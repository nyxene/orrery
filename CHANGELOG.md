# Changelog

Every release of Orrery is recorded here, newest first. The version is the
`version` field in `.claude-plugin/plugin.json`: Claude Code decides an
installed plugin has an update from that number and nothing else, so a change
without a bump reaches nobody.

<!-- Assembled by tools/changelog.sh from changelog/<version>.md. Do not edit
     this file: one release is one file there, and that file is also the body
     of its GitHub release page. -->

## 0.10.7

A guard that stopped refusing ordinary work, a planning skill that has to run
something, and a recorder you can switch on.

This release was audited before it was assembled, by an agent that did not write
it. That audit found six commands the guard used to refuse and had stopped
refusing — two of them introduced by the very changes meant to make it safer.
All six are fixed below, and they are the reason this release is worth taking.

### The Bash guard stopped refusing read-only work

The command splitter cut on operator characters wherever they appeared,
including inside quoted strings. A grep with an alternation, a jq filter, a
heredoc delimiter and a shell keyword each arrived at the head of a segment and
were read as commands nobody had listed — nine refusals of plainly read-only
commands in a single session.

The inconvenience is not the point. This guard's own denial text says that a
refusal which gets routed around is the failure it exists to prevent, and during
that session it was routed around twice before the cause was found. A guard that
cries wolf teaches people to walk past it.

Splitting is now decided by what the shell would actually interpret: nothing
inside single quotes, only substitutions inside double quotes, everything
outside. Redirects still split everywhere, because inside an awk program a `>`
really is a write. Heredoc bodies are data rather than shell. Shell keywords and
the loop variable after `for` are syntax, not commands. A variable holding a
path is an assignment, not a verb.

Two things that closed rather than loosened: an interpreter fed by a heredoc is
running inline code exactly as `-c` does and is judged on those terms, and a
command substitution now starts a fresh context so the quotes around it stop
leaking into it.

### An open heredoc was hiding the rest of the command

Found by the audit, and the most serious thing in this release.

The splitter entered heredoc-body mode on any `<<` and left only at a line
exactly equal to the delimiter — so anything it mistook for an open heredoc
swallowed everything after it, including a deletion or a write to a system
directory. Four ways in: a herestring `<<<`, whose delimiter scanned as `<`; an
arithmetic left shift `$((1<<n))`; `<<-` with the tab-indented terminator bash
allows; and `cat <<EOF>/dev/null`, where the redirect was taken into the
delimiter.

Each is fixed, and two backstops now make the class safe rather than the four
instances: a delimiter has to look like a word, and its terminator has to
actually appear ahead in the input. Both are checked before the body is trusted
to end.

Also from the audit: ANSI-C quoting (`$'...'`) inverted the quote state for the
rest of the command, and deletion verbs were matched case-sensitively on a
filesystem that is not — `RM -rf` runs the same binary as `rm` and matched
nothing.

### A delete could land one character outside the scratchpad

The check that a deletion targets the session scratchpad compared a prefix and
nothing else, so a sibling directory whose name merely began with the same
string passed it — as did a path that reached one through `..`.

### The Write and Edit tools were missing three system trees

The Linux system trees were in the Bash guard and absent from the deny-list, so
on Linux a write there was refused through the shell and allowed through the
editing tools. The deny-list is 99 entries.

### `plan` has to run something before it plans around it

A question whose answer is a number or an observable behaviour is now settled by
running the smallest thing that answers it, and the result enters the plan as a
fact. Bounded so it stays a question rather than the start of the work: nothing
written outside the scratchpad, no external service changed, the code thrown
away and only the result kept.

VERIFIED has a definition — a command was run, its output was read, and the
command is written beside the assumption. A three-tier confidence scale handed
out with no command behind it is the evidence rule suspended at exactly the
point where it decides a design.

The route is chosen by the *kind* of uncertainty rather than its size.
Uncertainty about the present is settled by a reader; uncertainty about the
future is not, and hiring more readers for it is the most expensive mistake
available. After a spike the route is decided again, usually one step lower.

The pre-mortem moved from the heaviest mode to all of `consensus` — it was
behind the narrowest gate in the file while being the only technique there aimed
at assumptions nobody stated. And the iteration cap counts the work rather than
the document: two rounds per plan, with nothing counting plans, is how five of
them each stayed inside the limit while ten review rounds produced no code.

### `debt` could no longer tell an empty pool from a blind one

A debt issue filed without a scope label, then a pool query that filters by
scope, returns nothing and reports a clean pool. The unfiltered count now runs
first, and debt existing while the pool reads empty is named as a defect with a
fix rather than as a result. Both queries page to 200, because a page boundary
and a clean tracker look identical.

### Optional: record which tools were called

Set `ORRERY_CALL_LOG` to a path and a hook appends one line per tool call: a
timestamp, a fingerprint of the session, the tool name, the subagent type, and
whether the spawn was named. Never a command, a prompt, a path, a branch, or an
agent's name. Unset by default, capped, and `--purge` empties it.

It exists because a skill cannot record the run in which it ignored its own
instructions — the same omission removes the behaviour and the evidence of it.
`sharpen` reads it.

Nothing is transmitted. The privacy section is more precise than it was: no hook
makes a network call, one skill does when you run it and the page says which and
what it sends, and the only thing ever written about your usage is this log, on
your disk, if you asked for it.

### The rule set shrank, and two rules became machinery

Four rules left `rules/process/`, none of them because the incident stopped
being real.

Three of them described the same law from different angles — a command that
answered a neighbouring question, output cut by a limit, a decision read as an
observation — and are now one rule carrying all three incidents. A rule set only
grows unless something shrinks it, and three files saying nearly the same thing
is how one stops being read.

The fourth was about checking, before closing an epic, that nothing already
tracking its doneness disagrees with you. That is a step in `verify` now rather
than a rule of its own: a procedure beats a sentence asking someone to remember.

A fifth left because the deny-list already enforces it. Staying out of system
folders is a machine's job, and it has been doing it since the deny-list gained
those entries.

Sixteen rules ship, down from nineteen. One of the three left because it
restated a canon section almost word for word, and its own body opened by
saying so — the canon line gained the one thing the rule had that it did not,
and the file went. A law stated twice is a law that drifts in one of the two
places.

Four more left the workshop's own rule set the same way, and two of them landed
in skills you have: `build` now says to commit the plan document before any
worktree agent launches — a worktree is made from a commit, so a plan that
exists only in the working tree is not in it — and to wait for a chained task's
pull request to actually merge rather than for a workflow to report success.
`handoff` now says that a follow-up somebody flagged and nobody closed comes
back every relevant session until it does, which is the one thing that survives
a handoff being rewritten.

### The guards failed open on their own errors

The most important fix here, and the one nobody would have noticed.

The harness reads a non-zero hook exit as a non-blocking error and runs the
command anyway. Both guards run under `set -euo pipefail`, so any failure they
did not anticipate — a malformed payload, a missing tool, an unset variable —
made them fall over and the command they never checked proceeded. Their own
headers had always claimed the opposite, and only the branch handling a missing
`jq` made it true.

Both now refuse on any internal failure. Feeding either one input it cannot
parse produces a refusal rather than silence, which the test suite asserts
directly — that check cannot live in the case corpus, because the corpus builds
valid input by construction.

Two things about the fix are worth stating, because each was wrong first. An
`ERR` trap does not fire on an unset-variable exit, so it looked complete and
was not. And a trap whose body starts `[ "$rc" -eq 0 ] && exit 0` is killed by
`set -e` before it can refuse, which made the first version silently do nothing
at all.

### A guard that refused reading because a delete appeared elsewhere

Inline interpreter code — `python3 -c "…rmtree(…)"`, or the same program handed
over as a heredoc — is judged inside the segment that runs the interpreter now,
rather than across the whole command. The wider test refused any command holding
both an interpreter and the word `rm` anywhere in it: a test payload, a path, an
unrelated second command. It did that four times in one day to the person who
wrote it. Every hole it existed to close is still closed and now has a case.

### One new rule

`rules/process/a-command-proves-only-the-question-it-asked.md` — a command that
exited 0 proves only what it tested. Before reporting, say the claim in words
and check that the command asked that question. Existence is not occupancy; a
commit is not a push.

Pre-1.0: skill names and layout may still move between releases. `jq` must be
on `PATH` before any hook fires.

## 0.10.5

One rule, about the way a check can be green and beside the point.

### A command proves only the question it asked

`rules/process/a-command-proves-only-the-question-it-asked.md`.

Canon §3 says run the proving command and read its output. It is possible to do
exactly that and still report something false: the command succeeds, its output
is read, and it proves a fact next to the one being claimed. Existence is not
occupancy. A commit is not a push. A file being present is not it being
non-empty.

What makes this hard to catch is that nothing looks wrong from inside — no
error, no truncation, no gap. The missing step leaves no trace when it is
skipped, which is why *did I verify this* answers yes and catches nothing. The
question that catches it is *does this command answer this sentence*.

The rule is to write the sentence you are about to report, name the command
under it, and check that every word the sentence commits to — held, pushed,
empty, running, all — is a word the command actually evaluated.

It loads on `process` scope.

Pre-1.0: skill names and layout may still move between releases. `jq` must be
on `PATH` before any hook fires.

## 0.10.4

An eighteenth rule, and a counter that could no longer be changed.

### A rule for the operation that was reserved

`rules/git/reserved-operations-never-ride-in-a-batch.md` covers the case where
someone has said an operation is theirs — not to be delegated, or needing their
word each time — and it is then performed anyway as one line inside a block run
for some other purpose. Not defiance: the reservation was remembered when it was
made and never consulted when the batch was composed, and inside a block whose
stated purpose is *run the gates*, a destructive line reads as routine because
its neighbours are.

The rule is that such an operation runs alone, in its own call, with its own
sentence announcing it. No guard can carry this one — it is about how a command
is run rather than what the command is — so the rule is the whole of it.

It loads on `git` scope, so it arrives when a session touches git and stays out
of the way otherwise.

### Release notes are no longer read as claims about the present

`sharpen`'s claims checker requires every number a document states to match what
is on disk, and the assembled changelog was in its scope. That file carries
every count any past release ever stated, and a release note describes a past
state by construction: 0.10.0's notes say seventeen rules and always will.

So the checker blocked any future change to any counter — rules, skills, agents,
hooks, deny rules — and the only way past it was rewriting the record of a
release that had already gone out. This is why the rule above is arriving now
rather than in 0.10.2.

The counting pass now skips the changelog. The pass that verifies every named
path still resolves keeps reading it, because a path named in a release note
should still be there.

### The gates badge reports `main`

The badge on the front page pinned no branch, and the same workflow runs on
release branches inside every release pull request — so it could show the
verdict of a pull-request run rather than of `main`. Both the badge and the link
beside it now filter to `main`.

Pre-1.0: skill names and layout may still move between releases. `jq` must be
on `PATH` before any hook fires.

## 0.10.3

Three refusals that were wrong, and one of them had been wrong since 0.10.0.

### The guard no longer refuses your own scratchpad

A delete inside the session scratchpad was denied whenever that directory did
not exist yet. The check resolves the target against the filesystem before
comparing it, and when the parent is missing the resolution produced `/x` — a
path outside the scratchpad by construction, so the deny was certain.

It only ever happened where the directory was absent, which is never on a
machine that has been running sessions and always on a fresh one. That is why
0.10.0 and 0.10.2 shipped with it: the corpus is green on any developer's
machine and red on every clean checkout.

Resolution now falls back to collapsing `.` and `..` textually when the
filesystem cannot answer. A path that climbs out of the scratchpad is still
refused — the fallback is normalisation, not the raw string, and the difference
is exactly what a prefix test can be fooled by.

### `git tag -d` is allowed again

0.10.2 shipped a section that refused every spelling of ref removal, including
`git tag -d`, `git tag --delete`, `git branch -d` and `git push --delete`. It
was withdrawn in the workshop the day after it was written and this release is
the first that could carry the withdrawal.

The reason it went: a `PreToolUse` hook sees a command, not who typed it, so a
rule meant to stop an agent from destroying a ref the operator reserved stops
the operator too. Two deny-list entries go with it.

### `feedback` files nothing, and hands you a link instead

The skill used to run `gh issue create` against a fixed repository. It is
installed into projects that are not that repository, so the command was
reachable from every one of them, and only the surrounding prose stood between
that and an issue nobody asked for.

Now it prints the report and a URL with the form already filled in from it, and
you submit it or it does not get submitted. Long reports do not fit in a URL, so
the summaries are prefilled and the rest is printed underneath to paste — the
skill says so rather than sending a link that arrives cut.

Pre-1.0: skill names and layout may still move between releases. `jq` must be
on `PATH` before any hook fires.

## 0.10.2

Release notes get their own files, and this release is the first to have one.

### One release is one file

`changelog/<version>.md` is now the whole of a release's notes, and it is what
the GitHub release page carries — sent byte for byte, with nothing reading it on
the way. `CHANGELOG.md` is assembled from those files and is never edited by
hand.

The version before this one located its notes by finding the right section
inside `CHANGELOG.md`, which meant deciding where a section ends: the next
heading, unless it is inside a fenced code block, unless that fence is inside
another fence. Every valid changelog that broke it broke it silently — a
truncated release page and a successful exit. A boundary you have to find is a
boundary you can get wrong; a file has one already.

### Also

- `SECURITY.md` and the Code of Conduct route reports through GitHub rather than
  an address, so no inbox has to be watched for a channel to work.
- `install/into-project.md` lists the `feedback` skill, which 0.10.0 shipped
  without naming, and states the deny-list count that ships with it.

There is no 0.10.1. Its build was assembled, refused by the publication checks
over a stale number in this README, and never left the workshop — and a stage
build is frozen once made, so the correction is the next version rather than a
second attempt at the same one. Nothing was published under it.

Pre-1.0: skill names and layout may still move between releases. `jq` must be
on `PATH` before any hook fires.

## 0.10.0

First release.

Earlier version numbers exist in the workshop's history and never reached
anyone; this is the first tree that leaves it.

### The method

- **[CANON.md](CANON.md)** — eight non-negotiable working rules, loaded into
  every session by hook.
- **Thirteen skills** — `frame`, `plan`, `build`, `review`, `diagnose`, `pare`,
  `verify`, `debt`, `doctor`, `feedback`, `handoff`, `learn`, `sharpen`.
- **Four agents** — `planner`, `architect`, `critic`, `auditor`: the
  consensus-planning loop and the independent audit.
- **Five hooks** — the Bash guard and the agent guard, the canon and scoped-rule
  loaders, and the handoff prompt that fires before compaction.
- **17 rules** in [rules/](rules/), each carrying the evidence it was earned
  from.
- **[install/into-project.md](install/into-project.md)** — the facts a host
  project declares in its own `CLAUDE.md` so the skills read its labels, gates
  and model tiers instead of guessing.

### The repository

- [LICENSE](LICENSE) — MIT, matching what the manifest and README have always
  declared and what no file previously carried.
- [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md) and a
  [Code of Conduct](CODE_OF_CONDUCT.md).
- Issue forms for bugs and for friction, a pull-request template naming the
  gates, and `CODEOWNERS`.
- A CI workflow running the same gates as `.githooks/pre-commit`, because
  `core.hooksPath` is local config and a fresh clone has the hook on disk and
  switched off — which looks exactly like having it.

Pre-1.0: skill names and layout may still move between releases. `jq` must be
on `PATH` before any hook fires.
