---
rule: before reporting, name the claim and name what establishes it — a command proves only the question it asked, a truncated output only its own part, and a decision nothing at all about the world
scope: process
canon: 3
evidence: "incidents, merged. In a multi-agent run, a call exhausted its structured-output retries and was reported as a hard failure while its pull request had merged; a second agent reported as running while it babysat its own poll loop and never returned, its work having landed without it — a task was nearly re-run from scratch against an already-merged branch. A reflog piped through `head` showed three clean commits and the audit was reported as finding nothing; a fourth was found later by hand, carrying private residue to a remote, and the repository had to be deleted and recreated. A ruling that a project must not be touched was written up as evidence that nothing was installed there, and reached two shipped documents. A commit was reported as pushed because the commit before it had succeeded, and cached versions as in use because a marker path existed, when that path is a directory of locks and it was empty. A claim about how a permission layer matches commands was written from the shape of the pattern, then rewritten from the vendor's own published documentation, and both were wrong about the running machine — the first reached the default branch in a file that ships verbatim, one publication away from being a consumer's, before a probe caught it, and one paragraph took three attempts to state. A project's repository visibility was asserted from the title of one of its own commits, which said what its author had been doing and not what the repository is; the false version reached the default branch in files that ship verbatim and in entries that cannot be edited"
---

A green result is evidence for the question it answered and for nothing beside
it. Before stating a result, say the claim in words, then look at what is
supposed to support it and check the two are about the same thing.

Six substitutions, one shape:

- **A command that answered a neighbouring question.** Existence is not
  occupancy; a commit is not a push; a file being present is not it being
  non-empty; a process running is not it doing the work.
- **Output cut by `head`, `tail` or any limit.** It answers "what are some of
  these", never "what are all of these". A conclusion about a whole set —
  nothing leaked, no matches, everything checked — needs an unbounded run or a
  count.
- **A decision, read as an observation.** "Do not touch that project" does not
  mean the project is untouched; "we are not publishing yet" does not mean
  nothing is published; "that is out of scope" does not mean it is absent.
- **A specification, read as an observation.** Vendor documentation, a schema,
  a config file's own syntax, the shape of a pattern — each says what *should*
  happen. Only the running system says what does, and the two diverge: a
  permission rule documented as matching past a leading environment assignment
  did not, and a wrapper documented as stripped was not stripped while its
  neighbour was. Documentation is a better source than a guess and is still not
  a measurement.
- **A commit message, changelog entry or pull-request title, read as a fact
  about current state.** It is evidence of what somebody meant at the moment
  they wrote it, and it was often true then. About today it establishes
  nothing: a commit titled "keep internal files out of the public repository"
  says what its author was doing, not that the repository is public — and it
  was not. This one is especially easy because the wording is *specific*,
  written by someone with direct knowledge, and sitting in the history you are
  already reading.
- **A harness's own failure or timeout signal, read as a fact about the work.**
  A run reported as failed, an agent reported as stalled, a call that exhausted
  its retries — each is a claim about the machinery that was meant to do the
  work, never about whether the work exists. The branch, the pull request and
  the merge are what settle that, and they have disagreed.

**Why:** each substitution is invisible from inside. The command *did* succeed,
the three clean lines look identical whether they are the only three or the
first three of thirty, and a decision arrives as a settled sentence from the
same source as a fact — usually the more recent one, so it overwrites the older
factual question without the swap being noticed. A specification is the worst
of them, because it is *authoritative*: it is written by the people who built
the thing, it is usually right, and reading it feels like research rather than
like guessing.

What is missing in all of them is a step that leaves no trace when it is skipped:
reading the claim back against its support. Canon §3 says run the proving
command and read its output, and every one of these obeyed that literally — a
command ran, its output was read, and it proved something adjacent. So "did I
verify this" is the wrong self-question and answers yes; "does this answer *this
sentence*" is the one that catches it.

It is worst where the proxy is nearly always right. A marker path usually does
mean the thing is held, a successful commit is usually followed by a push, the
interesting item is usually not the one past the limit. The shortcut is
reinforced every time it works and fails only in the case that matters.

**How to apply:** write the sentence you are about to report, then name what
supports it underneath. If the sentence contains a word the support never
established — *held*, *pushed*, *empty*, *running*, *clean*, *none*, *all* —
that word is unverified and either gets its own command or leaves the sentence.

A claim about behaviour is the case with the sharpest test: if the sentence
describes what a system *does*, the support is a run of that system and nothing
else. Reach for the documentation to learn what to probe and what the answer
means — never as the answer. Where a probe is genuinely impossible, say the
claim is the vendor's and unverified here, which is a different and honest
sentence.

Prefer checks that answer the claim directly: count the entries rather than test
the directory; re-run without the limit, or pipe to `wc -l` and state the
number; look at the install, the remote, the tree, rather than at what was
decided about them. Where the full output is genuinely too large, count first
and sample second and say which — "142 results, checked the 20 most recent" is
honest, "clean" is not. The same applies to a subagent's report: an agent
quoting a truncated command has proved as little as you would have.

Where an answer cannot be checked at all, say which decision it rests on rather
than asserting the fact. "We agreed not to touch it, and I have not verified its
state" is a different claim, and an honest one.

When a report has already gone out, correct it plainly and say what the evidence
actually proved.

**Related:** Canon §3 is the general form, and this is the collection of ways to
satisfy it literally and still be wrong.
