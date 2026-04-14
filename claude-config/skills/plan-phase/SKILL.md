---
name: plan-phase
description: "Architecture-first planning for a spec phase. Produces an interface-freeze + swim-lane document for parallel execution. Use in plan mode. Supports --consensus for multi-agent architectural consensus across named Plan teammates."
---

# plan-phase

Architecture-first planner for a single phase of a multi-phase specification. Produces a plan document containing interface freezes, swim lanes with disjoint file ownership, a lane DAG, per-lane task lists (test → impl → verify), and testable acceptance criteria. Designed to be run in **plan mode** and handed off to a future `execute-phase` skill (or manual per-lane worktree agents) for parallel execution.

## When to use

- The input is a **multi-phase spec** (e.g., `specs/v1.md`) and the user wants to plan a specific phase.
- The work touches **more than one area** of the codebase and would benefit from parallel lane execution.
- You need **interface contracts frozen** before lanes diverge.

## When NOT to use

- Single-file, single-concern change → use `/plan-detailed` instead.
- Pure research / "how does X work" → use `Agent(subagent_type: "Explore")` directly, no plan doc needed.
- No phase structure in the spec → use `/plan-detailed` or ad-hoc planning.

## Inputs

| Arg | Required | Meaning |
|---|---|---|
| `<spec-path>` | **no** | Path to the spec file (relative to repo root). **Default: `specs/v1.md`** — omit this arg when working in a repo that follows the standard spec layout. |
| `<phase-name-or-id>` | yes | A phase heading, short alias (`P1`–`P7`), or any fuzzy match. Ambiguous → stop and ask via `AskUserQuestion`. |
| `--output <path>` | no | Override the default output path. Default: `plans/<PHASE_ID>.md`. |
| `--consensus` | no | Enable multi-agent architectural consensus (2–3 Plan teammates with different framings). |

### Phase short aliases (consiliency-portal `specs/v1.md`)

| Alias | Resolves to |
|---|---|
| `P1` | `Phase 1 — Shared semantics, schema hardening, and signal contract` |
| `P2` | `Phase 2 — Home, Inbox, Guide, and role-based entry` |
| `P3` | `Phase 3 — Operations, Execution, Development, and Maintenance refinement` |
| `P4` | `Phase 4 — Projects, Executive, Knowledge, and Decisions` |
| `P5` | `Phase 5 — Platform governance and admin hardening` |
| `P6` | `Phase 6 — Prompt lifecycle and AI governance` |
| `P7` | `Phase 7 — Finance, prototype support, and assistant workflows` |

These are built-in defaults. For any other repo, derive aliases from the spec's own phase headings at runtime (Step 1) and present them to the user if the short form is ambiguous.

Examples:

```
/plan-phase P1
/plan-phase P3 --consensus
/plan-phase specs/roadmap.md "Phase 3: Billing" --consensus
```

## Workflow (delegation-first)

The main thread is an **orchestrator only**. It briefs specialists, synthesizes their output, enforces consensus, writes the final doc, and emits tasks. It does not `Grep`/`Read` the codebase directly — that is the Explore teammates' job. If the main thread is reaching for `Grep` or `Read` on anything other than the spec file and the plan file, that's a signal it should have delegated.

### Step 1 — Resolve spec path, phase, and PHASE_ID

**Spec path resolution (in order):**
1. If `<spec-path>` was explicitly passed → use it.
2. Else look for `specs/v1.md` in the current working directory → use it.
3. Else look for any `specs/*.md` file → if exactly one found, use it and note the assumption.
4. Else **stop** and ask via `AskUserQuestion` which spec file to use.

**Phase resolution (in order):**
1. If `<phase-name-or-id>` is a short alias (`P1`–`P7`) → expand via the alias table above.
2. Else fuzzy-match against headings in the spec.
3. If zero matches → **stop** and use `AskUserQuestion` to show the actual headings.
4. If multiple matches → **stop** and use `AskUserQuestion` to disambiguate.

**PHASE_ID:**
- Prefer the spec's own numeric identifier (`P1`, `PHASE-1`, …).
- Else derive from the phase name: `PHASE-<N>-<kebab-of-first-4-words>`.

### Step 2 — Parallel reconnaissance via Explore teammates

Launch up to **3** `Agent(subagent_type: "Explore")` calls **in a single message** (parallel tool calls). One per major area the phase touches. Each Agent call MUST set `name:` so it can be re-addressed later via `SendMessage`.

Teammate-naming template:

- `explore-<area>` (e.g., `explore-schema`, `explore-workers`, `explore-portal`, `explore-infra`).

Each brief must include:

- The phase's **Objective** + **Exit criteria** copied verbatim from the spec.
- A scoped question: "Map existing code in `<paths>` relevant to this phase. Surface: (a) existing utilities/patterns to reuse, (b) current type/schema/interface shapes that constrain the design, (c) places that will need to change, (d) hidden coupling that would break worktree isolation."
- A length cap: "Report in under 400 words."

Block until all return. Their findings populate the `## Context` section of the plan doc.

### Step 3 — Architectural decisions

**Step 3a — With `--consensus`**: Launch 2–3 `Agent(subagent_type: "Plan")` calls **in a single message**, each with a distinct framing:

| Name | Framing |
|---|---|
| `arch-minimal` | Minimal change. Preserve current module boundaries. Add, don't refactor. |
| `arch-clean` | Clean architecture. Willing to refactor to make the design right. |
| `arch-parallel` | Maximize parallelism. Prefer more, smaller lanes over fewer, fatter lanes, even if it adds interface surface. |

Each teammate's brief includes: the spec phase section, all Explore teammate findings, and its framing. Each must return: (1) proposed interface freezes, (2) proposed lane decomposition with file ownership, (3) rationale, (4) known risks.

Synthesize per the **Consensus mechanism** below. If round 1 doesn't converge, re-address the same named teammates via `SendMessage` (not new `Agent` calls) with the specific disagreement surfaced. **Max 2 rounds.**

**Step 3b — Without `--consensus`**: Launch 1 `Agent(subagent_type: "Plan", name: "arch-baseline")` for baseline architecture decisions.

### Step 4 — Lane decomposition (main thread)

Synthesize Explore + Plan output into swim lanes. For each lane, determine:

- **Scope** — one sentence.
- **Owned files** — glob list. MUST be disjoint from every other lane's globs.
- **Interfaces provided** — symbols, types, endpoints, migrations this lane publishes.
- **Interfaces consumed** — symbols this lane depends on from other lanes.
- **Parallel-safe** — `yes` / `no` / `mixed` (with explanation if not `yes`).

Run the **Lane validation checklist** (below) before proceeding. If it fails, return to Step 3 with the failure noted.

### Step 5 — Task authoring (main thread)

For each lane, author an ordered task list:

- One **test** task (write failing tests for the lane's contracts).
- One or more **impl** tasks (each depends on the preceding test task).
- One **verify** task (runs the full test suite for the lane, plus any integration checks).

Tasks are identified `<SL-ID>.<N>` where `<SL-ID>` is the lane's ID.

### Step 6 — Emit per-lane tasks via TaskCreate

For each lane, emit **one `TaskCreate`** whose:

- **Title**: `<SL-ID> — <lane name>`
- **Body**: `Depends on: <upstream SL-IDs>`, `Blocks: <downstream SL-IDs>`, `Parallel-safe: <flag>`, and the ordered child task list (`test / impl / verify`).

This makes the lane DAG visible in the user's task pane and becomes the hand-off surface for the future `execute-phase` skill.

### Step 7 — Write plan doc

Write the plan doc to **both**:

1. `plans/<PHASE_ID>.md` in the current project.
2. The plan-mode scratch file path (found in the plan-mode system reminder — do **not** guess the path).

### Step 8 — ExitPlanMode

Call `ExitPlanMode`. The plan doc is the approval surface.

## Plan document template

Use these headings verbatim (stable IDs matter — `execute-phase` parses them):

```markdown
# <PHASE_ID>: <Phase Name>

## Context
<Synthesized from Explore teammates. What exists, what constrains the design, what will change.>

## Interface Freeze Gates
- [ ] IF-0-<PHASE>-<N> — <one-line description of the frozen interface>
- [ ] IF-0-<PHASE>-<N+1> — …

## Cross-Repo Gates
<Omit this section entirely if the phase only touches this repo.>
- [ ] IF-XR-<N> — <interface that must be frozen across repo boundaries>

## Lane Index & Dependencies
<Machine-parseable block. One stanza per lane.>

SL-1 — <lane name>
  Depends on: (none)
  Blocks: SL-3, SL-4
  Parallel-safe: yes

SL-2 — <lane name>
  Depends on: (none)
  Blocks: SL-4
  Parallel-safe: yes

## Lanes

### SL-1 — <lane name>
- **Scope**: <one sentence>
- **Owned files**: `path/one/**`, `path/two/*.ts`
- **Interfaces provided**: `FooContract`, `POST /api/bar`
- **Interfaces consumed**: (none)
- **Tasks**:

| Task ID | Type | Depends on | Files in scope | Tests owned | Test command |
|---|---|---|---|---|---|
| SL-1.1 | test | — | `path/one/__tests__/foo.test.ts` | `FooContract` shape | `pnpm test path/one/__tests__/foo.test.ts` |
| SL-1.2 | impl | SL-1.1 | `path/one/foo.ts` | — | — |
| SL-1.3 | verify | SL-1.2 | `path/one/**` | all SL-1 tests | `pnpm test path/one` |

### SL-2 — <lane name>
…

## Execution Notes
- <Parallelism caveats, sequencing gotchas, lanes that can't be worktree-isolated (shared migrations, shared generated files), etc.>
- (If `--consensus` was used) **Architectural choices**: <consensus summary, or unresolved disagreement with dissent recorded>

## Acceptance Criteria
- [ ] <Testable assertion 1 drawn from the spec phase's Exit criteria>
- [ ] <Testable assertion 2>

## Verification
<Concrete end-to-end commands to run after all lanes merge. pnpm, supabase, curl, playwright, etc.>
```

## ID conventions

| ID | Format | Example |
|---|---|---|
| `PHASE_ID` | Spec identifier, else `PHASE-<kebab>` | `PHASE-1-shared-semantics` |
| Lane ID | `SL-<N>` | `SL-3` |
| Task ID | `<LANE_ID>.<N>` | `SL-3.2` |
| Interface freeze | `IF-0-<PHASE>-<N>` | `IF-0-P1-1` |
| Cross-repo freeze | `IF-XR-<N>` | `IF-XR-2` |

Defaults only — if the spec already uses its own identifiers (e.g., `P1-SL-AUTH-01`), adopt those verbatim.

## Task types & dependency rules

| Type | Purpose | Rules |
|---|---|---|
| `test` | Write failing tests that pin down the lane's contracts. | Must precede any `impl` task in the same lane. |
| `impl` | Write the code that makes the preceding tests pass. | Must depend on exactly one `test` task in the same lane. |
| `verify` | Run the full lane test suite + any integration checks. | Last task in the lane. Depends on the last `impl` task. |

## Consensus mechanism (synthesis rule)

Applied by the main thread after `--consensus` Step 3a:

1. **Unanimous** across all teammates → accept directly.
2. **Majority (2 of 3)** → accept the majority view; record the dissenting view under `## Execution Notes > Architectural choices > Dissent`.
3. **No majority** → re-address the same named teammates via `SendMessage` with the specific conflict surfaced ("arch-minimal and arch-clean disagree on whether X should live in package Y or Z — reconsider with <argument>"). Max 1 additional round.
4. **Still no convergence** → main thread picks (biased toward `arch-parallel` for this skill's purpose) and records the full disagreement under `## Execution Notes > Unresolved architectural disagreements`.

## Lane validation checklist

Before writing the plan doc, verify:

- [ ] **Disjoint file ownership** — no two lanes' `Owned files` globs intersect. (If uncertain, expand globs mentally and check; for generated files, call out shared-generated status in Execution Notes.)
- [ ] **DAG has no cycles** — a topological sort of `Depends on:` succeeds.
- [ ] **Every `impl` task has a preceding `test` task** in the same lane.
- [ ] **Every acceptance criterion is a testable assertion**, not prose. "Users can log in" is not testable; "`POST /api/auth` returns 200 with a valid session cookie for a registered user" is.
- [ ] **Interface freeze gates are concrete** — name the symbol/endpoint/migration, not a vibe.

## Teamwork & delegation posture

This skill is an exercise in delegation. The rules:

- **Main thread = orchestrator only.** Brief, synthesize, write, emit. Do not `Grep`/`Read` the codebase directly during Steps 2–5. If you find yourself doing so, stop — the teammate's brief was incomplete. Re-brief via `SendMessage`.
- **Parallel-by-default.** Step 2 (Explore) and Step 3a (consensus Plan) MUST be issued as a single message with multiple `Agent` tool calls. Sequential spawning is a bug.
- **Name every teammate.** Set `name:` on every `Agent` call so you can re-address via `SendMessage` without losing the teammate's context or paying to restart.
- **Task list as source of truth for the lane DAG.** Step 6's per-lane `TaskCreate` is how the plan becomes actionable. Each lane task is addressable by ID for the future `execute-phase` skill.
- **Hand-off to `execute-phase` (deferred skill).** That skill is expected to read the plan doc + task list, then use `TeamCreate` (experimental `AGENT_TEAMS` teammates) to spawn one named teammate per lane, each running inside its own `Agent(isolation: "worktree")`. Lanes merge to main only after their lane-local verify task passes and the interface freeze gates for that lane's consumers are green.
- **Manual hand-off until then.** Execute a lane by spawning `Agent(isolation: "worktree", name: "<SL-ID>", subagent_type: "general-purpose")` and pasting that lane's section of the plan doc as the brief.

## Output contract

After `ExitPlanMode` approval, the following artifacts exist:

1. `plans/<PHASE_ID>.md` — committable, valid markdown, all headings present.
2. The plan-mode scratch file — identical contents.
3. One `TaskCreate`'d top-level task per lane, each with `test / impl / verify` children, containing `Depends on:` / `Blocks:` / `Parallel-safe:` metadata in the body.

Those three artifacts are the full hand-off surface. Everything downstream (manual lane execution, or the future `execute-phase` skill) reads from them.
