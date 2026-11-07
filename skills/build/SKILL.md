---
name: build
description: Execute an already-approved plan across parallel agents tiered by what each task needs, with an independent audit before commit and a decision log for every question resolved along the way. Use once a plan already exists and it's time to build it. Not for planning itself (use `plan` for that) and not for `plan`'s `inline` route.
argument-hint: "[--interactive] [plan already in context — otherwise the work's item]"
---

# Build — Tiered Plan Execution

Executes an **already-approved** plan — the work's item,
`.orrery/work/<work>/item.md`, that `plan` ruled, or one pasted into the conversation — with a
fixed model-tier split, mandatory autonomous decision logging, an independent
pre-commit audit, and a final report. If no plan exists yet,
run `/plan` first — this skill does not draft plans, only builds them.

Fan-out runs through the harness's `Workflow` tool where it exists — a
deterministic script that spawns agents in parallel or in a pipeline, and whose
opt-in this skill's invocation supplies. **Where it does not exist, the fallback
is plain parallel `Agent` calls in one message**, which costs the pipelining and
nothing else; say which you used. Either way, pin `model` per the table below —
a spawned agent that silently inherits the session default has left its tier.
Every agent in the fan-out serves the one plan this build is for — parts of one
result, never several tasks in flight at once. An agent that "went silent" has
likely lost its report; recovering it is in `<that directory>/reference.md`,
where `<that directory>` is the base directory this skill was loaded from.

## Flags

- `--interactive`: pause via `AskUserQuestion` after the architecture and
  task-breakdown step, or after intake, where step 2 was skipped (proceed /
  adjust). Without it, the whole pipeline runs unattended through to the final
  report. It never changes what may be decided without asking.
- Default (no flag): fully autonomous end to end. This skill's entire point is
  that decisions get made and logged, not deferred — don't stop to ask
  domain/convention/technical questions, per Canon §6.

## Model tiers (fixed — do not improvise a different split)

| Tier | Needs | Work |
|---|---|---|
| Architecture | The strongest available | Turns the plan into a concrete task breakdown: module boundaries, interfaces, data flow, and which tier below owns each unit of work. It builds its own architecture, not a sketch for someone else. |
| Critical | The strongest available | Code where a subtle error is expensive: formulas and precision-sensitive calculation in whatever the project's subject is, security and auth paths, anything touching third-party data provenance. |
| Core | The strongest available | The bulk of substantive logic once architecture is set — scoped work that is not in the critical tier. |
| Routine | The cheap tier | Wiring, glue code, mechanical repetition, tests over already-understood shapes, boilerplate. |
| Data collection | The cheap tier | Gathering reference values, transcribing source material, building fixtures and goldens — collecting facts, not deciding how to compute something. |
| Audit | **Its own session**; a different model family where the stake earns it | Independent, read-only, adversarial — spawned via the `auditor` agent type, whose frontmatter pins its own model. Always after implementation, before the pull request (with no tracker, before the branch's first push) — on every change, this skill or not. |

The host project declares which model serves each tier (see the declarations in
install/into-project.md); when nothing is declared, use the session's default
model throughout.

A host may declare a budget regime that reassigns tiers; follow the declaration.

The audit tier is a fresh session first and a different model family second;
why, in `<that directory>/reference.md` — the base directory this skill was
loaded from.

## Procedure

1. **Intake.** Read the work's item (or the plan in context). Extract
   scope, files touched, acceptance criteria, and any open questions the plan
   already flagged.

   **Hand each agent its task's text from the item in its brief, and commit the
   item to the task's own branch before any worktree agent launches** where
   `.orrery/work/` is tracked. A worktree is created from a commit, so an item
   only in the working tree is not in it; and where the project ignores
   `.orrery/work/` it is in no commit at all — the brief is the one channel that
   reaches an agent either way. Never the default branch: where it is protected the
   commit is refused, and where it is not, the plan reaches it unreviewed.

   **In a chained run, wait for the previous task to reach the default branch**
   before intake on the next one. Not "the workflow reported success" — the
   merge. An agent's own completion signal is not evidence about the repository,
   and a chain that starts on an unmerged base builds on a tree nobody has.

2. **Architecture** (the strongest tier, single agent). Produce a concrete task breakdown:
   for each work item, its target tier and a **self-contained** brief (no
   "see step 2 above" back-references — implementation agents run
   independently and don't share context with each other or with this step).

   **The direct path skips this step** when every task in the item names
   nothing outside the item. Each brief is then its task's text plus every
   *Decided* row and Assumption that task names — the whole item where it is
   small — and each task runs at the tier the table above gives its work.

3. **Fan-out implementation.** Run the task list through `Workflow`
   (`pipeline`/`parallel` — independent items in parallel, not serialized),
   one agent per item, `model` pinned to its assigned tier. Each agent:
   - Implements only its own slice (own files, own scope — no drive-by
     refactors elsewhere).
   - Leaves a runnable check behind for non-trivial logic, per this repo's
     normal testing conventions.
   - Leaves nothing running: stops every process it started, children
     included, before it reports, and its output names anything it could not
     stop. Check the process table after it returns rather than its word for it.
   - Returns structured output: files touched, a summary, and `decisions[]`
     — any genuinely open/disputed question it resolved itself, each with a
     unique id, the question, the decision made, the options considered, and
     the rationale. An agent that hits no open question returns an empty list
     — don't manufacture entries.
   - **Licensing/legal questions get escalated scrutiny, never a silent
     default**: the defensible option is autonomous, a ruling on a licence is
     the owner's. Read *Licensing and provenance* in
     `<that directory>/reference.md` the moment one comes up.

4. **Aggregate.** Collect every agent's diff and `decisions[]` into one
   running list, assigning each entry a stable id in the order it was made
   (`D1`, `D2`, ...).

5. **Audit** (one independent read-only agent via the `auditor` agent
   type). Hand it the plan, the full diff, and the aggregated decision log —
   nothing else; it should have zero prior context bias. It must, per its own
   definition:
   - Check the implementation against the plan's actual acceptance criteria.
   - Independently verify math/science/calculation claims against primary
     sources (re-deriving where feasible), not just read-and-agree.
   - Screen for licensing/provenance exposure on anything third-party-derived.
   - Actually run the test suites and type-checks itself and report real
     pass/fail counts.
   - Explicitly confirm or dispute every entry in the decision log.

6. **Fix loop** (max 3 iterations). Any BLOCKING/SIGNIFICANT audit finding
   routes back to the tier that owns the affected file for a fix, then
   re-audits. If 3 iterations pass without a clean or minor-only audit, stop
   and hand the remaining findings to the user instead of looping forever.
   Landing stays refused while the latest verdict is BLOCKING: landing anyway
   is the user's ruling, given as a waiver, not the loop's way out.

7. **Debt accounting** (both directions, via the `debt` skill — do not improvise
   this bookkeeping inline). Any audit finding NOT fixed here gets filed as a
   debt item (an issue, or `.orrery/work/debt/<slug>.md` without a tracker)
   before the change lands, with its origin pointing at this task —
   the audit is the single richest source of debt a project has, and a finding
   that only lives in a chat report is lost. In the other direction, if the host
   declares a `debtPool`, this task also closes two debt items from that
   pool (see skills/debt).

8. **Write the record, then land it**, per the project's declared branch and PR
   flow — which is a required declaration precisely because it differs
   everywhere. Prove the work with `verify` before making any claim about it.
   This session edits only the landing bookkeeping a gate asks for — a count, a
   pinned hash once both copies were edited, a size ceiling with its reason;
   anything that changes behaviour goes to an agent.
   Then write the record of step 9 and **commit it with the work**, before the
   pull request, where the code host has one: the record reaches the default
   branch through the merge, and that merge is the closing act — nothing is
   written after it. `<that directory>/../../hooks/tracker.sh closer <id>`
   says what closes the originating item with it: a line for the pull request,
   or a file to delete in this change. `hooks/process-guard.sh` refuses
   `gh pr create` while the record is not in `HEAD` — or, in a project
   with no tracker, the branch's first `git push` while it is not in the branch.

9. **The record**, `record.sh`, which writes
   `.orrery/work/<work>/retrospective.md` in the work's tree: a heading naming
   the work, the one line of what happened, the machine-readable header, and
   the per-stage table — model, output, input, cache read, cache write, tool
   calls and duration per row, built by `retrospect.sh` from this
   session's transcripts. Both scripts ship in the plugin, not in the host
   repository: run them from the base directory this skill was loaded from
   (`<that directory>/record.sh`), not from the project root, where
   `skills/build/` does not exist.

   ```
   <that directory>/record.sh write --what "<one line>" [--retries <n>]
   ```

   Re-running it, `--retries`, `--final`, work that ends without merging and an
   umbrella's record are in `<that directory>/reference.md`; read it before the
   first write of a work.

10. **Final report — in chat, in the project's configured output language**
   (Canon §8; English unless the project declares otherwise). Summarize what
   was built and the audit outcome (tests run, verdict), what the run left
   running — read from `ps` and `lsof`, ideally nothing — then the mandatory
   decision-log table covering every autonomously-resolved question from
   any step that produced one (including ones the audit merely confirmed, not just ones it
   disputed — and never omitting a licensing decision, however minor it
   seemed). The columns are fixed and so are their headings: they stay in
   English whatever the output language, because a fixed identifier keeps one
   name in every language. Only the prose around the table is translated:

   | ID | Question | Decision taken | Options available | Rationale |
   |---|---|---|---|---|

## Autonomous decision policy

- Default is fully autonomous: don't surface domain/convention/technical
  questions to the user — research, decide, record. Only genuine
  product-level choices (what the user sees or pays for) or scope changes go
  to them, per Canon §6.
- Every decision gets its id and one-line rationale the moment it's made, not
  reconstructed after the fact for the report.
- Licensing and provenance are the exception, in every mode: the defensible
  default is autonomous, a ruling on a licence is the owner's (Canon §6).
- Everything else stays autonomous even in `--interactive` mode.

## When to use

- A plan already exists: every item `plan` ruled, whatever its size, or one
  the user just handed you.
- Skip for: `plan`'s `inline` route, or when no plan exists yet (run `plan`
  first). `inline` skips the agents, never the audit (`plan` §Ship).
