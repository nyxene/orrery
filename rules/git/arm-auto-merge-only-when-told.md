---
rule: arm auto-merge on a pr only on an explicit merge instruction; leave it off while review is still iterating
scope: git
evidence: "auto-merge was armed on a PR still receiving review iterations and had to be stopped twice before merge; a half-finished iteration would have landed the instant CI turned green"
---

Don't enable auto-merge while a PR's content is still being iterated on.
Open the PR, push commits as the review continues, but leave merging to an
explicit merge instruction.

**Why:** an auto-merge armed during an active feedback loop can land a
half-finished iteration the moment CI goes green, with no chance for a last
round of review. Whoever is reviewing treats the merge itself as the
finalization signal, not a formality that happens to coincide with a green
build — continued engagement with a PR is not a release of it.

**How to apply:** while a PR is under active review or iteration (design
passes, copy tweaks, code review comments), push commits but keep auto-merge
OFF until an explicit "merge it" arrives. A one-shot mechanical PR that was
explicitly requested — no further review expected — remains fine to open with
auto-merge on.

**Related:** `rules/process/only-an-explicit-go-ahead-starts-work.md` — arming
auto-merge is the same mistake in a different place, reading continued
engagement with a PR as its release.
