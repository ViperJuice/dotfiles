---
name: execute-phase
description: "Executes a plan-phase plan doc to completion. Spawns one worktree-isolated teammate per swim lane via TeamCreate, respects the lane DAG and interface freeze gates, auto-merges lanes when their verify passes, and retries once on failure before halting. Assigns each teammate a model + thinking level matched to the lane's complexity. Run after /plan-phase has produced plans/phase-plan-<VERSION>-<PHASE_ALIAS>.md."
---

# execute-phase

Follow-on executor for `/plan-phase`. Consumes the plan doc + TaskCreate'd lane tasks and drives them to completion: root lanes first, parallel lanes in parallel, auto-merge on green, retry-once on failure, halt-all on second failure.

## When to use

- `/plan-phase` has produced `plans/phase-plan-<VERSION>-<PHASE_ALIAS>.md` and a `TaskCreate`'d task per lane.
- You want the phase executed **full-auto** end-to-end, with lanes merging to the current branch as their gates go green.
- The working tree is clean and you're on the branch lanes should merge into.

## When NOT to use

- Plan doc has never been produced → run `/plan-phase` first.
- You want human checkpoints between lanes → execute lanes manually (`Agent(isolation: "worktree", name: "<SL-ID>")` with the lane's section pasted in).
- The plan doc's DAG has cycles or a lane's owned files overlap another lane's → fix the plan first.

## Inputs

| Arg | Required | Meaning |
|---|---|---|
| `<plan-path>` | no | Path to plan doc. Default: auto-detected via env vars + filename convention. |
| `--dry-run` | no | Parse + validate, print the dispatch schedule with per-lane model assignments, do not spawn teammates. |
| `--resume` | no | Continue a partially executed plan: skip lanes already merged (their merge commit is on the target branch and their produced gates are closed). |

## Environment variables

Plan-location variables are inherited from `plan-phase` so the two skills resolve the same defaults:

| Variable | Default | Meaning |
|---|---|---|
| `PLAN_SPEC` | Auto-detected highest `specs/phase-plans-v*.md` | Path to spec file (used only for version extraction here). |
| `PLAN_VERSION` | Extracted `v\d+` from spec filename | Version token embedded in plan-doc filename. |
| `PLAN_PHASE_ALIASES` | Built-in P1–P7 table | Path to alias-map JSON. |
| `PLAN_DOC` | `plans/phase-plan-<VERSION>-<PHASE_ALIAS>.md` | Override the resolved plan-doc path directly. |
| `EXECUTE_MERGE_TARGET` | Current branch at invocation | Branch lanes merge into. |
| `EXECUTE_WORKTREE_ROOT` | `.worktrees/` (inside repo; auto-gitignored) | Root dir for per-lane worktrees. |

## Deferred tool preloading

Several core tools this skill uses are deferred in the current harness and must be registered via `ToolSearch` before first call. Load them at the top of Step 1 in a single query so mid-workflow calls (especially `TaskUpdate` on every dispatch and `AskUserQuestion` on preflight failures) don't pay a round-trip:

```
ToolSearch(query: "select:TaskCreate,TaskUpdate,TaskList,TeamCreate,AskUserQuestion")
```

## Workflow (orchestrator-only main thread)

The main thread reads **exactly two things**: the plan doc and the TaskList. It does not Grep/Read repo source — lane teammates own their files. If the main thread is reaching for Grep or Read on source files, the teammate brief was incomplete; re-brief via `SendMessage`.

### Step 1 — Resolve + parse plan doc

Resolve in order: `$PLAN_DOC` → `<plan-path>` arg → default path built from `$PLAN_VERSION` + phase alias argument.

`Read` the plan doc. Parse these sections (headings are stable IDs from `plan-phase`):

- `## Interface Freeze Gates` — list of `IF-0-<PHASE>-<N>` items with descriptions.
- `## Cross-Repo Gates` (optional) — `IF-XR-<N>`.
- `## Lane Index & Dependencies` — machine-readable DAG block (`SL-N`, `Depends on:`, `Blocks:`, `Parallel-safe:`).
- `## Lanes` — per-lane: `Scope`, `Owned files`, `Interfaces provided`, `Interfaces consumed`, task table.
- `## Verification` — final end-to-end commands.

Build the lane graph. Topologically sort it; **reject on cycle** with a clear error.

### Step 2 — Preflight

- `git status --porcelain` → must be empty. If not, stop and ask the user (via `AskUserQuestion`) whether to stash, commit, or abort.
- Record merge target = current branch (or `$EXECUTE_MERGE_TARGET`).
- Sanity check: every symbol appearing in any lane's `Interfaces consumed` must either be produced by an upstream lane's `Interfaces provided` OR be pre-existing (skip unknown symbols with a warning, don't hard-fail).
- Ensure `.gitignore` contains `.worktrees/` and `.claude/execute-phase-state.json`; if not, append.
- If `--dry-run`: print the topological schedule with per-lane model/thinking assignments (see Step 3) and stop here.

### Step 2a — Worktree hygiene preflight

Prior sessions that didn't complete Step 7's post-merge cleanup leave stale worktrees and branches in `.claude/worktrees/`. These accumulate silently (network drop mid-merge, orchestrator crash, manual execution that bypassed Step 7, etc.) and surface as noise during later debugging. Prune them at phase start.

Skip this step entirely on `--resume` — resume continues a partial phase whose worktrees are still live.

```bash
bash "$(git rev-parse --show-toplevel)/.claude/skills/execute-phase/scripts/sweep_stale_worktrees.sh"
# Pass --dry-run to preview decisions without removing anything.
```

For each worktree marked `PRUNE`:

1. `git worktree unlock <path>` (succeeds silently if unlocked; unlocks if locked).
2. `git worktree remove -f -f <path>` — double-force bypasses both the lock and the unmerged-changes check (safe since the ancestor check already confirmed incorporation).
3. `git branch -D <branch>` **only** if the branch name matches an auto-named pattern: `worktree-agent-*` or `phase/*/sl-*`. Leave human-named branches (`skills/*`, `feature/*`, `fix/*`, etc.) intact even when their work is on the merge target — the user may still want the branch reference.

Worktrees marked `KEEP` are left alone; log a one-line warning per worktree so the operator can inspect before the next session.

### Step 3 — Assign model + thinking per lane

Each lane gets a model and thinking level matched to its complexity. The assignment is encoded on the `Agent` call via `model:` and communicated as guidance in the brief.

**Heuristic (apply in order, first match wins):**

1. Lane has `Execution hint: <model>/<thinking>` inside its `### SL-N` section → use it verbatim.
2. Lane publishes any `IF-0-*` gate (contract-authoring) → **`claude-sonnet-4-6` / high**. Downstream lanes depend on the symbols being correct; pay for deliberation.
3. Lane scope mentions migrations, schema, or SQL → **`claude-sonnet-4-6` / high**. A bad migration is expensive to unwind.
4. Lane scope mentions algorithmic/computed logic AND has tests as first task → **`claude-sonnet-4-6` / medium**. Tests pin behavior; mid-tier reasoning is sufficient.
5. Lane owns >10 files AND publishes no interfaces (wiring / mechanical refactor) → **`claude-haiku-4-5` / low**. High volume, low per-file complexity.
6. Lane implements small components against already-frozen types → **`claude-haiku-4-5` / low**. Mechanical implementation, fast iteration.
7. Default fallback → **`claude-sonnet-4-6` / medium**.

**Retry escalation** (after a lane's first failure):

- `claude-haiku-4-5` → `claude-sonnet-4-6`
- `claude-sonnet-4-6` → `claude-opus-4-6`
- `claude-opus-4-6` → stay at `claude-opus-4-6`
- Thinking level bumps up one tier (`low → medium → high`).

Thinking level is conveyed to the teammate in the brief (e.g., `"Think carefully before editing shared type definitions"` or `"These are mechanical edits; move quickly"`), since `Agent` does not expose a direct thinking-level parameter — the brief's framing is the control surface.

### Step 4 — TeamCreate

Create one team for the phase:

- **Team name**: `phase-<PHASE_ALIAS>` (e.g., `phase-p1`).
- **Teammates**: one per lane, named `lane-<sl-id>` lowercased (e.g., `lane-sl-1`). `subagent_type: "general-purpose"`.

Registering teammates via TeamCreate lets the main thread re-address them later via `SendMessage` for retry rounds without paying the cost of a fresh Agent spawn.

### Step 5 — Dispatch loop

State per lane: `pending | running | verify-ok | merged | failed`.
State per gate: `open | closed`.

Repeat until all lanes are `merged` or halt is triggered:

1. **Find ready lanes** — `pending` lanes whose upstream lanes are all `merged` AND all consumed `IF-0-*` gates are `closed`. Then **cap the dispatch batch at `MAX_PARALLEL_LANES`** (default 2; configurable via env `EXECUTE_MAX_PARALLEL_LANES`). Slice the eligible set to the first N (lower SL-ID first) and queue the rest for the next round. Reason: full-parallel dispatch opens a multi-lane staleness window where each merge makes the others stale (Phase 1 P6 lesson). Wave dispatch with a small N shrinks the window without losing meaningful parallelism.
2. **Dispatch in parallel** — single message with one `Agent(team_name: "phase-<alias>", name: "lane-<sl-id>", subagent_type: "general-purpose", model: "<assigned>")` call per ready lane (up to `MAX_PARALLEL_LANES`). **Sequential dispatch within a wave is a bug.** **Do NOT pass `isolation: "worktree"` when `team_name` is also set** — the harness silently runs the teammate in-process, drops the isolation kwarg, and leaves all lanes writing into the parent checkout. The working pattern is `team_name` for coordination + teammate-called `EnterWorktree` for filesystem isolation (see the mandatory first-tool-call below). Each brief contains:
   - **Worktree isolation (mandatory, first tool call)**: Load `EnterWorktree` via `ToolSearch(query="select:EnterWorktree")` if not already in your tool registry. Call `EnterWorktree(name: "lane-<sl-id>")` as your very first action, BEFORE any file operation. The tool creates a git worktree at `.claude/worktrees/lane-<sl-id>/` on branch `worktree-lane-<sl-id>` and switches your session cwd into it. Every subsequent edit/commit goes into that worktree, not the parent. At the end, call `ExitWorktree(action: "keep")` so the worktree (and its branch) remain available for the orchestrator to merge.
   - The full `### SL-N` section copied verbatim from the plan doc.
   - Concrete upstream artifact paths (populated from now-merged upstream lanes) for every entry in `Interfaces consumed`.
   - The merge target branch and the orchestrator's current tip SHA, injected as `<TIP_SHA>` (used by the stale-base check below). Branch will be auto-named `worktree-lane-<sl-id>` by EnterWorktree — teammate confirms in the reply envelope, orchestrator doesn't assume.
   - The lane's test → impl → verify task list.
   - Thinking-level guidance matching the lane's profile.
   - **Stale-base discipline (mandatory)**: AFTER `EnterWorktree` returns (cwd now in your worktree), and BEFORE any code change, run `git rebase main` (or `git merge main --no-ff -m "merge: incorporate prior-lane foundation"`). Verify with `git merge-base --is-ancestor <TIP_SHA> HEAD && echo OK || echo STALE`. Repeat the rebase IMMEDIATELY before your final commit — peer lanes may have merged during your run. If the rebase produces conflicts, STOP and report rather than resolving silently. (P6 + Phase 1 lessons — Phase 1 had three lanes hit stale base because the prior reactive check required teammates to notice independently and most didn't until the orchestrator force-fed them remediation.)
   - Structured-reply instruction: "When done, reply with JSON `{lane, verify_exit_code, failed_tasks, notes, commit_sha, branch, worktree_path}`. **All six fields are mandatory.** `branch` and `worktree_path` come from `EnterWorktree`'s return value; they let the orchestrator verify isolation actually fired (not the silent-fallback-to-in-process case). Going idle without the full envelope blocks the orchestrator and forces an extra `SendMessage` round-trip."
3. **Await completions**. For each:
   - `verify_exit_code == 0` → run gate verification (Step 6). On green → auto-merge (Step 7). Mark lane `merged`, flip produced gates to `closed`, update the lane's `TaskCreate`'d task to `completed`.
   - Non-zero or gate failure → retry-once (Step 8).
   - **Idle without JSON reply** → `SendMessage` to the teammate by name asking for the envelope. If it still doesn't reply and a commit exists on a branch you can identify via `git branch` or `git log --all --oneline --author=<user>`, treat the commit as the result and proceed with Step 7's destructiveness check.
4. Persist lane + gate state to `.claude/execute-phase-state.json` after every transition (enables `--resume`).

### Step 6 — Gate verification

For each gate the lane provides:

1. If the plan doc's `## Verification` section has a command that names this gate's artifact (e.g., `psql` for schema gates, `grep` for symbol gates), run that command against the lane's worktree.
2. Else fall back to the three-part heuristic:
   - Files listed under `Owned files` exist.
   - Symbols listed under `Interfaces provided` are grep-visible at expected paths.
   - Lane's own verify command exited 0.

Any failure here counts as a lane failure and triggers retry-once.

### Step 6.5 — Parent-tree leakage check (before merge)

Worktree-isolated agents occasionally leak writes into the parent checkout even when not SendMessage-resumed (Lesson #10). The lane's commit is valid in its worktree branch AND the same edits appear as modified/untracked files in the parent. `git merge --no-ff` then aborts with "untracked files would be overwritten" and can panic an orchestrator that doesn't verify before acting.

Run a single-line probe in the parent before Step 7:

```bash
git status --porcelain
```

Interpret:

- **Output empty** → proceed to Step 7 unchanged.
- **Output non-empty AND every path falls within the lane's `Owned files` globs**:
  1. Verify byte-equality: for each leaked path, `git diff <lane-sha> -- <path>` must be zero lines. This confirms the leak is a redundant copy of the already-committed lane work, not independent uncommitted editing the operator started.
  2. Clean the parent: `git checkout -- <modified>` for tracked changes; `rm <untracked>` for new files. **Do NOT `git stash`** — stash can resurface the same leak at a later checkout/merge and re-trigger this failure.
  3. Record the action in `.claude/execute-phase-state.json` under the lane's `notes`: `"parent-tree leakage cleaned; lane commit is authoritative"`.
  4. Proceed to Step 7.
- **Output non-empty AND any path falls outside the lane's `Owned files`** → STOP. This is unexpected state: uncommitted operator edits, a sibling lane's leak, or a linter that fired between steps. Ask via `AskUserQuestion` whether to stash, commit, or abort. Do not auto-clean.

This check is cheap (one `git status`) and turns a silent foot-gun into a recoverable procedure.

### Step 7 — Auto-merge

**Branch discovery first.** The harness sometimes auto-names the lane branch (e.g., `worktree-agent-<id>`) rather than honoring the briefed `phase/<PHASE_ALIAS>/<sl-id>` convention, and two lanes occasionally share a worktree. Don't assume the branch name — resolve it from the teammate's reply envelope (`commit_sha`). Run `git worktree list` + `git log --oneline -1 <commit_sha>` to confirm the SHA exists and find the actual branch/worktree.

**MANDATORY pre-merge destructiveness check** (P6 lesson — 3 of 10 lanes in that phase committed against stale bases and would have wiped peer-lane work on `--no-ff` merge):

```bash
# Primary check: what does main..lane-sha show
git diff --stat main..<lane-sha> | tail -5
git diff --diff-filter=D --name-only main..<lane-sha>

# If the primary check shows deletions, run the ancestor-diff disambiguator
# to distinguish real-destructive commits from parallel-branch false positives
ANCESTOR=$(git merge-base main <lane-sha>)
git diff --diff-filter=D --name-only "$ANCESTOR"..<lane-sha>
```

Interpret:

- **Primary deletion list empty OR only contains files the lane legitimately deletes per its plan section** → safe to merge normally with `git merge --no-ff <lane-ref>`.
- **Primary deletion list contains files owned by *other* merged lanes, AND the ancestor-diff is EMPTY** → **parallel-branch false positive.** The lane branched from a pre-peer-merge main and simply doesn't contain peer files — it never actively deleted anything. Git's 3-way merge will preserve peer work correctly. Preview to confirm:
  ```bash
  git merge --no-ff --no-commit <lane-sha>
  ls <peer-lane-owned-paths>   # should exist
  git commit --no-edit           # finalize
  ```
  Do NOT salvage in this case — salvage loses the lane's original commit lineage unnecessarily. Record in state: `"parallel-branch false positive; 3-way merge preserved peer work"`.
- **Primary deletion list contains files owned by *other* merged lanes, AND the ancestor-diff is NON-EMPTY** → **real destructive commit.** The lane actively removed files via `git reset --hard`, `git checkout HEAD~N -- …`, or similar. **DO NOT `--no-ff` merge.** Salvage instead:
  ```bash
  git checkout <lane-sha> -- <lane's owned paths from the plan doc>
  git commit -m "feat(<phase>,<sl-id>): <subject>

  Salvage of <SL-ID> lane work: lane commit was based on stale main and
  would have deleted <peer lanes' files>. Cherry-picked in-scope additions only."
  ```
  Record the salvage in `.claude/execute-phase-state.json` under the lane's `notes`. This is a successful completion, not a failure — no retry needed. The destructive diff is a symptom of lane isolation breakdown (shared worktree, stale rebase), not of bad code.

**Merge conflict** (non-destructive case) → treat as lane failure: `git merge --abort`, surface the conflict to the teammate via `SendMessage` asking it to rebase inside its worktree, then retry the merge.

**Post-merge cleanup.** `git worktree remove --force` any worktrees that were used for the lane (including any the teammate squatted on that weren't its own). `git branch -D` every lane branch — **use `-D` not `-d`** because salvaged work leaves the original branch unreachable from the merge target. Cannot remove the worktree the orchestrator session itself is anchored to; skip it and note in state.

### Step 8 — Retry-once, then halt

On first failure for a lane, decide between SendMessage-resume and kill-and-respawn based on whether the lane committed anything:

- **`commit_sha` is empty AND `verify_exit_code != 0`** (e.g., teammate STOPed during preflight, no work done): kill via `TaskStop` and re-`Agent`-spawn fresh. Resuming a STOPed agent risks worktree-isolation breakdown — Phase 1's SL-3 was resumed via `SendMessage`, lost its worktree, and started writing into the parent checkout, scrambling sibling lanes' staging.
- **`commit_sha` populated AND verify failed** (teammate did work but it broke): re-address the same named teammate via `SendMessage`. Context preservation matters here; the teammate's understanding of its branch state is hard to rebuild from scratch.

In either case, the brief includes: the failure log, the escalated model+thinking hint, and the instruction to fix the failing task and re-run verify. Main thread may also upgrade the teammate's model at retry time if the harness supports it; if not, the escalation lives entirely in the brief's framing.

On second failure:

- Halt: cancel all still-running lane Agents via their task IDs.
- Emit a diagnostic report naming the failing lane, the failing task, the last ~30 log lines, and which lanes were merged vs pending.
- Persist state to `.claude/execute-phase-state.json` and exit cleanly. User can fix and re-run with `--resume`.

### Step 9 — Final verification + summary

After all lanes merged:

- Run every command under the plan doc's `## Verification` section against the merged tree.
- Run every assertion under `## Acceptance Criteria` that can be mechanically checked.
- Emit final summary:
  - Lanes merged (with merge-commit SHAs)
  - Gates closed
  - Final verification pass/fail
  - Total wall-clock duration
  - Per-lane breakdown: model used, duration, token spend, retry count
- Mark the phase's parent TaskCreate (if one exists) as completed.

## Lane state machine

```
pending ──► running ──► verify-ok ──► merged
                 │                        ▲
                 └─fail─► failed ─retry─►─┘ (once)
                                 │
                                 └─fail2─► HALT
```

## Parallelism contract

- All lanes whose dependencies are satisfied at the same time MUST be dispatched in the same message (parallel `Agent` tool calls).
- Lanes must not share files. The plan's lane-validation checklist guarantees disjoint ownership; execute-phase trusts the plan and does not re-verify file-glob intersections.
- Shared generated files (e.g., `packages/db-types/index.ts`) are called out in the plan's `## Execution Notes`; only the lane that lists them under `Owned files` may modify them.

## Model selection quick-reference

| Symptom in the plan doc | Assigned model | Thinking |
|---|---|---|
| `Scope` mentions schema / migration / SQL | `claude-sonnet-4-6` | high |
| `Interfaces provided` includes any `IF-0-*` gate | `claude-sonnet-4-6` | high |
| `Scope` mentions algorithm / compute / worker logic | `claude-sonnet-4-6` | medium |
| `Owned files` glob expands to >10 files, no interfaces provided | `claude-haiku-4-5` | low |
| `Scope` is "small components against frozen types" | `claude-haiku-4-5` | low |
| `Execution hint:` line is present in lane section | Use it verbatim | Use it verbatim |
| Retry | One tier up | One tier up |

## Output contract

On successful completion:

1. Every lane's branch merged into the target branch with a `--no-ff` commit, in topological order.
2. All lane worktrees removed; lane branches deleted.
3. All `TaskCreate`'d lane tasks marked `completed`.
4. `.claude/execute-phase-state.json` deleted (or the `status` field set to `complete`).
5. Final summary message to the user.

On halt:

1. Lanes that completed remain merged; their state is preserved.
2. `.claude/execute-phase-state.json` contains the failing lane's name, task, log tail, and which gates/lanes were green vs open.
3. User can `/execute-phase --resume` after fixing the blocker.

## Worktree layout

```
<repo>/
├── .worktrees/
│   ├── sl-1/      # worktree for lane SL-1, branch phase/<PHASE>/sl-1
│   ├── sl-2/
│   └── …
└── .claude/
    └── execute-phase-state.json   # lane + gate state, for --resume
```

Both paths are auto-added to `.gitignore` in Step 2.

## Teamwork posture (hard rules)

- **Main thread = dispatcher.** Reads plan doc + TaskList + git state. Never Greps or Reads source code during execution, *except* to run the pre-merge destructiveness check (Step 7) — that one is load-bearing.
- **Parallel-by-default.** Ready lanes dispatch in a single message, every round.
- **Name every teammate** (`lane-<sl-id>`). Retries go through `SendMessage` to preserve context.
- **TaskCreate tasks are the source of truth for lane status.** Update them as lanes transition.
- **No speculative refactoring.** Lane teammates must stay within their `Owned files` globs; reject their work at gate verification if they wandered.
- **Never trust a branch name.** The harness auto-names worktree branches and lanes sometimes squat on sibling worktrees. Resolve work by commit SHA from the reply envelope, not by branch convention.
- **Never `--no-ff` merge without the destructiveness check.** Step 7's `git diff --diff-filter=D` is non-negotiable.

## Lessons from P6 (mandatory reading)

These failure modes appeared 3× in a single phase and will recur. Bake them into your mental model.

1. **Stale-base destructive commits.** A lane teammate in an isolated worktree doesn't see peer lanes' merges. If its worktree base is main-at-spawn-time and it ran any of `git checkout HEAD~N -- …`, `git reset --hard`, or a fresh `git add -A` after clobbering files, its commit will show peer-lane work as *deleted* when diffed against current main. The `--no-ff` merge then destroys that work silently. **Defense**: Step 7's pre-merge diff check.

2. **Cherry-pick salvage is a success outcome.** When destructiveness is detected, don't retry the lane — the teammate did the right work, it just got mis-based. Salvage only the additive paths per the plan's `Owned files`. Record `notes: "lane commit was based on stale main; only the new X paths were cherry-picked"` in state.

3. **Shared worktree scrambling.** If two lanes get assigned the same physical worktree path (happens under harness contention), the second lane's commit sits on top of the first's branch. Branch `phase/p6/sl-10` can end up pointing at SL-8's work. Resolve by commit SHA, never by branch name.

4. **Idle-without-JSON reply.** Teammates sometimes send `idle_notification` without the structured result envelope. First retry: `SendMessage` asking for the envelope. If still silent and a commit exists, proceed with that commit as the implicit result. Never block the phase on missing JSON when the artifact is on disk.

5. **In-process teammates ignore `shutdown_request`.** `TeamDelete` blocks on active members. If a teammate is `backendType: "in-process"` and not acking shutdown, `rm -rf ~/.claude/teams/<team>` + `rm -rf ~/.claude/tasks/<team>` is the accepted tear-down path after the phase has verified green.

6. **Leftover dev servers.** Lane teammates occasionally spawn `next dev` or worker processes that outlive their termination. Include a `ps aux | grep -E "next dev|node.*dev"` check in the final cleanup and `kill` any stragglers.

## Lessons from Phase 1 (governed-pipeline isolation refactor)

These extend the P6 lessons with three concrete failure modes that hit during the five-lane Phase 1 dispatch.

7. **Worktree base ≠ live `main`.** `EnterWorktree` creates each worktree from the teammate's current HEAD at spawn time, which is session-start main — not the orchestrator's live main. Every lane in Phase 1 needed an explicit rebase before the actual work began. The "Stale-base discipline (mandatory)" clause in Step 5's brief addresses this — proactive rebase-on-spawn instead of the older reactive "if you find yourself…" check. The teammate must `git rebase main` immediately after `EnterWorktree` AND immediately before the final commit (peers may have merged during the run). NOTE: the old version of this lesson referenced `Agent(isolation: "worktree")` as the mechanism; that kwarg is silently dropped when `team_name` is also set — see Lesson #12.

8. **Full-parallel dispatch creates a multi-lane staleness window.** Phase 1 dispatched SL-2 + SL-3 + SL-5 simultaneously after SL-1; each merge made the others stale. SL-2's diff-against-main showed SL-5's just-merged files as deletions (P6 lesson #1 fired correctly, salvage worked, but the near-miss cost an extra orchestration round). Step 5's `MAX_PARALLEL_LANES` cap (default 2) shrinks the window without losing meaningful parallelism.

9. **`SendMessage`-resume to a STOPed agent loses worktree isolation.** Phase 1's SL-3 was STOPed during preflight (no commits made), then `SendMessage`-resumed by the orchestrator. The original worktree had been reaped; the resumed instance wrote into the parent checkout, scrambling sibling lanes' staging mid-orchestration. Under the EnterWorktree pattern this is still a hazard but narrower: the teammate's worktree persists across their own turns, so SendMessage-resume is safe when `commit_sha` is populated. **Defense unchanged**: Step 8's conditional — if `commit_sha` is empty AND verify failed, kill via `TaskStop` and re-`Agent`-spawn fresh (the fresh spawn's teammate re-enters a worktree from a current HEAD). SendMessage-resume is correct ONLY when the lane committed work but verify failed.

## Lessons from Phase 3 (governed-pipeline reingestion detection)

10. **Worktree-isolated agents can leak writes into the parent checkout even without resume.** Distinct from Lesson #9: here a fresh `Agent(isolation: "worktree")` spawn — never STOPed, never `SendMessage`-resumed — committed cleanly to its own worktree branch AND simultaneously wrote byte-identical copies of the same files into the parent checkout. Likely root cause is path-resolution inside the agent's Write/Edit tools occasionally resolving absolute-looking paths against the parent repo instead of the worktree. The lane's commit in its worktree is usually correct and authoritative; the parent tree is the stale artifact that blocks `git merge --no-ff` with "untracked files would be overwritten." **Defense**: Step 6.5's parent-tree leakage check — `git status --porcelain` in the parent before merging, verify byte-equality with the lane SHA, clean the parent, then merge the lane commit normally.

11. **`git diff main..lane-sha` can't distinguish real-destructive commits from parallel-branch false positives.** Both produce the same deletion list. In Phase 3, SL-3-B branched from pre-SL-3-A-merge main and never touched A's files; `main..B` showed A's 5 files as "deletions" even though git's 3-way merge would (and did) preserve them correctly. The original Step 7 recipe would have triggered an unnecessary salvage. **Defense**: the extended Step 7 check now runs a second diff against the true ancestor (`git merge-base main <sha>`) — if that diff shows zero deletions, the lane never actively removed anything and is safe for `--no-ff` merge. Only a non-empty ancestor-diff indicates real destruction. `scripts/pre_merge_destructiveness_check.sh <lane-sha> <merge-target> <whitelist-path>` implements this three-outcome verdict deterministically.

12. **`Agent(isolation: "worktree")` + `team_name` silently falls back to in-process.** Observed empirically across Phase 1 and Phase 2A: every team-spawned lane member had `backendType: "in-process"` in `~/.claude/teams/<team>/config.json`, `git worktree list` showed only the parent checkout, and all lanes committed linearly onto `main` in the parent. The harness accepts both kwargs but applies only one — team membership wins and isolation is dropped. The working pattern is team membership for coordination (`Agent(team_name=…)`) combined with teammate-called `EnterWorktree` for filesystem isolation (verified via a toy experiment: teammate-called EnterWorktree produces a real worktree at `.claude/worktrees/<name>/` on branch `worktree-<name>`, with per-lane commits landing on that branch only and main unchanged). **Defense**: Step 5.2 dispatches `Agent` WITHOUT the `isolation` kwarg; the teammate's brief mandates `EnterWorktree` as its first tool call; the reply envelope includes `worktree_path` and `branch` so the orchestrator can verify isolation actually fired (worktree_path should be under `.claude/worktrees/`, not the parent checkout).

## Browser verification capabilities

When a plan's `## Verification` section includes Playwright/e2e commands or lane tasks ask for browser smoke-testing, the main thread (and lane teammates) have these tools available and should use them rather than skipping the step:

- **Playwright via PMCP** — `pmcp_invoke(tool_id="playwright::browser_navigate", ...)` and related `playwright::*` tools. Covers navigation, clicks, form fills, screenshots, console/network inspection. Preferred for all browser automation.
- **Chrome DevTools Protocol (CDP)** — available for low-level debugging when Playwright's API isn't enough (e.g., performance traces, CPU profiling).
- **`claude-in-chrome`** — extension-context automation; only used when the task needs Chrome extension APIs.

Do not mark a lane "verified" by skipping its Playwright step on the grounds that a harness isn't wired — the PMCP Playwright server provisions on demand. If the repo lacks a Playwright config, add one in the lane rather than deferring the test.
