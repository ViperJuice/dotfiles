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

1. **Find ready lanes** — `pending` lanes whose upstream lanes are all `merged` AND all consumed `IF-0-*` gates are `closed`.
2. **Dispatch in parallel** — single message with one `Agent(isolation: "worktree", name: "lane-<sl-id>", subagent_type: "general-purpose", model: "<assigned>")` call per ready lane. **Sequential dispatch is a bug.** Each brief contains:
   - The full `### SL-N` section copied verbatim from the plan doc.
   - Concrete upstream artifact paths (populated from now-merged upstream lanes) for every entry in `Interfaces consumed`.
   - The merge target branch. **Do NOT promise a specific lane branch name** — the harness may auto-name the worktree branch; tell the teammate "work in your auto-named worktree branch" and report the final SHA in its reply envelope. Branch-name assumptions in the orchestrator are bugs waiting to happen.
   - The lane's test → impl → verify task list.
   - Thinking-level guidance matching the lane's profile.
   - **Staleness warning**: "If you find yourself working against a worktree whose HEAD is not on current `main`, your base is stale. Rebase onto `origin/main` before committing, OR stop and report so the orchestrator can re-spawn you." (P6 lesson — lane teammates silently committed on stale sibling branches.)
   - Structured-reply instruction: "When done, reply with JSON `{lane, verify_exit_code, failed_tasks, notes, commit_sha}`. **The JSON is mandatory** — going idle without it blocks the orchestrator and forces an extra `SendMessage` round-trip."
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

### Step 7 — Auto-merge

**Branch discovery first.** The harness sometimes auto-names the lane branch (e.g., `worktree-agent-<id>`) rather than honoring the briefed `phase/<PHASE_ALIAS>/<sl-id>` convention, and two lanes occasionally share a worktree. Don't assume the branch name — resolve it from the teammate's reply envelope (`commit_sha`). Run `git worktree list` + `git log --oneline -1 <commit_sha>` to confirm the SHA exists and find the actual branch/worktree.

**MANDATORY pre-merge destructiveness check** (P6 lesson — 3 of 10 lanes in that phase committed against stale bases and would have wiped peer-lane work on `--no-ff` merge):

```bash
git diff --stat main..<lane-sha> | tail -5
git diff --diff-filter=D --name-only main..<lane-sha>
```

Interpret:

- **Deletion list is empty OR only contains files the lane legitimately deletes per its plan section** → safe to merge normally with `git merge --no-ff <lane-ref>`.
- **Deletion list contains files owned by *other* merged lanes** → the lane was based on a stale main. **DO NOT `--no-ff` merge.** Salvage instead:
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

On first failure for a lane:

- Re-address the same named teammate via `SendMessage` (**never** spawn a new `Agent` — context preservation matters).
- Brief includes: the failure log, the escalated model+thinking hint, and the instruction to fix the failing task and re-run verify.
- Main thread may also upgrade the teammate's model at retry time if the harness supports it; if not, the escalation lives entirely in the brief's framing.

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

## Browser verification capabilities

When a plan's `## Verification` section includes Playwright/e2e commands or lane tasks ask for browser smoke-testing, the main thread (and lane teammates) have these tools available and should use them rather than skipping the step:

- **Playwright via PMCP** — `pmcp_invoke(tool_id="playwright::browser_navigate", ...)` and related `playwright::*` tools. Covers navigation, clicks, form fills, screenshots, console/network inspection. Preferred for all browser automation.
- **Chrome DevTools Protocol (CDP)** — available for low-level debugging when Playwright's API isn't enough (e.g., performance traces, CPU profiling).
- **`claude-in-chrome`** — extension-context automation; only used when the task needs Chrome extension APIs.

Do not mark a lane "verified" by skipping its Playwright step on the grounds that a harness isn't wired — the PMCP Playwright server provisions on demand. If the repo lacks a Playwright config, add one in the lane rather than deferring the test.
