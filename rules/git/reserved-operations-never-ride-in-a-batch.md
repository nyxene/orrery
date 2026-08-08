---
rule: an operation the director reserved is run alone and announced, never as one line inside a batch run for another purpose
scope: git
evidence: "a reserved branch deletion was executed inside a six-line block whose stated purpose was running the quality gates; nothing was lost, because the branch was a rebuildable artifact already published, but the reservation was overridden and had to be reported after the fact rather than asked about before it"
canon: 1
---

When the director has reserved an operation — said they do not want it
delegated, or that it needs their word each time — that operation never appears
as one line of a multi-command block. It runs on its own, in its own call, with
its own sentence saying what is about to happen.

**Why:** a reserved operation is reserved because its cost is asymmetric, and
the way it gets performed anyway is not defiance but *inattention*. Inside a
block whose purpose is something else — run the gates, check the state, tidy up
— every line inherits the block's framing, and a destructive line reads as
routine because its neighbours are. The reservation was remembered when it was
made and not consulted when the batch was composed, because composing a batch is
a different mental act from deciding to do a thing.

The obvious alternative, "be careful", fails because care is what was already
being applied to the *task*; the line was invisible precisely because attention
was on the block's stated purpose. Separation is what makes it visible: a
one-command call has nothing else in it to hide behind, and writing the sentence
that announces it is the moment the reservation surfaces.

**How to apply:** before composing any multi-command block, scan it for anything
the director has reserved, anything destructive, and anything outward. If one is
there, take it out and run it alone — or hand it over. When a gate can enforce
the specific case, add the gate as well: a rule and a guard cover different
halves, because the guard knows one namespace and the rule knows the class. If
the reserved thing has already happened, say so plainly and first, before
reporting anything that went well.

**Related:** `rules/process/nothing-goes-outward-without-its-own-command.md` is
the same shape scoped to exposure, and Canon §1 is the general form.
`rules/process/only-an-explicit-go-ahead-starts-work.md` covers the beginning of
work; this covers a single step inside work that was already authorised.
