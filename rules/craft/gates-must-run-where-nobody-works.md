---
rule: a suite proves only the conditions it actually had — run the gates where nobody works, and on what production actually hands them
scope: craft
evidence: "two incidents, merged. A guard's delete check resolved its target against the filesystem; the directory it named always exists on a machine that has run the tool, so the corpus was green in every pre-commit run and red the first time it executed in a clean environment — after shipping in two releases. Separately, a tool's suite ran fifteen cases against manifests of two to four entries and the same command died on the real fifty-entry one, leaving the tool's primary phase non-functional while every gate reported green. A third, later: the same suites moved onto a different Linux runner and went red twice against a tree whose local pre-commit hook and whose previous CI had both been green. The runner executed as root, so probes that prove a refusal by making a path unreadable could not fire; and a comparison consumed input pinned to byte collation while itself collating on the ambient locale. The second had been latent for months in the program that decides which files ship, invisible because both machines it had ever run on happened to agree"
---

A suite is evidence about the conditions it ran under and about no others. Two
of those conditions are almost never written down, and both report green with
total confidence when they are wrong: **the machine it ran on**, and **the size
of what it was handed**.

**The machine.** A suite that has only ever executed on developers' machines has
been passing against whatever those machines accumulated — directories that
exist because something created them once, tools on `PATH`, config set months
ago, caches. None of it is in the repository, and all of it is load-bearing
until proven otherwise.

Two conditions belong on that list and are almost never thought of as
environment at all, because they are properties of the process rather than of
the disk. **Who the suite runs as:** a case that proves a refusal by making a
path unreadable proves nothing under a uid that ignores permission bits, and
root is the default in more container images than not. **What locale it runs
under:** every program that compares or orders text collates, and pinning
`LC_ALL` on the producers while leaving it off the consumer means the two agree
by luck — which they will, on any two machines that happen to share a default.

**The size.** Fixtures are sized for legibility — two or three entries, enough
to show the case. Some defects are invisible at that size and certain at the
real one: buffering and pipe behaviour, timeouts, memory, sort stability,
anything quadratic, anything that depends on a producer still writing when a
consumer stops reading.

**Why:** the failure in both is not a missing case. Case coverage, environment
coverage and scale coverage are three different axes, and a complete corpus on
the first proves nothing about the other two. In the machine incident the corpus
held exactly the right case — a delete inside a scratch directory, expected to
be allowed — and it passed, because the path it named happened to exist. In the
scale incident the mechanism was that small inputs complete inside a single
buffer, a single batch, a single tick, so the code never enters the state where
the bug lives: a per-item lookup closed a pipe early, and with four entries the
producer had already finished writing, so no SIGPIPE occurred.

The obvious alternative in each case is the same mistake. "Run it on a
colleague's machine too" fails because a second working machine has the same
leftovers for the same reason — what distinguishes a clean environment is not
that it is *different*, it is that it is *empty*. "Trust the suite because it is
comprehensive" fails because it is comprehensive in the axis you were counting.

**How to apply — the machine:** give the suite a run in a fresh environment on
every change — CI, a container, or a scratch user account — and treat that as
the authoritative result when the two disagree. The local run stays, because it
is the fast one; it stops being the one that decides. While writing a case, ask
what has to be true of the machine for the expected answer to hold. If the
answer names anything outside the repository, either construct it inside the
case or add a sibling case that reaches the same code path with it absent. A
path that does not exist is a state, and it is usually the untested one.

**How to apply — the size:** keep the small fixtures for readability, and add
one case that carries production scale. Generate the input rather than writing
it out, assert that the command reaches a verdict at all, and prove the case
fails against the unfixed code before trusting it. Where the real scale is
unknown, use the largest instance the system has actually seen. A cheap tell
during review: if every fixture in a suite fits on one screen, the suite has
never exercised size.

**Related:** the `verify` skill's fifth condition — *reading the real thing* —
is the principle; this is the runbook for the two conditions that go unwritten
most often. `rules/craft/make-the-tool-say-why-before-deciding-why.md` is the
same instinct pointed at a refusal rather than at a pass.
