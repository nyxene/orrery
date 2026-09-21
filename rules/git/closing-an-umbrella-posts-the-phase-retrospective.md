---
rule: the party whose act empties an umbrella closes it, and posts the phase retrospective before doing so
scope: git
evidence: "a phase of sixteen merged pull requests across twelve task issues completed with no retrospective posted anywhere, found only when someone opened the umbrella looking for the spend; the umbrella then stayed open for hours after its last item was done, because the act that emptied it belonged to no step of any skill"
---

An umbrella issue closes when its last child leaves, performed by whoever's act
emptied it — and **the phase retrospective is posted before it closes**, not
after and not somewhere else.

**Why the obligation lives here rather than in a skill.** `build` posts a task
retrospective and closes a task issue. Nothing anywhere closes a *parent*. So
the phase-level act belongs to no numbered step, which is why it can happen zero
times across a phase spanning sixteen pull requests — and why an umbrella sits
open after its final item is done: the act that emptied it was not one any skill
was watching for. An obligation attached to an act always fires; an obligation
attached to a step fires only when someone invokes the skill that holds it, and
that is rarer than it looks from inside the skill.

**Why it is assembled rather than measured.** `skills/build/retrospect.sh` reads
the transcripts of *the session it runs in*. The session closing an umbrella is
almost never one of the sessions that did the work, so running it there reports
the closer's own spend and nothing else. The phase retrospective is built by
reading the task retrospectives back out of the tracker — that is what the
machine-readable header block in each of them is for, and it is why
`rules/process/retrospectives-always-use-the-table-format.md` insists the format
stay identical across issues.

**How to apply:**

1. Before closing, list the children and collect their retrospective comments:
   `gh issue view <child> --json comments`. Sum the header blocks rather than
   re-reading any transcript.
2. Post the phase retrospective on the umbrella in the full four-part form —
   the header, the summed spend table, the `gh`-queried wall-clock table across
   the phase's pull requests, and the numbered list of what actually happened.
   The minimum form is for an ordinary issue; a phase earns all four.
3. Then close the umbrella, and close it yourself if your act emptied it. A
   child closed by a merge means the merging party; a child closed by hand means
   whoever closed it.
4. A child whose retrospective is missing is a hole in the phase total, and the
   honest cell is `not captured`. Do not reconstruct it from memory: an invented
   number cannot be told from a real one later, which is the only reason any of
   this is written down.

**Related:** `rules/git/reopen-umbrella-issues-after-each-pr.md` is the other
half of keeping a parent's state honest — that one is about an umbrella closing
when it should not, this one about an umbrella not closing when it should.
