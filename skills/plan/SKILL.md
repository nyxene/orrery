---
name: plan
description: Produce a plan someone else can execute, checked by as many independent agents as the stake earns — none, a critic, or a critic and an architect in parallel until APPROVE. Use before any change, including a one-line one: it prices the work and an obvious fix spends no agents. Not for building (use `build`).
argument-hint: "[--interactive] [--deliberate] <task description>"
---

# Plan — Priced Planning

A plan, checked by as many independent agents as the work earns. That is
sometimes three, often one, and sometimes none — the route is decided first and
most of this file describes the heaviest case, not the usual one.

Plans are written to the host project's plan directory (`docs/planning/plans/`
unless the project's own instructions say otherwise). Execution is autonomous by
default; `--interactive` adds human checkpoints.

**Spawning the checkers is a parallel fan-out**, which
`rules/agents/confirm-scope-before-parallel-agents.md` gates: name the agents,
their tier and the scope, then **wait for the go-ahead** before launching. Inside
an approved auto-continue chain the approval already covers it, so the statement
is made and the run proceeds.

## Route first — how many agents this work earns

Every agent run costs minutes of the owner's wall clock. Decide the route
**before** spawning anything, from facts you look up rather than impressions.

**The disqualifier is evaluated first, and size does not answer it.** Work that
touches data, money, security or auth, a migration, a production incident, or a
public API — or that is hard to reverse — takes `consensus`, however small the
diff. A one-file change to a token check is a one-file change to a token check.

That order is the whole point. Judged inside the table, "one file" matches first
and the risk list is never read, so the exact class of change the list exists to
catch is the one class that escapes it.

Everything else, first match wins:

| Route | When | Runs |
|---|---|---|
| `inline` | One file, or the approach is already obvious | 0 — plan here, in this session, and say you did |
| `pair` | The approach is known, or has precedent in this codebase | Planner → Critic |
| `consensus` | The approach is genuinely uncertain | Planner → (Architect ∥ Critic) |

Look up what decides it: `git log` for precedent, a Grep for the call sites, the
manifest for what already exists. A route chosen from a guess is the guess that
costs the most.

**`inline` still finishes the job.** Plan it here, say you did and why the route
was inline, then build it, then prove it with `verify` before claiming anything.
Taking `inline` is a decision about how many checkers the work earns — never a
decision to skip the gate at the end.

**`consensus` reached by a risk signal is DELIBERATE.** Reaching it because the
approach is merely uncertain is not. The difference is what the plan must carry:
DELIBERATE adds a pre-mortem of three concrete failure scenarios and a test plan
spanning unit, integration, end-to-end and observability. `--deliberate` forces
it by hand, for when you know something the signals do not.

That is the whole vocabulary: three routes, and a mode that is `standard` or
`deliberate`. No agent re-derives either; every spawn is told which it is.

## The pass

1. **Planner** drafts to the plan directory. **Its brief opens with the route and
   the mode**, because what it must produce depends on both:
   - Always: steps with acceptance criteria, an **Assumptions** list rated
     VERIFIED / REASONABLE / FRAGILE, and per-step dependencies. The checkers
     verify that list rather than rebuilding it, which is where the time goes.
   - `consensus` only: principles (3-5), decision drivers (top 3), and options
     (2+, or what invalidated the rest). On `pair` the approach is known by
     definition — demanding alternatives there manufactures the token ones the
     critic is supposed to reject.
   - DELIBERATE only: the pre-mortem and the expanded test plan.
2. *(--interactive only)* **Stop on the draft and wait.** Put it to the owner with
   `AskUserQuestion` — proceed / request changes — and do not spawn a checker
   until they answer. Displaying the draft and carrying on is not this step: the
   whole value of the checkpoint is redirecting a wrong draft *before* the agent
   runs are spent on it.
3. **Check.** On `pair`, spawn `critic` alone. On `consensus`, spawn `architect`
   and `critic` **in the same parallel batch** — they are two independent checks,
   and a checker that has read the other's verdict is less independent, not more.
   Every brief names the route and the mode, and the agent sets its own effort
   from them — maximum on `consensus`, high on `pair`, maximum regardless
   wherever data, money, security or irreversibility is in scope.
4. **On APPROVE**, go to §Ship.

## The re-review — only what moved

A non-APPROVE verdict revises the plan. It does not restart the pass.

- **Planner** revises against the findings, and states in the revision how it
  answered each one. An architect antithesis it rejects is answered in writing,
  not ignored.
- **Critic** re-checks **its own prior findings** and anything the revision newly
  touched. Not a fresh full pass — the plan it already read has not changed
  underneath it.
- **Architect** re-runs **only if the approach changed** — or if the planner
  rejected its antithesis. A finding about a missing function name does not
  warrant re-arguing the direction; a rejected argument does, because nobody else
  can weigh it. The critic never saw the antithesis, by design, so a rejection
  the architect does not re-read is an argument that dies unopposed after being
  answered once by the party it was aimed at.
- A rejection the architect **accepts** ends it. It says so in one line and the
  iteration closes.

**Two iterations, then stop.** If the critic still withholds APPROVE after two,
the defect is in the brief rather than the plan. Present the best version, name
what the critic will not pass, and hand it to the owner.

## Ship

**This section is about a plan document, so it is about `pair` and `consensus`.**
`inline` produces no document — it is decided and said in the session, per
§Route — and an ADR listing "alternatives considered" for a change whose approach
was obvious by definition is paperwork with nothing in it. What `inline` still
owes is one line naming the decision and why the route was inline, then the same
`verify` at the end as everything else. The gate is never what `inline` skips.

- The final plan carries an ADR: Decision, Drivers, Alternatives considered, Why
  chosen, Consequences, Follow-ups.
- **Open questions** — questions you can state precisely, answered or not — are
  resolved by `build` and logged, or escalated per Canon §6.
- **Not yet specified** — areas you can tell are coming but cannot yet phrase as
  a question — are not planned, not decomposed, and not argued about. The loop
  burns its iterations trying to sharpen these; keeping them in their own section
  is what stops it.
- Default: proceed to implementation immediately in this session. Quality gates
  stay script-only (pre-push + CI).
- *(--interactive only)*: ask first — approve / request changes / reject.
- An open question that materially changes scope, or is destructive or
  irreversible, goes to the owner before that part is built, in any mode.

## When to Use

- Multi-file features, cross-package changes, DB migrations, auth/security work,
  unfamiliar subsystems, genuinely uncertain approaches.
- **Never skipped.** Routine fixes and single-file changes come here too and
  take the `inline` route, which spends nothing. Skipping the skill is what
  lets a one-file auth change avoid the disqualifier, so the entry is
  unconditional and the routing does the pricing.
