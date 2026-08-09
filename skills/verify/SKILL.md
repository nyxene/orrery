---
name: verify
description: Prove a completion claim before making it. Invoke before saying anything passes, is fixed, is done, or is ready — and before committing, pushing, or opening a PR. Turns "should work" into a command that was actually run, with its output read.
argument-hint: "[the claim you are about to make]"
---

# Verify — Evidence Before Claims

Expands Canon §3.

## The gate

Before any statement about the state of the work:

1. **Name the command that would prove it wrong.** If you cannot name one, you
   do not have a claim — you have an impression, and it should be worded as one.
2. **Run it now, in this message.** Not an earlier turn, not a subset, not the
   fast variant.
3. **Read the whole output.** Exit code included. Count the failures rather
   than scanning for the word "pass".
4. **Then speak, carrying the evidence.** If the output contradicts the claim,
   report what is actually true.

Skipping a step does not make the claim faster. It makes it unverified, and an
unverified claim asserted as fact is the failure this skill exists to stop.

## A command that cannot fail proves nothing

Step 1 is satisfied by naming any command. A command that exits 0 whatever the
state of the code satisfies its letter and proves nothing at all.

Four conditions, all of them required:

- **Red-capable** — it goes red if the claim is false, and you can say what its
  failing output looks like. "Runs without erroring" is not this.
- **Deterministic** — the same verdict every run.
- **Fast** — seconds. A check slow enough to avoid is a check you do not have.
- **Runnable unattended** — no human clicking through it.

For a check you wrote yourself, red-capability is established the same way it is
for a regression test: break what it guards, watch it deny, put it back.

## What proves what

| Claim | Proven by | Not proven by |
|---|---|---|
| Tests pass | The suite run now, 0 failures | A run from before your last edit |
| Types are clean | Type-checker output, exit 0 | The tests passing |
| Lint is clean | Linter output, 0 errors | Having checked the file you edited |
| Build succeeds | Build command, exit 0 | Types and lint being clean |
| The bug is fixed | The original symptom retested | The code having changed |
| The regression test works | Seen failing, then passing | Seen passing once |
| A new gate or guard works | What it guards broken on purpose, seen denying, then reverted | It being installed and the suite still green |
| The tests pin this behaviour | A mutation run leaving no survivors in the touched code | A green suite and high coverage |
| An agent did the work | The diff | The agent's own report |
| Requirements met | Each one walked, one at a time | The suite being green |

The right column is not a list of careless mistakes. Every entry is a real
signal — just not a signal about *this* claim.

## Celebrating before the output arrives

"Perfect!", "Done!", "All set!", "That fixed it!" — written in the same message
as the command, before its result exists.

This is the opposite failure to hedging and it is more common. A hedge at least
signals doubt; this asserts a result that has not been observed, in the tone of
someone who watched it happen. The tool call is on screen directly above, which
makes the claim read as evidenced when nothing has come back yet.

The output arrives in the *next* message. Everything said about it before then
is a prediction, and it belongs in the future tense or nowhere.

## The words that mean the command was not run

Canon §3 names three: "should", "probably", "seems to". Four more mean the same
thing — "appears to", "it passed earlier", "the agent reported success", and
"just this once".

Each is a report about your confidence rather than about the output. When one
turns up, run the command. Rewording the sentence changes nothing about whether
the claim is true.

## Reporting

State what the output said, not what you hoped it would say.

- Failures get reported **with their output**, not summarized as "a few
  unrelated failures".
- A skipped step gets reported as skipped. Silence reads as "done".
- A verified claim is stated plainly, with the evidence, and without hedging.
  Hedging a *verified* claim is its own error — it wastes the verification.

## Closing something larger than a change

Before recommending that an epic, an issue or a milestone be closed, two extra
reads — both of things that already track doneness and are easy to walk past.

**The design document's resolved decisions, not just its phase list.** A
phase-by-phase read only proves that each named phase shipped something. A
decision settled on paper in an Open Questions section and never implemented
belongs to no phase, so no phase's absence reveals it. Each resolved decision
needs its own check against shipped code.

**Any artefact that already says the thing is incomplete** — a dashboard, a
handoff note, a comment on the issue. Treat it as a lead to chase with fresh
evidence, never as something to quietly overrule because your own read
disagrees. When your read and the artefact conflict, resolve it with a targeted
search of the code before acting, and say in the report that they disagreed.

This nearly cost a wrongly-closed epic: a published feature map was flagging it
incomplete while a checklist read said done, and the real gap — a decision
resolved on paper and never built — surfaced only because the discrepancy was
chased instead of dismissed.

## When there is nothing to run

Some claims have no command: a design reads well, a name is clearer, a
document is accurate. Say so explicitly — "no automated check covers this; I
read it and it looks right" — rather than borrowing the authority of a test
run that never happened.
