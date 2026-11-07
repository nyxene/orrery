# Reading the call log

Part of `sharpen`: how to read `.orrery/local/calls.tsv` once *What this looks
at* has opened it. It lives beside the skill rather than in it, so the skill
fits what Claude Code keeps of it after compaction.

**Read the pair, not the row.** `ran` is written only when a tool succeeds, so
a `call` with no `ran` under the same id did not run — refused by a guard, by
the permission classifier or by the person, or errored, or interrupted, and
the log cannot tell those apart. Count rows and every number doubles. Lines
written before the event field arrived have five fields and no event; read an
empty sixth field as `call`.

It answers what a transcript answers badly and what a skill cannot answer
about itself. Group by the session fingerprint and read the shape:

- **Commands ran against a plan and no checker was ever spawned.** The case
  this log exists for. `plan` requires a spike where an answer cannot be read,
  and says in prose that a spike does not replace the review — prose that
  nothing enforces. Each such session is one time it did not hold.
- **How often a checker runs at all**, as a fraction of the sessions that
  produced a plan. A ratio, not a count: the denominator is what makes it
  mean anything.

  **The denominator is the hard half, and it is not in this log.** Drafting
  is not an agent — `plan` writes in the session that invoked it — so no
  spawn marks a session as having planned, and the log records no content
  that could. Until something does, count the items carrying a Ruling written in the
  window and say that is what you counted. A ratio whose denominator came
  from a different source than its numerator is worth stating as two numbers
  rather than one fraction.
- **How many agents a piece of work cost**, which is the number the route
  table is spending and has never been able to see.

A skill cannot record the run in which it ignored its own instructions — the
same omission removes the behaviour and the evidence of it. That is why this
is read here rather than reported by the skill it is about.

On a handful of sessions this is noise with a shape, not statistics. Say "in
this project, after that change, the ratio moved" and never "the change
works".

**And the waiver log** — `.orrery/local/waivers.tsv`, beside it — where every deliberate skip of a gate is a row with its
reason. Read the reasons, not only the count: a waiver whose reason is an
agent's own judgement rather than the owner's words is the skip the gate
exists to stop.
