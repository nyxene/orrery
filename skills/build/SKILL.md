---
name: build
description: Execute an already-approved plan across parallel agents tiered by what each task needs, with an independent audit before commit and a decision log for every question resolved along the way. Use once a plan already exists and it's time to build it. Not for planning itself (use `plan` for that) and not for trivial single-file changes.
argument-hint: "[--interactive] <plan file path, or issue number, or plan already in context>"
---

# Build — Tiered Plan Execution

Executes an **already-approved** plan (a `plan` output in the project's plan directory,
a GitHub issue with a design doc, or a plan pasted into the conversation) with a
fixed model-tier split, mandatory autonomous decision logging, an independent
pre-commit audit, and a final report. If no plan exists yet,
run `/plan` first — this skill does not draft plans, only builds them.

Fan-out runs through the harness's `Workflow` tool where it exists — a
deterministic script that spawns agents in parallel or in a pipeline, and whose
opt-in this skill's invocation supplies. **Where it does not exist, the fallback
is plain parallel `Agent` calls in one message**, which costs the pipelining and
nothing else; say which you used. Either way, pin `model` per the table below —
a spawned agent that silently inherits the session default has left its tier.

`hooks/agent-guard.sh` denies a named spawn whose brief never tells the agent to
send its deliverable back, so the lost-report failure is blocked rather than
remembered. **Recovering an already-lost report** is the part no guard can do:
the payloads are in
`~/.claude/projects/<project>/<session>/subagents/agent-*.jsonl`, and an agent
that "went silent" is this failure until proven otherwise.

## Flags

- `--interactive`: pause via `AskUserQuestion` after the architecture and
  task-breakdown step (proceed / adjust). Without it, the whole pipeline runs
  unattended through to the final report. It does not change what may be
  decided without asking — a licence that needs a ruling goes to the owner in
  every mode, and a defensible default is taken autonomously in every mode.
- Default (no flag): fully autonomous end to end. This skill's entire point is
  that decisions get made and logged, not deferred — don't stop to ask
  domain/convention/technical questions, per Canon §6.

## Model tiers (fixed — do not improvise a different split)

The tiers are named by what the work needs, not by which model is current. A
model release then changes one paragraph instead of a table.

| Tier | Needs | Work |
|---|---|---|
| Architecture | The strongest available | Turns the plan into a concrete task breakdown: module boundaries, interfaces, data flow, and which tier below owns each unit of work. It builds its own architecture, not a sketch for someone else. |
| Critical | The strongest available | Code where a subtle error is expensive: formulas and precision-sensitive calculation in whatever the project's subject is, security and auth paths, anything touching third-party data provenance. |
| Core | The strongest available | The bulk of substantive logic once architecture is set — scoped work that is not in the critical tier. |
| Routine | The cheap tier | Wiring, glue code, mechanical repetition, tests over already-understood shapes, boilerplate. |
| Data collection | The cheap tier | Gathering reference values, transcribing source material, building fixtures and goldens — collecting facts, not deciding how to compute something. |
| Audit | **Its own session**; a different model family where the stake earns it | Independent, read-only, adversarial — spawned via the `auditor` agent type, whose frontmatter pins its own model. Always after implementation, before commit. |

The host project declares which model serves each tier (see the declarations in
install/into-project.md); when nothing is declared, use the session's default
model throughout.

A host may declare a budget regime that reassigns tiers; follow the declaration.

The audit tier is the one that is about context rather than capability. A judge
that ran inside the session which produced the work inherits its reasoning whole
— the same files in the same order, the same alternatives already dismissed — so
whatever was missed is missing from the judge as well. A fresh session is the
mechanism, and it is what the gate buys. Spawning the `auditor` agent type is
what supplies it.

A different model family on top of that is an amplifier rather than the
mechanism: two fresh sessions of one model already have separate contexts, and
two families additionally have separate blind spots, which is worth buying where
the stake earns it. This repository buys it — `auditor` pins Fable — but a
project with one family available conforms, and nothing in this table says
otherwise.

## Procedure

1. **Intake.** Read the plan (file path, issue, or in-context text). Extract
   scope, files touched, acceptance criteria, and any open questions the plan
   already flagged.

   **Commit the plan document to the default branch before any worktree agent
   launches.** A worktree is created from a commit; a plan that exists only in
   the working tree is not in it, so every isolated agent starts without the
   document it was told to follow. This has bitten twice in one session and was
   caught both times by something unrelated, which is the shape of a defect that
   otherwise ships.

   **In a chained run, wait for the previous task's PR to actually merge**
   before intake on the next one. Not "the workflow reported success" — the
   merge. An agent's own completion signal is not evidence about the repository,
   and a chain that starts on an unmerged base builds on a tree nobody has.

2. **Architecture** (the strongest tier, single agent). Produce a concrete task breakdown:
   for each work item, its target tier and a **self-contained** brief (no
   "see step 2 above" back-references — implementation agents run
   independently and don't share context with each other or with this step).

3. **Fan-out implementation.** Run the task list through `Workflow`
   (`pipeline`/`parallel` — independent items in parallel, not serialized),
   one agent per item, `model` pinned to its assigned tier. Each agent:
   - Implements only its own slice (own files, own scope — no drive-by
     refactors elsewhere).
   - Leaves a runnable check behind for non-trivial logic, per this repo's
     normal testing conventions.
   - Returns structured output: files touched, a summary, and `decisions[]`
     — any genuinely open/disputed question it resolved itself, each with a
     unique id, the question, the decision made, the options considered, and
     the rationale. An agent that hits no open question returns an empty list
     — don't manufacture entries.
   - **Licensing/legal questions get escalated scrutiny, never a silent
     default**: anything touching data provenance (third-party constant or
     reference tables, named-author formulas, scraped or verbatim text,
     patented algorithms) defaults to the most independently-defensible
     option — attribute to the original human or public-domain source,
     re-derive rather than copy, avoid copyleft-triggering redistribution —
     per `rules/craft/third-party-content-splits-into-idea-vs-expression.md`. The defensible
     option costs a little now; the other one carries an unbounded liability
     the moment the work reaches anyone outside the room.

     **Taking the defensible default is autonomous. Ruling on a licence is
     not.** Re-deriving instead of copying sidesteps the question and needs
     nobody's permission. Deciding that a particular third-party artifact may
     be used *as it is* is a legal judgement, and Canon §6 reserves it — an
     agent presents the risk and the mechanism, never the verdict. Where no
     defensible default exists, stop and put it to the owner, in any mode.
     Either way the decision is mandatory in the log, never omitted for being
     "obviously fine."

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

7. **Debt accounting** (both directions, via the `debt` skill — do not improvise
   this bookkeeping inline). Any audit finding NOT fixed here gets filed as a
   debt issue before the change lands, with its origin pointing at this task —
   the audit is the single richest source of debt a project has, and a finding
   that only lives in a chat report is lost. In the other direction, if the host
   declares a debt quota, this task also closes that many debt issues from the
   active pool (see skills/debt).

8. **Land it**, per the project's declared branch and PR flow — which is a
   required declaration precisely because it differs everywhere: some projects
   commit to the default branch, some require a branch and a reviewed PR. Prove
   the work with `verify` before making any claim about it, then land it the way
   that project lands things. Where the flow produces a PR, `Closes #N` on the
   originating issue is what closes it.

9. **Retrospective logging**, in the table format
   `rules/process/retrospectives-always-use-the-table-format.md` fixes: the
   machine-readable header, the tokens and tool-calls table, real `gh`-queried
   timestamps, and the numbered step list. Post it on **the issue that is
   closing** — this task's issue, never a sub-PR and never the umbrella, which
   gets its own assembled one when it closes. `skills/build/close-issue.sh <N>
   --what "<one line>"` does the minimum form and closes the issue in one act,
   which is what `hooks/process-guard.sh` refuses a bare `gh issue close` in
   favour of. Do not invent a second format — the rule exists because a second
   one was invented, and "the issue or PR" was itself two readings that between
   them produced no retrospective at all.

   Run `skills/build/retrospect.sh` for the first two: it reads this session's
   transcripts — the main session and every agent it spawned — and prints the
   header block and the per-stage table. **No step above records anything for
   it** — the transcripts already hold the usage, the tool calls and the
   timestamps, which is why this step is at the end and costs the run nothing.
   Pass `--since <iso8601>` when this session already reported on an earlier
   issue, or the earlier one's spend is counted again here. If it reports no
   transcripts, the cells are `not captured`; never fill them with an estimate.

10. **Final report — in chat, in the project's configured output language**
   (Canon §8; English unless the project declares otherwise). Summarize what
   was built and the audit outcome (tests run, verdict), then the mandatory
   decision-log table covering every autonomously-resolved question from
   any step that produced one (including ones the audit merely confirmed, not just ones it
   disputed — and never omitting a licensing decision, however minor it
   seemed). Translate the column headings into the output language; the
   columns themselves are fixed:

   | ID | Question | Decision taken | Options available | Rationale |
   |---|---|---|---|---|

## Autonomous decision policy

- Default is fully autonomous: don't surface domain/convention/technical
  questions to the user — research, decide, record. Only genuine
  product-level choices (what the user sees or pays for) or scope changes go
  to them, per Canon §6.
- Every decision gets its id and one-line rationale the moment it's made, not
  reconstructed after the fact for the report.
- Licensing and provenance are the exception, and step 3 states where the line
  falls: taking the defensible default is autonomous, ruling on a licence is
  the owner's under Canon §6. That carve-out holds in every mode, not only
  `--interactive`; the flag changes when you are interrupted, never what may
  be decided without asking.
- Everything else stays autonomous even in `--interactive` mode.

## When to use

- A plan already exists (from `plan`, a GitHub issue design doc, or one the
  user just handed you) and it's substantial enough to want independent
  parallel agents and a real audit gate — multi-file features, anything with
  a math/science core, anything touching third-party data.
- Skip for: trivial single-file changes, or when no plan exists yet (run
  `plan` first).
