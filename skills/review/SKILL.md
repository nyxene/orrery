---
name: review
description: Review a diff you did not write — a PR, a branch, a commit range, or working changes — through the same gate that reviews plans. Use when asked to review, when inheriting someone else's change, or before approving anything. Not for reviewing your own work in flight (that is `build`'s audit gate) and not for planning (use `plan`).
argument-hint: "[--deep] [PR number | branch | commit range | paths]"
---

# Review — A Gate for Code Somebody Else Wrote

`critic` has always described itself as "the quality gate for plans **and
code**". Only `plan` ever spawned it, and only ever with plans, so half of the
agent was unreachable and there was no door into the library for the most
ordinary review task there is. This skill is that door. It adds no reviewing
logic of its own — everything about *how* to review lives in `agents/critic.md`,
and a second copy here would be the two-sources-one-contract failure this
library exists to prevent.

## Get the diff before deciding anything

The argument names the work. Resolve it to an actual diff first, because the
route depends on what is in it and impressions of a change are wrong about its
size roughly as often as they are right.

| Argument | What to run |
|---|---|
| A PR number | `gh pr diff <n>`, and `gh pr view <n>` for the description and linked issue |
| A branch | `git diff $(git merge-base HEAD <branch>)..<branch>` |
| A commit range | `git diff <range>` |
| Paths, or nothing | `git diff HEAD` and `git status` — the uncommitted working tree |

Read the diff yourself before spawning anything. A reviewer who has not read the
change cannot tell whether the verdict it gets back is about the change.

## Route — how many agents this diff earns

Same shape as `plan`, and the disqualifier is evaluated the same way: **first,
and size does not answer it.**

**Disqualifier.** A diff touching data, money, security or auth, a migration, a
production incident, a public API, or anything hard to reverse takes `audited`,
however few lines it is. A one-line change to a permission check is the case this
exists for.

| Route | When | Who runs |
|---|---|---|
| `read` | Generated, mechanical, or fully covered by a gate that already ran — a lockfile bump, a formatter pass, a rename your tooling performed | Nobody. You read it and say so |
| `gate` | The ordinary case | `critic` alone |
| `audited` | The disqualifier fires, or the diff makes a factual claim you cannot check by reading — a formula, a licence, a performance number | `critic` and `auditor` in the same parallel batch |

`--deep` forces `audited`. Nothing forces `read`; if you are unsure between
`read` and `gate`, it is `gate`, because the cost of the wrong guess is one agent
against a defect that reached the branch.

**Spawning two is a parallel fan-out**, which
`rules/agents/confirm-scope-before-parallel-agents.md` gates: name the agents,
their tier and the scope, then wait for the go-ahead. One agent does not need it.

## The pass

1. **Brief `critic` for code, not for a plan.** The brief must say so, because
   the agent's output format branches on it: there is a plan gate row it fills
   only for plans, and ambiguity risks it reports only for plans. Give it the
   diff or the exact command that reproduces it, the base it is against, and
   what the change is *supposed* to do. Evidence for code is `file:line`, and a
   finding without one is an opinion.

   **Name the route in `critic`'s vocabulary, not this skill's.** The agent
   knows `pair` and `consensus`, sets its own effort from them, and assumes
   `consensus` when the route it is handed means nothing to it — so a brief
   saying `gate` silently buys maximum effort on every ordinary review. The
   two vocabularies line up exactly, because they measure the same thing:

   | This skill's route | Tell `critic` | Why it matches |
   |---|---|---|
   | `gate` | `pair` | One checker at an ordinary stake, so high effort rather than maximum |
   | `audited` | `consensus` | A second checker runs in parallel, and the stake earns maximum effort |

   Whatever the route, say so explicitly when data, money, security or
   irreversibility is in scope — that takes maximum effort on its own, and the
   agent is told to apply it regardless of route.
2. **On `audited`, brief `auditor` in the same batch** for what `critic` does not
   own: claims against primary sources, and licensing or IP exposure of anything
   third-party the diff introduces. Two independent checks — an agent that has
   read the other's verdict is less independent, not more.
3. **Do not fix anything.** This skill produces a ruling. Acting on it is a
   separate decision and often the author's, not yours.

## Report the verdict, do not restate it

`critic` returns a structured verdict. Pass it through — the severities, the
evidence, the ranking. Then add the one thing the agent could not know: whether
its findings are already tracked. A CRITICAL that duplicates an open issue is a
different fact than a new one.

Anything real that is **not** being fixed here goes to the debt register through
`debt` before this skill reports done. A review whose findings evaporate
when the conversation ends has reviewed nothing — and a review is the second
richest source of debt a project has, after an audit.

## What this is not

- **Not `build`'s audit gate.** That gate runs inside the pipeline that wrote
  the code, against the plan the code was built from. This runs against a diff
  with no plan and, usually, no author present.
- **Not `verify`.** `verify` proves behaviour by running things. This reads.
  Where a claim needs settling by execution, `critic` has Bash and is told to
  use the project's own commands — but a green suite is `verify`'s answer, not
  this skill's.
- **Not a style pass.** Style is MINOR or it is nothing. A review that leads
  with naming has buried whatever it found underneath.
