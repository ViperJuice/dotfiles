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
| `PLAN_PHASE_ALIASES` | Built-in alias table | Path to alias-map JSON. |
| `PLAN_DOC` | `plans/phase-plan-<VERSION>-<PHASE_ALIAS>.md` | Override the resolved plan-doc path directly. |
| `EXECUTE_MERGE_TARGET` | Current branch at invocation | Branch lanes merge into. |
| `EXECUTE_WORKTREE_ROOT` | `.worktrees/` (inside repo; auto-gitignored) | Root dir for per-lane worktrees. |
| `EXECUTE_MAX_PARALLEL_LANES` | `2` | Max concurrent lane dispatches per wave. Keep small: each merge makes the other running lanes' bases stale. |

## Deferred tool preloading

Several tools this skill uses are deferred and must be registered via `ToolSearch` before first call. Load them in a single query at the top of Step 1 so mid-workflow calls (especially `TaskUpdate` on every dispatch and `AskUserQuestion` on preflight failures) don't pay a round-trip:

```
ToolSearch(query: "select:TaskCreate,TaskUpdate,TaskList,TeamCreate,AskUserQuestion")
```

## Workflow (orchestrator-only main thread)

The main thread reads exactly two things: the plan doc and the TaskList. It does not Grep/Read repo source — lane teammates own their files. If the main thread is reaching for Grep or Read on source files, the teammate brief was incomplete; re-brief via `SendMessage`.

### Step 1 — Resolve + parse plan doc

Resolve in order: `$PLAN_DOC` → `<plan-path>` arg → default path built from `$PLAN_VERSION` + phase alias argument.

`Read` the plan doc. Parse these sections (headings are stable IDs from `plan-phase`):

- `## Interface Freeze Gates` — list of `IF-0-<PHASE>-<N>` items with descriptions.
- `## Cross-Repo Gates` (optional) — `IF-XR-<N>`.
- `## Lane Index & Dependencies` — machine-readable DAG block (`SL-N`, `Depends on:`, `Blocks:`, `Parallel-safe:`).
- `## Lanes` — per-lane: `Scope`, `Owned files`, `Interfaces provided`, `Interfaces consumed`, task table.
- `## Verification` — final end-to-end commands.

Build the lane graph. Topologically sort it; reject on cycle with a clear error.

### Step 2 — Preflight

- **Run `scripts/verify_harness.sh <merge-target>`.** This script enforces the hard gates deterministically: git + git-worktree available, inside a work tree, merge-target branch exists locally, working tree clean (allowlist: `.claude/worktrees/`, `.claude/execute-phase-state.json`), `.gitignore` covers worktree paths. **Non-zero exit blocks dispatch.** The dirty-tree check has no orchestrator-side override — if it fails, you MUST invoke `AskUserQuestion` with the options `[commit the changes as a chore, stash for the duration of the phase, abort /execute-phase]` and take the user's answer. Do not rationalize around a dirty tree even if the diff looks like "noise" — test-run artifacts and config drift are state changes that deserve a commit decision.
- Record merge target = current branch (or `$EXECUTE_MERGE_TARGET`).
- Sanity check: every symbol appearing in any lane's `Interfaces consumed` must either be produced by an upstream lane's `Interfaces provided` OR be pre-existing (skip unknown symbols with a warning, don't hard-fail).
- If `--dry-run`: print the topological schedule with per-lane model/thinking assignments (see Step 3) and stop here.

### Step 2a — Worktree hygiene preflight

Prior sessions that didn't complete Step 7's post-merge cleanup leave stale worktrees and branches in `.claude/worktrees/`. Prune them at phase start. Skip on `--resume` (resume continues a partial phase whose worktrees are still live).

```bash
bash "$(git rev-parse --show-toplevel)/.claude/skills/execute-phase/scripts/sweep_stale_worktrees.sh"
# Pass --dry-run to preview decisions without removing anything.
```

For each worktree marked `PRUNE`:

1. `git worktree unlock <path>` (succeeds silently if unlocked).
2. `git worktree remove -f -f <path>` — double-force bypasses both the lock and the unmerged-changes check (safe since the ancestor check already confirmed incorporation).
3. `git branch -D <branch>` **only** if the branch name matches an auto-named pattern (`worktree-*`, `phase/*/sl-*`). Leave human-named branches (`skills/*`, `feature/*`, `fix/*`) intact even when their work is on the merge target — the user may still want the reference.

Worktrees marked `KEEP` are left alone; log a one-line warning per worktree.

### Step 3 — Assign model + thinking per lane

Each lane gets a model and thinking level matched to its complexity. The assignment is encoded on the `Agent` call via `model:` and communicated as guidance in the brief.

Apply in order, first match wins:

1. Lane has `Execution hint: <model>/<thinking>` inside its `### SL-N` section → use it verbatim.
2. Lane publishes any `IF-0-*` gate (contract-authoring) → `claude-sonnet-4-6` / high. Downstream lanes depend on the symbols being correct.
3. Lane scope mentions migrations, schema, or SQL → `claude-sonnet-4-6` / high. Bad migrations are expensive to unwind.
4. Lane scope mentions algorithmic/computed logic AND has tests as first task → `claude-sonnet-4-6` / medium.
5. Lane owns >10 files AND publishes no interfaces (wiring / mechanical refactor) → `claude-haiku-4-5` / low.
6. Lane implements small components against already-frozen types → `claude-haiku-4-5` / low.
7. Default fallback → `claude-sonnet-4-6` / medium.

**Retry escalation** (after a lane's first failure):

- `claude-haiku-4-5` → `claude-sonnet-4-6`
- `claude-sonnet-4-6` → `claude-opus-4-6`
- `claude-opus-4-6` → stay at `claude-opus-4-6`
- Thinking level bumps up one tier (`low → medium → high`).

`Agent` does not expose a direct thinking-level parameter — convey it in the brief's framing (e.g., "Think carefully before editing shared type definitions" vs "These are mechanical edits; move quickly").

### Step 4 — TeamCreate

Create one team for the phase:

- **Team name**: `phase-<PHASE_ALIAS>` (e.g., `phase-p1`).
- **Teammates**: one per lane, `subagent_type: "general-purpose"`. Teammate names use the allocator — see Step 5.

Registering teammates via TeamCreate lets the main thread re-address them later via `SendMessage` for retry rounds without paying the cost of a fresh Agent spawn.

### Step 5 — Dispatch loop

State per lane: `pending | running | verify-ok | merged | failed`. State per gate: `open | closed`.

Repeat until all lanes are `merged` or halt is triggered:

1. **Find ready lanes** — `pending` lanes whose upstream lanes are all `merged` AND all consumed `IF-0-*` gates are `closed`. Cap the dispatch batch at `EXECUTE_MAX_PARALLEL_LANES` (default 2). Slice the eligible set to the first N (lower SL-ID first) and queue the rest. Wave dispatch with a small N shrinks the multi-lane staleness window — each merge makes the other running lanes' bases stale — without losing meaningful parallelism.

2. **Allocate worktree names**. For each ready lane, run `scripts/allocate_worktree_name.sh <sl-id>`. The emitted name (e.g., `lane-sl-1-20260418T144536-nxz5`) is substituted into both the `Agent(name=…)` and the briefed `EnterWorktree(name=…)`. Bare `lane-<sl-id>` names collide under rapid in-process dispatch; unique names do not.

3. **Dispatch in parallel** — single message with one `Agent(team_name: "phase-<alias>", name: "<allocated-name>", subagent_type: "general-purpose", model: "<assigned>")` call per ready lane. Sequential dispatch within a wave is a bug. Do NOT pass `isolation: "worktree"` when `team_name` is also set — the harness silently runs the teammate in-process and drops the isolation kwarg. The working pattern is `team_name` for coordination + teammate-called `EnterWorktree` for filesystem isolation.

4. **Teammate brief** contains:
   - **Worktree isolation (mandatory, first tool call)**: Load `EnterWorktree` via `ToolSearch(query="select:EnterWorktree,ExitWorktree")` if not already in the tool registry. Call `ExitWorktree(action="keep")` FIRST (no-op if no session active; clears any stale session-state flag inherited from a prior teammate). Then call `EnterWorktree(name: "<allocated-name>")` as the very next tool call, BEFORE any file operation. Every subsequent edit/commit goes into that worktree. At the end, call `ExitWorktree(action: "keep")` so the worktree and branch remain available for the orchestrator to merge.
   - The full `### SL-N` section copied verbatim from the plan doc.
   - Concrete upstream artifact paths (populated from now-merged upstream lanes) for every entry in `Interfaces consumed`.
   - The merge target branch and the orchestrator's current tip SHA, injected as `<TIP_SHA>` (used by the stale-base check below).
   - The lane's test → impl → verify task list.
   - Thinking-level guidance matching the lane's profile.
   - **Stale-base discipline**: AFTER `EnterWorktree` returns (cwd now in your worktree), and BEFORE any code change, run `git rebase main` (or `git merge main --no-ff -m "merge: incorporate prior-lane foundation"`). Verify with `git merge-base --is-ancestor <TIP_SHA> HEAD && echo OK || echo STALE`. Repeat the rebase IMMEDIATELY before your final commit — peer lanes may have merged during your run. If the rebase produces conflicts, STOP and report rather than resolving silently. Silent `git reset --hard` or `git checkout HEAD~N -- …` in a stale worktree produces commits that destroy peer-lane work on `--no-ff` merge.
   - **Structured-reply instruction**: "When done, reply with JSON `{lane, verify_exit_code, failed_tasks, notes, commit_sha, branch, worktree_path}`. All six fields are mandatory. `branch` and `worktree_path` come from `EnterWorktree`'s return value; they let the orchestrator verify isolation actually fired. Going idle without the full envelope forces an extra `SendMessage` round-trip."

5. **Await completions**. For each:
   - `verify_exit_code == 0` → run gate verification (Step 6). On green → auto-merge (Step 7). Mark lane `merged`, flip produced gates to `closed`, update the lane's `TaskCreate`'d task to `completed`.
   - Non-zero or gate failure → retry-once (Step 8).
   - **Idle without JSON reply** → `SendMessage` to the teammate by name asking for the envelope. If it still doesn't reply and a commit exists on a branch you can identify via `git branch` or `git log --all --oneline --author=<user>`, treat the commit as the result and proceed with Step 7's destructiveness check. Never block the phase on missing JSON when the artifact is on disk.

6. Persist lane + gate state to `.claude/execute-phase-state.json` after every transition (enables `--resume`).

### Step 6 — Gate verification

For each gate the lane provides:

1. If the plan doc's `## Verification` section has a command that names this gate's artifact (e.g., `psql` for schema gates, `grep` for symbol gates), run it against the lane's worktree.
2. Else fall back:
   - Files listed under `Owned files` exist.
   - Symbols listed under `Interfaces provided` are grep-visible at expected paths.
   - Lane's own verify command exited 0.

Any failure here counts as a lane failure and triggers retry-once.

### Step 6.5 — Parent-tree leakage check

Worktree-isolated teammates occasionally write into the parent checkout — path resolution inside Edit/Write tools sometimes resolves absolute-looking paths against the parent repo. `git merge --no-ff` then aborts with "untracked files would be overwritten". A silent `EnterWorktree` fallback (collision on the worktree name) also manifests here as the parent sitting on the lane's branch with a clean tree.

Run:
```bash
bash scripts/parent_tree_leakage_check.sh <lane-id> <owned-globs-file> <merge-target>
```

Verdicts (emitted on stdout; details on stderr):

- **`CLEAN`** — proceed to Step 7.
- **`LEAKAGE_DETECTED`** (dirty files overlap the lane's owned globs):
  1. Verify byte-equality: for each leaked path, `git diff <lane-sha> -- <path>` must be zero lines. Confirms the leak is a redundant copy of already-committed lane work, not independent uncommitted editing.
  2. Clean the parent: `git checkout -- <modified>` for tracked changes; `rm <untracked>` for new files. Do NOT `git stash` — stash can resurface the same leak at a later checkout/merge.
  3. Record in `.claude/execute-phase-state.json` under the lane's `notes`.
  4. Proceed to Step 7.
- **`UNRELATED_DIRTY_TREE`** (dirty files outside the lane's globs) → STOP. Ask via `AskUserQuestion` whether to stash, commit, or abort.
- **`PARENT_ON_WRONG_BRANCH`** (tree clean but parent on a non-merge-target branch — `EnterWorktree` silently fell back to in-place branch creation):
  1. The lane's commit is on a branch; isolation just didn't fire.
  2. Merge by SHA per the no-branch-trust rule below (Step 7).
  3. Run `git checkout <merge-target>` in the parent BEFORE Step 7's worktree cleanup, or `git worktree remove` will refuse (the parent holds a worktree for the lane branch).
  4. Record in state: parent-fallback note.

### Step 7 — Auto-merge

**Branch discovery.** Don't trust briefed branch names — the harness sometimes auto-names branches, and lanes occasionally squat on sibling worktrees. Resolve from the reply envelope's `commit_sha`: `git log --oneline -1 <commit_sha>` + `git worktree list` to confirm the SHA and find the actual branch/worktree.

**Cross-lane file-touch audit.** Before the destructiveness check, run:

```bash
python scripts/audit_lane_file_touches.py <lane-sha> <plan-doc-path> <this-lane-id>
```

Verdicts:

- **`CLEAN`** → every touched file is within this lane's `Owned files` globs. Proceed.
- **`PEER_INTRUSION`** → the lane touched files owned by another lane (defensive test mocks are the common case). Stderr lists peer + files. Pause on `AskUserQuestion`: merge anyway, bounce the lane, or ask the teammate to revert the peer edits.
- **`ORPHAN_FILES`** → the lane touched files outside every lane's globs. Probable bug in the plan or the impl — surface to user.

**Pre-merge destructiveness check** — lanes that committed against a stale base can wipe peer-lane work on `--no-ff` merge. Use the three-outcome script:

```bash
bash scripts/pre_merge_destructiveness_check.sh <lane-sha> <merge-target> <whitelist-path>
```

Where `<whitelist-path>` is a file (one path per line) of deletions the lane legitimately performs per its plan section; `/dev/null` if the lane is purely additive.

Verdicts:

- **`SAFE`** — deletion list empty or all whitelisted. Merge with `git merge --no-ff <lane-sha>`.
- **`STALE_BASE_DETECTED`** — the lane branched from a pre-peer-merge main and doesn't contain peer files; it never actively deleted anything. Git's 3-way merge will preserve peer work. Preview to confirm, then finalize:
  ```bash
  git merge --no-ff --no-commit <lane-sha>
  ls <peer-lane-owned-paths>   # should exist
  git commit --no-edit
  ```
  Do NOT salvage — salvage loses the lane's original commit lineage unnecessarily.
- **`CONFLICT`** — the lane actively removed files (`git reset --hard`, `git checkout HEAD~N -- …`, or `git add -A` after clobbering). DO NOT `--no-ff` merge. Salvage:
  ```bash
  git checkout <lane-sha> -- <lane's owned paths from the plan doc>
  git commit -m "feat(<phase>,<sl-id>): <subject>

  Salvage of <SL-ID> lane work: lane commit was based on stale main and
  would have deleted <peer lanes' files>. Cherry-picked in-scope additions only."
  ```
  This is a successful completion, not a failure — no retry needed. The destructive diff is a symptom of isolation breakdown (shared worktree, stale rebase), not of bad code.

**Merge conflict** (non-destructive case) → treat as lane failure: `git merge --abort`, surface the conflict to the teammate via `SendMessage` asking it to rebase inside its worktree, then retry the merge.

**Post-merge import smoke** — run immediately after `git merge --no-ff` and before dispatching the next wave:

```bash
packages="$(git diff --name-only HEAD~..HEAD \
    | grep '__init__\.py$' \
    | sed 's|/__init__\.py$||; s|/|.|g' \
    | sort -u)"
if [[ -n "$packages" ]]; then
    bash scripts/post_merge_import_smoke.sh $packages
fi
```

Non-zero exit means the merge broke package load (eager re-export + dropped symbol, circular import, missing import). The merge is already on `main`, so `git reset --hard HEAD~` to unwind, then retry per Step 8. Second failure halts the phase.

**Post-merge cleanup.** `git worktree remove --force` any worktrees the lane used. `git branch -D` every lane branch — use `-D` not `-d` because salvaged work leaves the original branch unreachable from the merge target. If Step 6.5 returned `PARENT_ON_WRONG_BRANCH`, `git checkout <merge-target>` in the parent BEFORE removing worktrees.

### Step 8 — Retry-once, then halt

On first failure for a lane, decide between SendMessage-resume and kill-and-respawn based on whether the lane committed anything:

- **`commit_sha` empty AND `verify_exit_code != 0`** (teammate STOPed during preflight, no work done): kill via `TaskStop` and re-`Agent`-spawn fresh. Resuming a STOPed teammate risks worktree-isolation breakdown — the original worktree may have been reaped, and the resumed instance writes into the parent checkout instead.
- **`commit_sha` populated AND verify failed** (teammate did work but it broke): re-address the same named teammate via `SendMessage`. Context preservation matters here; the teammate's understanding of its branch state is hard to rebuild from scratch.

In either case, the brief includes: the failure log, the escalated model+thinking hint, and the instruction to fix the failing task and re-run verify.

On second failure:

- Cancel all still-running lane Agents via their task IDs.
- Emit a diagnostic report naming the failing lane, the failing task, the last ~30 log lines, and which lanes were merged vs pending.
- Persist state to `.claude/execute-phase-state.json` and exit cleanly. User can fix and re-run with `--resume`.

### Step 9 — Final verification, cleanup, and summary

After all lanes merged:

1. Run every command under the plan doc's `## Verification` section against the merged tree.
2. Run every assertion under `## Acceptance Criteria` that can be mechanically checked.
3. **Team teardown**. Try `TeamDelete` first. If it blocks (in-process teammates ignore `shutdown_request`), fall back to filesystem cleanup: `bash scripts/team_teardown.sh phase-<alias>` (rm on `~/.claude/teams/<team>/` + `~/.claude/tasks/<team>/`).
4. **Kill leftover background processes**. Lane teammates occasionally spawn `next dev` or worker processes that outlive their termination. Run `ps aux | grep -E "next dev|node.*dev"` and `kill` any stragglers.
5. Emit final summary:
   - Lanes merged (with merge-commit SHAs)
   - Gates closed
   - Final verification pass/fail
   - Total wall-clock duration
   - Per-lane breakdown: model used, duration, token spend, retry count
6. Mark the phase's parent TaskCreate (if one exists) as completed.

## Lane state machine

```
pending ──► running ──► verify-ok ──► merged
                 │                        ▲
                 └─fail─► failed ─retry─►─┘ (once)
                                 │
                                 └─fail2─► HALT
```

## Parallelism contract

- All lanes whose dependencies are satisfied at the same time MUST be dispatched in the same message (parallel `Agent` tool calls), up to `EXECUTE_MAX_PARALLEL_LANES`.
- Lanes must not share files. The plan's lane-validation checklist guarantees disjoint ownership; execute-phase trusts the plan and does not re-verify file-glob intersections.
- Shared generated files (e.g., barrel index files, generated types) are called out in the plan's `## Execution Notes`; only the lane that lists them under `Owned files` may modify them.

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
5. Team torn down via `TeamDelete` or `team_teardown.sh`.
6. Final summary message to the user.

On halt:

1. Lanes that completed remain merged; their state is preserved.
2. `.claude/execute-phase-state.json` contains the failing lane's name, task, log tail, and which gates/lanes were green vs open.
3. User can `/execute-phase --resume` after fixing the blocker.

## Worktree layout

```
<repo>/
├── .claude/
│   ├── worktrees/
│   │   ├── lane-sl-1-<timestamp>-<random>/
│   │   └── …
│   └── execute-phase-state.json
```

Both paths are auto-added to `.gitignore` in Step 2.

## Teamwork posture (hard rules)

- **Main thread = dispatcher.** Reads plan doc + TaskList + git state. Never Greps or Reads source code during execution, except to run the pre-merge destructiveness check and audit (Step 7) — those are load-bearing.
- **Parallel-by-default.** Ready lanes dispatch in a single message, every round.
- **Name every teammate via the allocator.** Bare `lane-<sl-id>` names collide in rapid in-process dispatch.
- **TaskCreate tasks are the source of truth for lane status.** Update them as lanes transition.
- **No speculative refactoring.** Lane teammates must stay within their `Owned files` globs; reject their work at gate verification if they wandered. Use the file-touch audit to catch this pre-merge.
- **Never trust a branch name.** Resolve work by commit SHA from the reply envelope, not by branch convention. The harness sometimes auto-names branches and lanes occasionally squat on sibling worktrees.
- **Never `--no-ff` merge without the destructiveness check.**
- **Never resume a STOPed teammate with no commits.** Kill + respawn instead; the worktree is gone and the resumed instance writes into the parent.
- **Never rationalize past a dirty-tree preflight fail.** `verify_harness.sh` is the gate. If check (4) fails, the ONLY paths forward are: (a) commit the diff as a `chore:`, (b) `git stash push -u` and restore post-phase, (c) abort. No "it's just a test-run artifact" exceptions.

## Browser verification capabilities

When a plan's `## Verification` section includes Playwright/e2e commands or lane tasks ask for browser smoke-testing, use these tools rather than skipping the step:

- **Playwright via PMCP** — `pmcp_invoke(tool_id="playwright::browser_navigate", ...)` and related `playwright::*` tools. Preferred for all browser automation.
- **Chrome DevTools Protocol (CDP)** — for low-level debugging (performance traces, CPU profiling).
- **`claude-in-chrome`** — extension-context automation only.

The PMCP Playwright server provisions on demand. If the repo lacks a Playwright config, add one in the lane rather than deferring the test.
