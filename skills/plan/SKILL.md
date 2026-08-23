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
| `pair` | The approach is known, or has precedent in this codebase | 1 — Critic |
| `consensus` | The approach is genuinely uncertain | 2 — Architect ∥ Critic |

**Uncertainty has a kind, and only one kind is settled by hiring readers.**
Before choosing between `pair` and `consensus`, ask what the uncertainty is
*about*.

- **About the present** — what the code does, what precedent exists, what the API
  returns. A reader settles it, and the table above applies as written.
- **About the future** — will this hold, what will it cost, does this edge close.
  No number of readers settles it. §Spike comes first, and the route is decided
  again afterwards — usually one step lower, because the thing that made it
  uncertain is now a fact.

A spike costs minutes. `consensus` costs two agents at maximum effort. Reaching
for the second where the first applies is the most expensive mistake available
here.

This is not licence to skip the checkers. The spike removes the uncertainty, not
the review: what remains after it — structure, order, naming, blast radius — is
exactly what a reader is good at. A plan that spiked and then went unchecked has
answered the cheap question and skipped the one the route was chosen for.

Look up what decides it: `git log` for precedent, a Grep for the call sites, the
manifest for what already exists. A route chosen from a guess is the guess that
costs the most.

**`inline` still finishes the job.** Plan it here, say you did and why the route
was inline, then build it, then prove it with `verify` before claiming anything.
Taking `inline` is a decision about how many checkers the work earns — never a
decision to skip the gate at the end.

**`consensus` reached by a risk signal is DELIBERATE.** Reaching it because the
approach is merely uncertain is not. The difference is what the plan must carry:
DELIBERATE adds a test plan spanning unit, integration, end-to-end and
observability. `--deliberate` forces it by hand, for when you know something the
signals do not.

**The pre-mortem belongs to `consensus`, both modes.** It was DELIBERATE-only,
which put the one technique we have against *unstated* assumptions behind the
narrowest gate in the file — available exactly where the most care was already
being spent, and absent everywhere else. Assuming the plan has already failed
and saying why is not a check on the entries; it is the only step that goes
looking for the ones nobody wrote. Three concrete failure scenarios, and each
names what would have had to be true.

That is the whole vocabulary: three routes, and a mode that is `standard` or
`deliberate`. No agent re-derives either; every spawn is told which it is.

## Spike what cannot be read

A reviewer reads. So a reviewer can check what the code **is** and cannot check
what it **will do** — and a plan is mostly the second kind of sentence: this
stub will serve, this edge will close, these four cases are enough. Those are
predictions, and no number of readers converts one into a fact.

That is not a hypothetical failure mode. Five plans and ten checker rounds on
one task produced no code; the same work, built, surfaced four plan defects in a
single pass, and not one of them was reachable from the existing code. The
checkers had found real errors — a sign inverted, a cost four times under, a
term misspelt — all of them statements about the present, all of them a grep
away.

**So: a question whose answer is a number or an observable behaviour is settled
by running something, before it is planned around.** Write the smallest thing
that answers it, run it, and put the result in the plan as a fact. Plan the
remainder.

Three bounds make a spike a question rather than the start of the work:

- It writes nothing outside the session scratchpad.
- It reads external services and changes none of them. A rate limit or a bill is
  a side effect the owner did not authorise by asking for a plan.
- It is thrown away. What reaches the plan is the result, never the code — a
  spike kept is a prototype promoted without review.

**What a spike catches that an assumptions list cannot** is the assumption
nobody wrote down. All four defects above were absences, not wrong entries: a
behaviour never specified, an edge that does not close, a filter that turns out
dead. A list of stated assumptions is checked against; a gap announces itself
only when something refuses to run.

No spike is needed when nothing in the plan turns on an unread number or an
unobserved behaviour. Say that, in one line, rather than leaving it unsaid —
the absence of a spike is a claim like any other.

## The pass

1. **Draft to the plan directory, here, in this session.** The drafting is not
   an agent — the checkers are. **Open the draft with the route and the mode**,
   because what it must contain depends on both:
   - Always: steps with acceptance criteria, an **Assumptions** list rated
     VERIFIED / REASONABLE / FRAGILE, and per-step dependencies. The checkers
     verify that list rather than rebuilding it, which is where the time goes —
     and an entry marked VERIFIED with no command beside it is a finding, or the
     rating is a self-assessment they are auditing instead of the work.

     **VERIFIED means a command was run, its output was read, and the command is
     written beside the assumption.** Nothing else earns the word. Without one,
     the entry is REASONABLE at best — a rating applied to a prediction after
     reading the code is Canon §3 suspended at exactly the point where it decides
     a design. FRAGILE that the design rests on is the trigger for §Spike, not a
     label to ship.
   - `consensus` only: principles (3-5), decision drivers (top 3), and options
     (2+, or what invalidated the rest). On `pair` the approach is known by
     definition — demanding alternatives there manufactures the token ones the
     critic is supposed to reject.
   - `consensus` only: a pre-mortem of three concrete failure scenarios.
   - DELIBERATE only: the expanded test plan.
   - Always, when §Spike applies: the spike's result as a fact, with the command
     that produced it. A plan that turns on an unread number and carries no
     command is redrafted rather than checked.
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

- **The draft** is revised here against the findings, and the revision states
  how each one was answered. An architect antithesis you reject is answered in
  writing, not ignored.
- **Critic** re-checks **its own prior findings** and anything the revision newly
  touched. Not a fresh full pass — the plan it already read has not changed
  underneath it.
- **Architect** re-runs **only if the approach changed** — or if the revision
  rejected its antithesis. A finding about a missing function name does not
  warrant re-arguing the direction; a rejected argument does, because nobody else
  can weigh it. The critic never saw the antithesis, by design, so a rejection
  the architect does not re-read is an argument that dies unopposed after being
  answered once by the party it was aimed at.
- A rejection the architect **accepts** ends it. It says so in one line and the
  iteration closes.

**Two iterations, then stop** — and the count belongs to the work rather than to
the document. If the critic still withholds APPROVE after two, the defect is in
the brief rather than the plan. Present the best version, name what the critic
will not pass, and hand it to the owner.

**Before drafting, look in the plan directory for a plan already covering this
work.** If one is there, this is a second attempt and the draft says so. A third
is not written: two documents for one task means planning is not what the work
is short of, and the next move is a spike or a build.

Five plans for one task, each of them inside the two-iteration cap, is how ten
checker rounds produced no code. Every round was within the limit; nothing
counted the sequence.

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
