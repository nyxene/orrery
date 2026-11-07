---
rule: lead every report with the shape that carries it — an ASCII diagram for a mechanism, a table for a comparison, a list for a sequence — and keep the prose to what the shape cannot say; a step handed to the owner names only output that was seen
scope: process
evidence: "a working practice fixed in writing after it held only while someone remembered to ask for it; the attention it protects gates every piece of work, and a report explaining in prose what a diagram would have shown spends it twice on one fact; and a step that promised output nobody had seen sent the owner searching a screen for a line that was never going to be there"
---

Open with the thing that can be *seen* rather than read, chosen by what is being
reported:

| what you are reporting | the shape that carries it |
|---|---|
| a mechanism, a flow, where something lands | an ASCII diagram |
| options against criteria, before against after | a table |
| an ordered sequence, or findings ranked | a list |
| one fact | a sentence — a diagram of one box is decoration |

Then the text beside it says **only what the shape cannot**: what was decided
and why, what is at risk, what needs them. Not a walkthrough of the diagram —
they can see the diagram.

**Hold the depth.** Everything you know and did not say is available the moment
they ask, and asking is one line. When they do ask, answer in full — this rule
sets the default, not a ceiling, and a follow-up question deserves the
exhaustive version.

**A step handed to them promises only what was seen.** When a report ends in
steps the owner runs, a step names the output to expect only if that output was
seen — run here, or read whole in the tool's own documentation. Otherwise the
step says it was not seen, and what success and what failure each look like, so
a screen that does not match is a finding they can report rather than a search
they cannot finish.

**Why ASCII rather than a rendered picture:** the report arrives in a terminal.
A diagram that needs a viewer is a diagram they open later, which is the same as
not sending it. It also has to survive being pasted into an issue, a commit
message or a plan document, all of which are plain text.

**Why the shape comes first even when the prose is good:** drawing it is what
exposes the part you had not worked out. Canon §7 makes this point about
thinking rather than presentation, and it is the reason this is not a formatting
preference — a report you could not draw is a report you do not yet understand.

**How to apply:** before writing the report, decide which of the four rows above
it is, and draw that first. Then delete every sentence that a reader could have
got from the drawing. What remains is the report. If nothing remains, the
drawing was the whole answer and that is a good outcome, not a missing section.
Before handing over a step, check whether you saw what it will print; if not,
say so in the step.
Exceptions run one way only: a question that asked for prose gets prose, and a
document whose form is fixed elsewhere — a rule file, a changelog entry, a
retrospective's mandatory tables — keeps its own form.

**Related:** the rule that an umbrella's closer posts the phase retrospective is
the same law narrowed to one document. The rule that you name the members rather
than the count is what keeps a table honest once you have drawn it.
