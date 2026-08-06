---
rule: every research or analysis document ends with a references table of sources actually used
scope: process
evidence: "a research pass reported findings in prose without capturing source URLs; a later request for the references required redoing the web search from scratch to reconstruct the citation trail"
---

Any document produced from research or analysis — design docs, plans, competitive/UX research, audits — ends with a References table listing every external source actually consulted: title and URL at minimum, ideally what it was used for.

**Why:** losing the citation trail is a real defect, not a nice-to-have. Once a research subagent's session ends, the source list only exists if it was captured in the deliverable — a later "show me the references" request can't be answered from memory and has to redo the search from scratch.

**How to apply:** when delegating research to a subagent, or doing it directly, instruct it to track every URL it actually uses, and append a References table (or equivalent) at the end of whatever document or report comes out of it — plan files, design docs, research reports, anything conclusions are built on external sources for. Do this proactively, not only when asked.

**Related:** none directly — a documentation-quality rule that applies wherever research feeds a written deliverable.
