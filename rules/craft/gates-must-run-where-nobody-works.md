---
rule: a gate that has only ever run where the work happens was tested against that machine's leftovers, not against the code
scope: craft
evidence: "a guard's delete check resolved its target against the filesystem. The directory it named always exists on a machine that has run the tool, so the corpus was green in every pre-commit run and red the first time it executed in a clean environment — after shipping in two releases, having been silently correct on every machine anyone checked it on"
---

Run the gates somewhere nobody works. A suite that has only ever executed on
developers' machines has been passing against whatever those machines have
accumulated — directories that exist because something created them once,
tools on `PATH`, config set months ago, caches. None of it is in the repository,
and all of it is load-bearing until proven otherwise.

**Why:** the failure is not that a case is missing. Case coverage and
environment coverage are different axes, and a complete corpus proves nothing
about the second. In the incident behind this rule the corpus contained exactly
the right case — a delete inside a scratch directory, expected to be allowed —
and it passed, because the path it named happened to exist. On a machine where
it did not, the same case failed. The code read the filesystem, so the
filesystem was an input, and it was an input nobody had written down.

The obvious alternative — "run it on a colleague's machine too" — fails because
a second working machine has the same leftovers for the same reason. What
distinguishes a clean environment is not that it is *different*, it is that it
is *empty*: nothing has happened there, so nothing ambient can be mistaken for
something the repository provides.

**How to apply:** give the suite a run in a fresh environment on every change —
CI, a container, or a scratch user account — and treat that as the authoritative
result when the two disagree. The local run stays, because it is the fast one;
it stops being the one that decides.

While writing a case, ask what has to be true of the machine for the expected
answer to hold. If the answer names anything outside the repository, either
construct it inside the case or add a sibling case that reaches the same code
path with it absent. A path that does not exist is a state, and it is usually
the untested one.

**Related:** `rules/craft/make-the-tool-say-why-before-deciding-why.md` is the
same shape one level up — an environment nobody exercises is one nobody has
measured, and a refusal nobody printed is one nobody has read.
`rules/craft/state-owned-elsewhere-is-fetched-before-it-is-read.md` covers the
version of this where the unwritten input is not the machine but a stale copy of
someone else's state.
