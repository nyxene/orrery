---
rule: only an explicit go-ahead starts work — an answer, a direction, or a finished plan is none of them
scope: process
canon: 1
evidence: "two in-flight tool calls were interrupted in one session, both after an answer to the assistant's own question was read as a start signal"
---

**Canon §1 owns this rule.** It loads every session and states it whole: no
development without an explicit go-ahead, an answer or a priority is direction
rather than authorisation, a scope change needs its own sign-off, and a grant to
start does not survive a detour into process or roadmap work.

What this file holds is what §1 has no room for — the shapes it has actually been
broken in, and how to tell them apart in the moment.

**Three things arrive looking alike, and only one starts work:**

1. **An answer** to a question you asked. It settles *what*, never *whether now*.
   Recorded failures of this rule have taken exactly this shape, which is not a
   coincidence: the assistant asks, gets a reply, and reads the reply as
   release. The reply is about the question.
2. **A direction** — "focus on X", "that comes later". It orders the work; it
   does not release it.
3. **An instruction to act.** This one, and nothing else.

**A finished plan is not consent either.** The moment before code exists is the
last cheap moment to correct a misread plan, and treating the plan's completion
as permission removes exactly that checkpoint.

**How to apply.** Stop and ask before: creating an implementation branch or a PR
with code in it, launching coding agents, or amending the scope of a plan already
approved. Recording decisions already made is not new scope; introducing scope
is. State what you would do next, then wait. When genuinely unsure whether a
message was a go-ahead, ask — one short question costs less than one interrupted
tool call.

## The exception, and how far it reaches

**An explicit auto-continue instruction is itself the go-ahead**, given up front,
for every task picked up under it. No per-task grant is needed inside that run.

And it is wider than it looks. It authorises deciding **every** choice point
autonomously — not only the domain and convention questions that are yours
anyway, but the product and commercial forks that would otherwise stop the run.
Applying only the narrower rule still pauses at those, which defeats the point of
an unattended chain: what was asked for is one consolidated decision log at the
end, not a gate at every branch.

**Its bound is the run it was given for.** Not a standing policy, not carried
into a later session, not covering a task outside the chain. Inside it: take the
best option at each fork with the same judgement you would have brought to the
question, write the choice and its reasoning into the final report so it can be
reviewed or vetoed after the fact, and keep applying the safety and quality gates
unconditionally. Those are invariants, not choice points.

**Related:** Canon §6 is what the exception widens, for the duration of the chain
and no longer. `rules/process/nothing-goes-outward-without-its-own-command.md`
extends this along the outward axis, and
`rules/git/arm-auto-merge-only-when-told.md` is the same law scoped to merges.
