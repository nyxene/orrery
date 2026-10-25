---
rule: the party whose act empties an umbrella closes it, and writes the phase record in its four-part table form in the same change
scope: git
tracker: github
evidence: "a phase of sixteen merged pull requests across twelve task issues completed with no retrospective posted anywhere, found only when someone opened the umbrella looking for the spend; the umbrella then stayed open for hours after its last item was done, because the act that emptied it belonged to no step of any skill. Separately, a retrospective posted as prose without its tables had to be found by the owner and rewritten in place"
---

An umbrella issue closes when its last child leaves, performed by whoever's act
emptied it — and **the phase record is written in the change that closes it**,
not after and not somewhere else.

**Why the obligation lives here rather than in a skill.** `build` writes a task
record and lands the task. Nothing anywhere closes a *parent*. So
the phase-level act belongs to no numbered step, which is why it can happen zero
times across a phase spanning sixteen pull requests — and why an umbrella sits
open after its final item is done: the act that emptied it was not one any skill
was watching for. An obligation attached to an act always fires; an obligation
attached to a step fires only when someone invokes the skill that holds it, and
that is rarer than it looks from inside the skill.

**Why it is assembled rather than measured.** `retrospect.sh` reads the
transcripts of *the session it runs in*. The session closing an umbrella is
almost never one of the sessions that did the work, so running it there reports
the closer's own spend and nothing else. The phase record is built by reading
the children's records back out of the repository — each child's
`.orrery/work/<work>/retrospective.md`, which arrived on the default branch with
its merge — and that is what the machine-readable header block in each of them
is for, and why that block has to stay identical across them. It does, because
no one writes it by hand: `record.sh write` generates it, and the pull-request
gate refuses to open a pull request (or, without a tracker, the first push)
whose record is not committed. The phase
form is the one part nothing generates, which is why it is here.

**How to apply:**

1. Before closing, list the children's records on the default branch —
   `.orrery/work/*/retrospective.md` for the works the phase spanned — and sum
   their header blocks rather than re-reading any transcript.
2. Write the phase record in the full four-part form — the header, the summed
   spend table with each row's model, the wall-clock table across the phase's
   pull requests, and the numbered list of what actually happened — and file it
   under the phase's own name in the pull request that empties the umbrella:
   `record.sh write --body-file <path> --work <phase>`. That pull request still
   carries its own record too, under its own name — the gate asks for that one.
   The minimum form is for
   an ordinary piece of work; a phase earns all four. Never prose or bullets
   alone. Say which numbers are cumulative agent compute and which are
   wall-clock, which includes idle time; and never add a harness-reported token
   total to a transcript-summed one without saying they measure different
   things.
3. Then let that pull request close the umbrella — `Closes #N` where the project
   keeps a tracker. A child closed by a merge means the merging party; a child
   closed by hand means whoever closed it.
4. A child whose record is missing is a hole in the phase total, and the honest
   cell is `not captured`. Do not reconstruct it from memory: an invented number
   cannot be told from a real one later, which is the only reason any of this is
   written down.

**Related:** `rules/git/reopen-umbrella-issues-after-each-pr.md` is the other
half of keeping a parent's state honest — that one is about an umbrella closing
when it should not, this one about an umbrella not closing when it should.
