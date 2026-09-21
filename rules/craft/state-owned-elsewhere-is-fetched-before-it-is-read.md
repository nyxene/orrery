---
rule: state owned by another system is fetched before it is read — a local mirror answers the right question with full confidence whether or not it has been refreshed
scope: craft
evidence: "twice. A library's maintainers answered questions about what a *consumer* had installed by reading their own working tree, which their one-way publication flow keeps ahead of anything released: a file added the day after a release was recommended to that consumer as something to copy out of its own install, where it does not exist, and the consumer's repository visibility was asserted from the title of one of its own commits rather than from a command. The second reached the default branch in files that ship verbatim, and in a commit message and two tracker entries that cannot be edited; a whole second change was spent on the half that could. Both were caught by the consuming project, not by any gate. Earlier: a release was prepared against a version number that had already shipped four hours earlier. The clone's newest tag and the local status tool agreed with each other and with nothing real; release notes for an already-published version were edited before a publishing gate — the one component that had to reach the other system to do its job — refused the attempt. Cost was a release cycle spent twice"
---

A fact that lives in another system — a remote's tags, a published release, an
installed package's version, an index — has a local copy that is a snapshot, not
the fact. Refresh it in the same breath as reading it, or state which reading
you are giving.

**And the local thing is sometimes not a copy at all.** Your own checkout of a
library is not a stale mirror of what it published; it is a *different artefact
that is ahead of it by design*, and a one-way publication flow guarantees the
gap rather than merely permitting it. That distinction decides whether this rule
fires: a rule about refreshing does not reach a case where there is nothing to
refresh. Reading your own source tree to answer "what does their install
contain" is not a stale reading of the right thing — it is a confident reading
of the wrong thing.

**Why:** staleness has no failure mode of its own. The command succeeds, the
output is well-formed, and it answers exactly the question asked — about a copy
whose age nothing prints. Every local reading agrees with every other local
reading, because they all descend from the same snapshot, so cross-checking
locally *increases* confidence while proving nothing. That is the trap: three
sources concurring reads as verification and is a single source counted three
times.

The obvious alternative is to trust the tool that summarises the state, which is
worse rather than better. A status tool is written against local data by
construction — it is the thing you reach for precisely because it saves a
network round trip — so the more convenient the reading, the staler it is
allowed to be. The one component that reads the real state is whichever one has
to talk to the other system to do its job, and it usually speaks last.

Note what this is *not*. The command did not answer a neighbouring question; it
answered this one, correctly, about the wrong snapshot. So the check that
catches a proxy — does this output answer this sentence — passes here and
catches nothing.

**How to apply:** before any decision that turns on state another system owns,
name the system and refresh from it.

- Tags, branches and releases: fetch first, or ask the owning repository
  directly — querying it beats reading a local tag, because the query cannot be
  stale by construction.
- **Anything about another party's installation** — its version, which files it
  has, what its documents instruct — is read *in that install*, never in your
  own tree and never in the document your tree carries. The two are different
  documents with the same path, and yours is the one nobody has. A path is not
  shared context: before telling someone to run or copy `$TOOL/some/file`,
  list it in **their** root.
- A summarising tool: check what it reads before believing it about the world.
  If it reads local files only, its answer is scoped to this clone and should be
  reported that way. A tool that can fail to refresh must say so; a refresh
  whose failure is swallowed makes a stale reading and a current one identical.

When a refresh is not possible — no network, no credential — say which reading
you are giving rather than presenting a snapshot as current. "The newest tag in
this clone is X; I have not asked the source" is a different and honest claim.

**Related:** `rules/process/a-command-proves-only-the-question-it-asked.md` is
the neighbouring failure and the one this is most easily mistaken for — there
the support answers an adjacent question, here it answers the right question
about an old copy. `rules/craft/gates-must-run-where-nobody-works.md` is the
same instinct one level down: an environment nobody exercises is one nobody has
measured, and a mirror nobody refreshes is one nobody has read.
