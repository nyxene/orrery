# Changelog

Every release of Orrery is recorded here, newest first. The version is the
`version` field in `.claude-plugin/plugin.json`: Claude Code decides an
installed plugin has an update from that number and nothing else, so a change
without a bump reaches nobody.

<!-- Assembled by tools/changelog.sh from changelog/<version>.md. Do not edit
     this file: one release is one file there, and that file is also the body
     of its GitHub release page. -->

## 0.27.0

**Minor.** The Bash guard refuses five kinds of inline deletion it used to
let through. When it refuses a deletion found inside inline code, it now
says how to do what you most likely meant.

### More inline deletions are caught

The delete check reads inline interpreter code for delete calls. It only
treated `-c` and `-e` as inline code, so these passed:

- `node -p` / `node --print`
- `node --eval`
- `deno eval`
- `php -r`
- `bash --command`

Each of them can delete, and each is refused now. Long flag bundles such as
`bash -xeuc`, and a flag glued to its code such as `bash -c'…'`, count as
inline code too.

**What it costs:** `-r` and `-p` are also ordinary flags for some tools.
`node -r ts-node/register src/remove.ts` and `npx -p <pkg> … remove.ts` are
now refused when a delete word sits in the same command. `node --require`
passes.

### A delete refusal in inline code says what to do

Inside inline code (`python3 -c`, a heredoc into an interpreter, `node -e`)
the check reads delete words in strings too. So code that only *writes* text
containing "remove" or `rm -rf` is refused as if it deleted something. That is
deliberate. Emptying string literals before matching was built and tested,
and every version of it could be fooled into hiding a real delete call. This
check is the only one protecting your working directory, so it does not take
that risk.

What changes is the denial. When the word was found in inline code, it now
says that strings count too, and that text which only mentions a deletion goes
into a file with the Edit or Write tool. Before, the refusal gave no way
forward. An agent that thinks a refusal is wrong should say so, not find
another route to the same command.

**What you need to do:** nothing.

No file leaves the product. No deny rule is added or withdrawn.

## 0.26.0

**Minor.** The Bash guard refuses a different set of commands, in both
directions. A secret file named as text no longer refuses a command. A file
named as a path is refused in many forms that used to pass. Separately,
`CLAUDE.md` moves into `.claude/` in this repository, because the current
`claude plugin validate --strict` refuses it at the plugin root.

### The guard judges the words a command is handed, not its text

The checks for system config (`/etc` and its neighbours), the credential stores
under your home folder (`~/.ssh`, `~/.aws`, `~/Library/Keychains` and the rest)
and secret files (`.env`, `.netrc`, `.npmrc`, private keys) used to search the
whole command line for a name. So the name refused a commit message, an issue
body, a `sed` expression or a heredoc writing source code exactly as it refused
`cat .env`. A false refusal like that teaches the walk-around: in one project an
agent moved a refused edit into a script file, which the guard does not read,
and ran that.

A name is now refused when it *is* a word the shell hands a command, or a
redirect target. The guard reads quoting the way bash does, follows `$(…)` and
backticks wherever they run, reads heredoc bodies as bash does, and decodes
`$'…'` escapes.

- **Now allowed:** a name inside a quoted message, a `--body`, a `sed`
  expression, `echo "…"`, a heredoc body handed to `cat`, a comment.
- **Now refused**, where the old matcher let them through: forms such as
  `cat .env;`, `cat .env>out`, `(cat .env)`, `echo "$(cat .env)"`,
  `cat ${HOME}/.aws/credentials`, `cat $'\x2eenv'`, a substitution hidden in
  arithmetic or in a parameter expansion, and `cat .env .env.example`. One
  example file used to exempt the whole command.
- **Unchanged, on purpose:** inline interpreter code is still read as text —
  `python3 -c`, `node -e`/`-p`, `php -r`, a heredoc or pipe into an
  interpreter, `eval`, an `awk` program. Where no sandbox is on, that is the
  only catch for an inline read of a private key, so inline code that merely
  *writes* a name is still refused. The denial now says so and names the Edit
  and Write tools as the way to put that text into a file.

**What you need to do:** nothing. If a command of yours was refused only because
a message or string named one of these files, it passes now.

### This repository's own instructions and gates

`CLAUDE.md` moves to `.claude/CLAUDE.md`, where Claude Code reads it too. The
pre-commit hook now runs every gate without the `GIT_*` variables git exports
into hooks. From a linked worktree those include an absolute `GIT_DIR`, and a
suite building a git fixture then wrote into the repository being committed.

**What you need to do:** nothing, unless you work in a clone of this repository.
Then the root `CLAUDE.md` is gone and `.claude/CLAUDE.md` holds the same text.

One file leaves the product: `CLAUDE.md`, moved rather than removed. No deny rule
is added or withdrawn.

## 0.25.0

**Minor.** `/doctor` stops making two false claims. Behaviour you can observe
changes, because two lines it prints are different. Nothing you run is refused
that was not refused before, and nothing else ships changed.

### A write that failed is no longer reported as recorded

The doctor keeps two pieces of state under your home directory: the cache
baseline its edited-install check compares against, and a log of its runs.
When that directory refuses a write, as it does in a sandboxed session, a
locked-down machine or CI, the run used to print `✓ … new baseline recorded`
right under the shell's own `Operation not permitted`, followed by the path of
a log it had not written. Every later run was then another first run, and
nothing said so.

The writes are now checked. A failure reads `could not record a cache
baseline … whether the cache was edited cannot be checked`, and the last line
reads `log not written`.

### A project's own issue gate is no longer reported missing

The doctor knew only this library's pull-request matcher by name. A project
that refuses a pull request naming no issue through a workflow of its own was
told that nothing refuses one. A gate like that has to read the pull request
body, so the doctor now finds it by that. It reports the gate as *likely*, with
a neutral mark rather than a ✓. The matcher is not this library's, so what it
refuses is not verified, and a notifier reads the body too.

**What you need to do:** nothing.

No file leaves the product. No deny rule is added or withdrawn.

## 0.24.0

**Minor.** The retrospective gate gains its server half. An issue closed by a
merge — `Closes #N` — was never seen by the hook that refuses a bare close,
and on a project that lands work through pull requests that is most closes. An
opt-in workflow now covers it, and `close-issue.sh` gains the three modes it
needs to live alongside it.

Nothing you run is refused that was not refused before. What changes is what
the process guard's refusal tells you, one line the doctor prints, and every
close `close-issue.sh` makes, which now says it was completed.

### A merge-closed issue owes its retrospective too

Measured on one host over a week: more than a hundred issues closed as finished
work, one carrying a retrospective — while every merged pull request named an
issue, because a gate held that half. The method was followed exactly where
something enforced it and nowhere else.

`install/ci/retrospective-on-close.yml` runs on `issues: closed`. An issue
closed as *not planned* or *duplicate* is left alone. One carrying a
retrospective, or a recorded waiver, is left alone. Otherwise it is reopened,
with one comment naming the command that closes it properly.

It waits 45 seconds before reading, because a session that merges and then
posts does so a few seconds later, and reads again after reopening so a
retrospective that lands in between closes it back. If it cannot read the
comments it fails the run and reopens nothing. Its matcher is a separate script
with a suite, and its test for a retrospective is the one `/doctor` counts with,
so the two cannot disagree.

**What you need to do:** nothing, unless you want it. It is a copy, like the
pull-request gate beside it:

```bash
cp "$ORRERY/install/ci/retrospective-on-close.yml" .github/workflows/
cp "$ORRERY/install/ci/retrospective-on-close.sh" "$ORRERY/install/ci/retrospective-on-close.test.sh" install/ci/
```

**What it costs, said before you meet it.** On a project that has been closing
issues by merge without retrospectives, the first days reopen a lot of them.
That is the gate working. An issue you close by hand as *completed* is reopened
too; close it with `--waive` instead, or as *not planned* when that is what it
was. If agents on your project take work from open issues, a reopened one looks
like work — the comment says why it reopened.

It cannot see a merge made by a workflow running on `GITHUB_TOKEN`, a bot
auto-merge for instance, because that raises no `issues` event. `/doctor`'s
count of closed issues without a retrospective still catches those, and now
names this workflow beside the number.

### `close-issue.sh` gains three modes

- **`--no-close`** posts the retrospective and leaves the issue open. `build`
  now posts it **before** the merge this way, so the merge closes an issue that
  already carries one and the workflow never has anything to do. Merging first
  and posting after is the order that loses the race.
- **`--not-captured`** is for closing an issue from a session that did not do
  the work — the usual case after the workflow reopens one. Without it the spend
  table measures whichever session runs it and posts your numbers as the work's.
- **`--waive "<reason>"`** closes without a retrospective, on purpose. It posts a
  marker the workflow reads and writes the local waiver row. The marker shares no
  prefix with the retrospective header, so `/doctor` never counts a skip as a
  retrospective.

Every close it makes now passes `--reason completed`.

### The guard's refusal points at the path that survives the server

When `gh issue close` is refused, the way past it the guard names is now
`close-issue.sh <N> --waive "why"`. The older `ORRERY_WAIVE="why" gh issue
close <N>` still works and still records the row — but only locally, so on a
project running the workflow the server sees a bare close and reopens it. The
refusal and the install guide both say so.

**What you need to do:** if a script of yours closes issues through
`ORRERY_WAIVE`, and you install the workflow, switch it to `--waive`.

### Also

The process guard's own header claimed the server half of this gate had been
filed as separate work. It had not. That sentence is corrected, and the half it
promised is the workflow above.

No file leaves the product. No deny rule is added or withdrawn.

## 0.23.0

**Minor.** A command you have been able to run since the first release starts
being refused, and a hook now runs before every shell call. Both are the same
change: the method's bookkeeping obligations stop being honour-system and start
having a gate behind them — with a supported, recorded way past.

Also here: a pull-request gate that has been named in the manifest since the day
after 0.22.0 shipped and therefore reached nobody, and a doctor that can finally
see an install it has been reporting as absent.

### `gh issue close` is refused unless the issue carries its retrospective

Measured across three projects over one week: **179 issues closed, 218 pull
requests merged, 2 retrospectives.** Nothing in the method had a refusal behind
it, so following it and not following it left identical traces — which is to say
no trace — and the only reason anyone found out was somebody going and looking.

`hooks/process-guard.sh` is a third guard, and it is a different trade from the
two you already have. The Bash guard exists for accidents that cannot be undone
and stays deliberately thin; this one is bookkeeping, where a false refusal
costs an argument rather than a boundary. So it is a separate file with its own
case corpus, and it **fails open**: anything it cannot parse is passed through.
That direction is deliberate and its corpus pins it. A bookkeeping gate that
blocks every command when `jq` is missing gets removed within the hour, and
removing it takes the delete guard with it.

`skills/build/close-issue.sh` is what it refuses the bare command in favour of:
it posts the retrospective and closes the issue in one act, so there is nothing
to verify — the only close that happens is one that posted. It generates the
machine-readable header and the spend table from your session's own transcripts,
which means the half of a retrospective that actually answers *what did this
cost* is the half nobody has to write.

**What you need to do:** nothing, unless you close issues from a script. If you
do, point it at `close-issue.sh` or waive deliberately — see below. If you have
been closing issues by hand and wondering whether the retrospective step was
real, it is real now.

### Skipping stays possible, and stops being invisible

`hooks/waiver.sh` records one line per waived obligation: the act, the reason,
and whether the reason was stated or inferred. **The only way past the gate is a
command that writes that line.**

This is the argument `--no-verify` already earns in a pre-commit hook. The point
was never that skipping is impossible — it is that skipping becomes something
somebody typed. Either a row carries a reason, or the gate was circumvented, and
that is a violation with a name instead of a silence indistinguishable from
obedience.

### The pull-request gate a hook cannot be

`install/ci/pr-names-an-issue.yml`, with `names-an-issue.sh` and its test, now
actually ship. They were added to the manifest one day after 0.22.0 was
published, which means every consumer on that version has been reading an
install guide that does not mention them and running an install that does not
contain them.

A hook cannot do this job. Hooks see commands a session types; a merge closes an
issue server-side, from an event no local hook is present for. Measured across
three projects in one week before this existed: **nine pull requests merged
carrying no issue reference at all**, in projects where the rule was loaded into
every session.

**What you need to do:** it is a copy, not something the plugin supplies at
runtime, because GitHub Actions runs against your checkout and cannot read a
plugin cache. `install/into-project.md` carries the copy step under *Copy in the
one gate a hook cannot be*, and `/doctor` reports when the workflow is missing.

Two things to check before you copy it in, because neither is universal: a
second workflow does not block a merge unless the branch ruleset names its
check, and if your repository already refuses a pull request that names no
issue, you do not need this one. Installing it anyway costs you a duplicate run
on every pull request and buys nothing.

### `/doctor` can see a local-scope install

A plugin enabled in `.claude/settings.local.json` rather than in the tracked
`.claude/settings.json` — which is what any repository whose index other people
read ends up doing, private ones included — was invisible to two checks. In a
project where the plugin was installed, enabled and demonstrably running, the
doctor printed:

```
✗ no orrery install found for this project
✗ enabledPlugins missing/false on branch '<branch>'
```

Both false, and they are the two lines anybody reads first when asking whether
the plugin is on at all. Those two reds are why a working install was believed
to be broken.

Three things changed with it. Enablement is now resolved across **both**
settings files, and the report says **which one answered** — the tracked file
varies by branch, which is what makes *not enabled on this branch* a true
sentence, while the untracked one does not vary by branch and now says so
instead of naming a branch the answer does not depend on. And enabled-versus-
disabled now comes from the install record's own field rather than from a
plain-text block that carries no project attribution: on a machine with orrery
in several projects, that block belongs to whichever one the CLI printed first.
Where the text is too ambiguous to rule out a load failure, the report says
`enabled (load failure not ruled out)` rather than a clean pass it cannot
establish.

**What you need to do:** nothing. If you saw either of those reds and changed
your settings to satisfy them, change them back — a local-scope install was
always correct.

### A correction to what this plugin told you

`skills/doctor/SKILL.md` said that having both `orrery` and `orrery-method`
installed loads the canon twice and that you should disable one of them. That is
backwards, and the doctor's own code has been saying the opposite for weeks:
`orrery` is the machinery and it **declares** the method as a dependency rather
than carrying a copy, so both installed is the healthy state and `orrery` alone
is the failure — every skill loads, every guard fires, and the corpus they are
written against is simply absent.

**What you need to do:** if you disabled `orrery-method` on the strength of that
paragraph, re-enable it. You have been running the machinery without the law it
implements.

### Also

Two shipped rules gain the case that would have caught a real error. *State
owned elsewhere is fetched before it is read* was written about a stale mirror —
a local copy of the same fact — and did not reach the case where your own tree
is not a copy at all but a different artefact ahead of what you published; its
advice now widens from versions to what files an install has and what its
documents instruct. *A command proves only the question it asked* gains a sixth
substitution: a commit message, changelog entry or pull-request title read as a
fact about current state, which is evidence of what somebody meant when they
wrote it and about today establishes nothing.

The deny-list gains no rules and withdraws none. It gains a long measured note
on what a Bash deny rule actually binds — the spelling is matched per
subcommand, an env-assignment prefix and a loop body escape, and the platform's
documentation and the machine disagree on two of the probed spellings. Read it
before assuming a rule covers a spelling you have not tried.

No file leaves the product. No deny rule is withdrawn.

## 0.22.0

**Minor.** Nothing you run behaves differently, but `build` stops asking for
something the method does not require, and the install guide starts asking for
something it always read. Both are corrections to what this plugin *tells* you,
which is the part of a method that executes.

### `build` no longer demands a second model family

The audit tier's requirement read **"a different model family from the
implementers"**, under a heading saying the split is fixed, and the paragraph
below equated family with independence outright.

The corpus says otherwise, and it is the corpus this skill implements: a station
is passed in **a session of its own**, and different model families "on top of
that are an improvement rather than the mechanism […] not what independence
rests on".

So the Audit row now names the session as the requirement and the family as an
amplifier bought where the stake earns it.

**What you need to do:** nothing, unless you wrote the old requirement into your
own `CLAUDE.md`. If you recorded a single-model setup as a deviation from the
method, it is not one — an auditor spawned as its own agent already has its own
context, which is the mechanism. Delete the note.

The error ran both ways, and the quiet direction is the one worth knowing about:
a project with two model families that runs its audit *inside* the implementing
session read as conformant against the old table while breaking the only thing
that produces independence. If that describes yours, the fix is the `auditor`
agent type rather than a model choice.

### The install guide names the debt pool

`skills/debt/SKILL.md` reads a project declaration — the one active area whose
debt feeds the per-task quota — and the declarations table in
`install/into-project.md` never listed it. The word appeared in the table only
inside another row's consequence column, so a reader met the term and took it as
covered.

A project that followed the guide exactly declared labels and a quota, never a
pool, and got the fallback: the area the current task touches. Across several
area labels that is close to none of the narrowing the skill calls "narrow on
purpose", and nothing reported the difference.

**What you need to do:** if you have more than one area label in flight, add
`Debt pool: <the one active area>` to your `CLAUDE.md`. If your project works one
area at a time, the fallback is what you want and there is nothing to change.

### Also

One shipped rule — *a suite proves only the conditions it actually had* — gains
two environment conditions that are properties of the process rather than of the
disk: the uid the suite runs as, which decides whether a permission-based
refusal can be proved at all, and the locale, which decides whether a comparator
agrees with the sorts feeding it. Both were learned by moving a suite onto a
machine that disagreed with every machine it had run on before.

No file leaves the product. No deny rule is withdrawn.

## 0.21.0

**Minor.** `doctor` starts failing runs it used to pass. If `orrery` is
installed and `orrery-method` is not, the doctor now says so and exits non-zero —
because the corpus this plugin's skills are written against is, from this
version, a separate plugin that orrery declares as a dependency.

Nothing else changes. No skill behaves differently, no deny rule is withdrawn,
and no file leaves the product.

### What is new

`orrery-method` is the method itself: the corpus in English and Russian, a canon
that loads into every session, and a skill that routes to the document answering
a question. It is published on its own, and `orrery` depends on it rather than
carrying a copy — one corpus, one home, and no second copy to fall behind the
first.

The doctor grew a check for that arrangement. It reads every installed plugin
whose name starts with `orrery`, so a rename or a third product is named rather
than silently missed, and it reports three states:

| Installed | Verdict |
|---|---|
| both | healthy |
| `orrery` alone | **fails** — the machinery is here and the method it implements is not |
| `orrery-method` alone | reported: the corpus, without the machinery that executes it |

### What you need to do

Nothing, in the ordinary case: the dependency installs with orrery, so updating
brings the method with it.

If your first doctor run after updating says the method is missing, the
dependency did not install — most often because the marketplace refused the
cross-marketplace reference. Reinstall orrery. If it recurs, report it; that is a
defect here, not a setting on your side.

### Why the failure is worth an exit code

Every skill still loads without the corpus. Every guard still fires. The plan
ruling still runs, the gates still run, the evidence package is still written —
and the method all of them are written against is simply not in the session.
Nothing errors, nothing is red, and the only signal that anything is wrong is
that the answers are subtly the answers of a session working from memory.

That is the class of failure this doctor exists for, and the only honest report
of it is a red one.

## 0.20.0

**Minor.** `doctor`'s drift check starts running on installs where it had been
skipping since the day they were installed. If your project never wrote an
`extraKnownMarketplaces` entry into its own `.claude/settings.json`, that check
has never once told you anything — and it did not look like it was failing,
because a skip leaves the run green and the report's row reads `n/a`.

Nothing else changes.

### What you need to do

Nothing to your settings. No deny rule is withdrawn, no file leaves the product,
and no other command behaves differently.

One thing to expect on the first run after updating: if this check has been
skipping for you, it will now produce a verdict, and that verdict may be that
your cache is stale. That is not a new problem appearing — it is an old one
becoming visible.

### Where the marketplace source is read from

The drift check compares the SHA recorded when you installed against the source's
current HEAD. It is what catches a source that has moved on **without a version
bump**, which no other check here does.

To do that it has to know where your marketplace lives, and that was read from
one place:

```sh
jq -r '.extraKnownMarketplaces.orrery.source.source' \
  "$PROJECT/.claude/settings.json"
```

No entry there, no source, no check — for as long as the install existed. Claude
Code, meanwhile, records every marketplace it knows in
`~/.claude/plugins/known_marketplaces.json`, keyed by name, with a `source`
object of exactly the shape the project entry uses. The answer was usually
already on the machine.

Both files are now read, your project's entry first — a project that writes its
own entry means it, and the two can disagree. Which file answered is named in the
messages, because a source path that will not resolve is worth chasing in the
file that named it. Where neither has it, the skip says so and names both places
it looked, instead of printing the empty value it found.

### What was deliberately left alone

A skipped drift check is still a `–`, not a `✗`. A checked-out copy rather than
an installed one legitimately has no marketplace source to compare against, and
failing a project for that is how a doctor stops being run at all.

### How this surfaced

The duplicate-`installPath` defect fixed in 0.19.0 lived in a project where this
check had never run once. It was found only when somebody added the missing entry
by hand and the check ran for the first time. The finding did not come from an
insight — it came from a check finally being allowed to run, which is the whole
argument for this change.

## 0.19.0

**Minor.** `doctor` stops reporting two failures that were never true. If you ran
it on 0.18.0 and were told your install had been edited in place, or that your
cache was stale against a SHA identical to the one beside it, nothing was wrong
with your install and nothing needs reinstalling.

Minor rather than patch because two checks go from ✗ to ✓ on a healthy install,
and observable behaviour counts in either direction. Nothing else changes.

### What you need to do

Nothing to your settings. No deny rule is withdrawn, no file leaves the product,
and every other command behaves as it did.

If you reinstalled the plugin because `doctor` told you the cache was edited,
that reinstall was unnecessary and harmless.

### `.in_use` is a directory, and the exclusion was written for a file

The cache-integrity check digests every file under the install path and compares
it against the digest taken at install time. Claude Code writes its own marker
into that same directory, which moves on its own, so the digest excluded it:

```sh
find "$install_path" -type f ! -name '.in_use' …
```

`.in_use` is a directory holding one file per live session, named after the PID.
`-type f` never yields the directory itself, so the name filter had nothing to
reject and every session marker went into the digest. Opening a second session
changed the digest, and the check called it an edit:

```
✗ cache unedited: no — edited in place
```

The exclusion now matches the path as well as the name, so both shapes are
covered.

### One install path, several projects, several SHAs in one variable

The staleness check reads the SHA recorded at install time out of
`installed_plugins.json`, matching on the install path. Installing at project
scope in more than one project produces one entry *per project*, all carrying
the same path — so the query returned two SHAs joined by a newline, which can
never equal a 40-character live SHA.

The report printed the first seven characters of that value, which truncated the
second copy away and produced a mismatch against what looked like itself:

```
✗ cache is stale: cached @72e56ff (0.18.0), source is @72e56ff
```

The query now takes the first match. A single-project install was never affected,
which is why this survived: the shape that triggers it is having installed
orrery in two places.

### Both were invisible from inside the tests

The suite planted `.in_use` as a plain file — the one shape the old filter
handled — so the fixture agreed with the code instead of with a real install.
Both defects now have probes built the way the cache actually looks, and each
one goes red when its own fix is removed.

## 0.18.0

**Minor.** One file you run starts refusing something it used to pass, and the
first thing it catches is a defect this release also fixes: `plan`'s own
description was not valid YAML, and had not been for as long as anyone can date.

### What you need to do

Nothing to your settings. No deny rule is withdrawn, nothing you have merged into
your own needs removing, and no file leaves the product.

Two files change. `skills/plan/SKILL.md` is a one-line correction with no
behaviour behind it. `skills/sharpen/check-claims.sh` gains a check, which means
it can now refuse a tree that passed on 0.17.0 — only a tree you have edited
yourself, since the shipped one is clean.

### A description Claude Code reads and a parser refuses

`plan`'s frontmatter carried this:

```yaml
description: Produce a plan … including a one-line one: it prices the work …
```

A plain scalar in a YAML block mapping may not contain a colon followed by a
space. That line ends the value at `one` and leaves `it prices the work` where a
key belongs, so a strict parser refuses the entire block:

```
mapping values are not allowed in this context at line 3 column 233
```

Claude Code loaded the skill anyway. Its reader splits the line on the first
colon rather than parsing it, so the description displayed intact in every
session — which is exactly why nobody looked. `description` is the only field
read when deciding whether a skill fires, and the one place it was whole was the
place that needed it least. Anything else reading the tree got a parse error.

The fix is quotes. Nothing about what the skill does or when it fires changes.

### The reason it survived is that nothing read frontmatter as YAML

`check-claims.sh` greps a frontmatter block for the fields it cares about, one
name at a time, and never asks whether the block parses. `claude plugin validate
--strict` validates the marketplace manifest and does not descend into a skill.
Both were green on the file above, for every release it shipped in.

A twelfth check closes that: every value in a skill, agent or rule frontmatter
that is unquoted and carries a colon followed by a space is now named and
refused.

**Its ceiling is stated rather than implied.** This is one pattern, not a YAML
parser. Colon-plus-space is the rule prose trips over; tabs, stray anchors and
unbalanced quotes go unchecked, and the first one of those to land is the
argument for putting a real parser behind it. The comment above the check says
so, so the next person meets it as a decision rather than as a gap.

Agreement with a real parser was measured rather than assumed: Ruby's
`YAML.safe_load` over all 74 frontmatter blocks in the workshop returns the same
verdict — one unparseable before the fix, none after.

## 0.17.0

**Minor.** The guard starts refusing things it used to allow, the call log starts
recording something it never saw, and `build`'s retrospective stops reporting
numbers it had made up. Two of the three were invisible from the inside: a check
that cannot fire and a log that looks complete read exactly like a clean result.

### What you need to do

Nothing to your settings. No deny rule is withdrawn, and nothing you have merged
into your own needs removing.

**Two things will behave differently, both deliberately.** Commands that the
Bash guard used to allow are now refused — see below, and if one of them was
load-bearing for you, that is worth knowing before you meet it mid-task. And
`orrery:call-log` begins writing a row for every `Skill` invocation, so a log you
already keep grows a kind of line it has never held.

**One rule file leaves the product.** Under `rules/process/`, the file
`fix-it-now-if-cheap-and-adjacent.md` is replaced by
`fix-what-you-find-when-you-find-it.md`. Nothing of yours points at the old path
unless you wrote it into something by hand.

### The guard was walked past by one keystroke of casing

Two of its refusals matched paths case-sensitively while the section beside them
matched case-insensitively — the same statement, the same subject, opposite
treatment, with nothing marking the difference as deliberate:

```
  §1  home credential stores            §4  the reserved operation
  ────────────────────────────          ─────────────────────────────
  cat ~/.aws/cre*        REFUSED        …/permissions-check.sh --reconcile  REFUSED
  cat ~/.AWS/cre*        allowed        …/Permissions-Check.sh --reconcile  allowed
  cat ~/.Ssh/config      allowed        bash …/PERMISSIONS-CHECK.sh …       allowed
```

**macOS's default filesystem is case-insensitive**, so every "allowed" line above
opened exactly the file the refused line names. macOS is one of the two platforms
the guard models. Both sections now fold case, and the corpus carries the variant
spellings so the next edit cannot quietly drop them again.

### The call log never saw a skill run

Its matcher listed `Agent`, `Edit`, `Write`, `NotebookEdit` and `Bash`, and no
skill invocation was recorded anywhere — so which of this library's own skills had
ever run was unknowable, and the gap was invisible because the log looked
complete. It had already produced a false statement in a report.

`Skill` joins the matcher. The kind column carries the skill name where the tool
is `Skill` and the subagent type where it is `Agent` — the tool name in field
three says which reading applies, so a skill named `critic` and an agent typed
`critic` are never confused. The record format is unchanged: no eighth field, and
still no content of any call.

Skill invocations also stop being counted as spawns anywhere that counts.

### `build`'s retrospective was reporting numbers it had reconstructed

The totals in the retrospective comment — agents, tokens, cost — were recovered by
re-parsing the markdown the script had just rendered, with `awk -F'|'`. One pipe
character inside an agent's description shifted every column, and 140 output
tokens were reported as 0, including inside the machine-readable block. The totals
now come from the data the table was rendered from. The script has a suite, and
seven of its cases go red against the version that shipped before this one.

### Canon gained two clauses, and both are about what you are already doing

**§2, on surgical changes.** A defect is not a drive-by: something *wrong* — a
wrong answer, a check that cannot fire, a claim the code does not keep — is fixed
the moment it is found, in the change you are already making, at whatever size the
fix turns out to be. What stays deferred is code outside the repository you do not
control. Dead code is still flagged rather than deleted; it is not telling anyone
anything false.

**§7, on the owner's attention.** The prose beside a shape says only what the
shape cannot. A paragraph restating the diagram spends that attention twice on one
fact, and depth is held rather than spent — everything else waits to be asked for,
and asking is cheap.

### Three rules, two of them new to you

- **Every merge is recorded in an issue** — the pull request names it, and work
  found mid-task joins the issue already open rather than starting a new one.
  Earned from a merge that reached a default branch with nothing in the tracker
  behind it.
- **A report is a shape plus what the shape cannot say** — the practice §7 now
  states, written down because it was holding only while somebody remembered to
  ask for it.
- **Fix what you find when you find it** replaces the older, narrower rule about
  fixing what is cheap and adjacent. "Cheap and adjacent" was the test being
  applied, and it deferred a finding that produced a wrong result in its own
  subject matter. The test is *is this wrong*, not *is this small*.

### `sharpen` — a correction is not a change

Its one-item-at-a-time rule is about decisions. Where a project states something
about itself that the disk contradicts, there is nothing to decide — the fix is
what the file already says — so corrections go as one batch and the batch is one
item. Anything whose fix could reasonably be written two ways is a change, and
goes alone.

## 0.16.0

**Minor.** Mostly the library correcting what it says about itself, which sounds
like housekeeping and is not: three of the corrections were sentences a reader
would have acted on. Plus one rule that got wider, one agent that goes, and a
skill that now knows what to do when a bug only reproduces somewhere else.

### What you need to do

Nothing. No deny rule is withdrawn, and nothing you have merged into your own
settings needs removing.

**One agent type disappears.** `orrery:planner` is gone. If you have written it
into a script, a workflow or a prompt, it will stop resolving — see below for
why it never did anything you would have noticed.

### `orrery:planner` is removed, having never been spawned

`plan` was written throughout as though a planner agent ran: a node in its route
table, "its brief opens with the route", "Planner revises against the findings".
Its only spawn instruction names `critic` and `architect`. Nothing anywhere
named the type, so its model pin and its tool restrictions had never once
applied.

Two honest fixes existed. Routing to it would have added an agent to every
planned change including the route defined as spending nothing; what that buys
is a model pin on the one step whose job is to write the plan. So the role
language goes instead. `plan` drafts in the session that invoked it, and spends
agents only on reading what it wrote — which is what it was already doing.

### `verify` gained a fifth condition, and `diagnose` gained a rung

`verify` asked four things of a proving command: red-capable, deterministic,
fast, unattended. All four are properties of the command; none was about what
the command **reads**.

The fifth is **reading the real thing** — the environment, the inputs and the
state it touches are the ones the claim is about — and it arrives with the
corollary that catches people out: *deterministic has no environment
coordinate*. A command green on every run here and red on every run there
satisfies determinism on both machines. Two machines disagreeing is not
flakiness, and a retry is the wrong reflex.

`diagnose` imports those conditions, and that is why "fails on CI, passes
locally" had no path through it: all six rungs of its ladder run where you are,
so that class walks the whole ladder without going red — and the skill then
asked which rung you landed on while forbidding you to open a file. It now has a
seventh rung, where the reproduction is the difference between the two
environments and the loop runs on the side that is red.

### One rule got wider, one is new to you

The rule about running gates where nobody works now covers both conditions a
suite most often lies about: the **machine** it ran on, and the **size** of what
it was handed. It absorbed a second rule rather than sitting beside it — case
coverage, environment coverage and scale coverage are three axes, and being
complete in the first proves nothing about the other two.

`learn` also stops claiming that every rule in the set was earned from an
incident. Most were. A few are declared policy — about a harm nobody wants to
meet even once, like licensing — and they carry `evidence:` naming the risk
rather than an incident. The difference decides how a rule loses an argument: an
earned rule wins on what it cost, a declared one only on the risk it names.

### Skills that seem to both fire

The index now says which one wins: **the one that names the other**. Where
neither does, take the one whose description names what you actually asked for
rather than the one with the wider scope — a skill claiming *any change* or
*anything* is stating what it charges, not staking a claim on the work.
`pare` and `verify` gained the clauses they were missing, and `diagnose` now
says that fixing a local, obvious bug on the spot **is** planning's cheapest
route rather than a skipped step.

## 0.15.0

**Minor.** Four rules you did not have before. Nothing else changes: no skill,
no hook, no agent, no deny rule.

No deny rule is withdrawn by this release. Nothing you have merged into your own
settings needs removing.

### Four more rules, all about tooling rather than about us

Rules load by scope, so these cost you nothing until a call enters `craft` — at
which point one line each arrives with the rest. All four had been earning their
keep in the workshop and were never shipped, which is a gap in what was
promoted rather than a judgement that they were too local.

**`gates-must-run-where-nobody-works`** — a suite that has only ever executed on
developers' machines has been passing against what those machines accumulated.
The incident behind it: a check resolved a path against the filesystem, that
path always exists where the tool has run, and the case was green in every
pre-commit and red the first time it ran anywhere clean — after shipping twice.

**`make-the-tool-say-why-before-deciding-why`** — read a refusal before theorising
about it, and probe the path that actually failed rather than the one that is
easy to type at a prompt. Four wrong conclusions about one sandbox came out of
skipping both halves.

**`name-the-members-never-the-count`** — a count in prose decays on its own, and
the dangerous form is the one spelled as a word, because a checker that catches
`[0-9]+ skills` does not catch "the four phases". A stale digit is an error; a
stale word is an error wearing a passing test.

**`state-owned-elsewhere-is-fetched-before-it-is-read`** — a local mirror answers
the right question with full confidence whether or not it was refreshed, and
every local reading agrees with every other because they descend from one
snapshot. Cross-checking locally raises confidence while proving nothing.

### Why this is a minor and not a patch

A rule that loads is behaviour you can observe. Four of them arrive in sessions
that touch `craft` work, and they will argue with choices you would otherwise
have made — which is the point, and is worth knowing before you update rather
than after.

## 0.14.0

**Minor.** Two fixes, and one of them changes what the Bash guard refuses. A
command that *starts* being refused counts the same way a withdrawn refusal would,
so it is named below with what does and does not change.

No deny rule is withdrawn by this release. Nothing you have merged into your own
settings needs removing.

### The Bash guard reads past `source`

The guard strips wrappers before judging a command, so `sudo`, `env`, `xargs`,
`bash -c` and a container `exec` all reveal what they actually run. `source` was
not on that list, and `.` never needed to be — it has no letter in it, so the
guard's "punctuation is not a command" line already dropped it.

So the two spellings of one shell builtin got different answers, and the letters
one won: anything sourced was judged on the word `source` rather than on the
script it runs, and every rule that decides at the verb stopped there.

**What starts being refused:** the sourced spelling of the one command this guard
reserves for you — the reconcile mode of the deny-list check, which records every
missing rule as one you declined on purpose. The other spelling was already
refused. A nonsense form like `source rm -rf ~/dev` is now read as `rm` and
refused too.

**What does not change:** sourcing an rc file, a virtualenv activation or a shell
library, and the read-only modes of the same check. Measured against the previous
guard over every `source`-led shape worth trying: three verdicts move and all
three tighten, none loosen.

### `sharpen`'s claim checker explains a mismatch under a sandbox

When the plugin manifest and `skills/` disagree, the checker printed the
difference with process substitution. Under the platform sandbox an external tool
cannot open the descriptors that hands it, so the *explanation* of a real failure
failed with `Operation not permitted` — and what you read was an error rather than
a difference.

The verdict never depended on it. Only the explanation did, and now it survives
the sandbox, which is the ordinary way you would run this from a session.

## 0.13.0

**Minor.** Behaviour you can observe changes in four places, and one of them is a
bug fix worth updating for on its own: with the call log enabled, a relative log
path used to create a new log in every directory a session worked in.

### What you need to do

**If you enabled `ORRERY_CALL_LOG` before this release, look for strays.** The
path was resolved against the working directory of each tool call, so every
change of directory started another log. A `.gitignore` line is anchored to the
directory holding it, so the copies were not ignored and could be committed.

```bash
find . -name orrery-calls.tsv -not -path ./.claude/'*'      # look first
git ls-files '*orrery-calls.tsv'                            # any that got committed
```

They hold no content — a hashed session id, tool names and timestamps — so
removing them is tidying rather than a security step. Nothing new appears after
updating.

No deny rule is withdrawn by this release. Nothing you have merged into your own
settings needs removing.

### The call log records outcomes, not just intent

It used to write one line when a tool call was *proposed*. A call refused by a
guard, by the permission system or by you looked exactly like one that ran.

Now a successful call writes two lines — `call` and `ran` — under one
`tool_use_id`, and a call that was stopped writes only the first. Reading the
pair tells you what happened; the absence needs no list of the ways a call can
be stopped, so no way of being stopped is missed.

What it cannot tell you: refused, errored and interrupted are one number. An
unpaired line means "did not complete", never "was refused".

**Cost, stated plainly:** one extra hook invocation per successful tool call.
The log has seven fields now instead of five, appended, so anything reading the
first five still works — but anything *counting rows* now counts double, and
should filter to `call` lines. `orrery:report` already does.

### `orrery:doctor` reports the platform sandbox

The defence has five layers and installing this plugin gives you three. Layers 4
and 5 are a `sandbox` block in `settings.json`, and a plugin cannot write that
file — the same reason it never merges the deny list for you.

That was true before and nothing said so. The doctor now reports the sandbox as
on, off, or absent, and **fails the run for none of them**: whether to sandbox is
your decision. The install guide gained the block to paste and an honest account
of what it costs day to day.

### The deny-list drift report is ranked

When rules are missing from your settings, they were listed flat, in whatever
order they happened to be in. A list opening with thirty enumerated `git
checkout` path variants buries the three that let a credential be printed.

Grouped by class now — credentials, the session's own control plane,
irreversible data loss, then everything else — and the one line a session shows
names the worst class present and how many are in it.

### Reports arrive with a shape

Canon §7 said what reaches you and never in what form. It now asks for a table,
a list or a diagram before prose, in both directions: what an agent reports to
you, and what it asks a subagent to return.

### `sharpen` counts from a stated denominator

Two corrections to the skill that reads your history for patterns. It now reads
every transcript, or says how many it read — a pass that quietly took the newest
few produced counts low by a factor of three. And a candidate is not promoted to
a finding until the other side of the conversation is checked: a complaint is
what you perceived, not proof of what the agent did.

## 0.12.1

Nothing changes for a project that installs this plugin. The release exists so
that the next one can be made by merging a pull request instead of running a
command.

### What you need to do

Nothing. No skill, hook, rule or deny rule moved, and no behaviour in a session
is different. Update at your convenience or wait for the next release that
carries something for you.

### What is in it

One file: `.github/workflows/release.yml`. It fires when a release pull request
is merged here, reads the version out of the branch name, refuses unless the
manifest agrees with it and the release notes exist, then tags the merge commit
and publishes those notes as the page.

It matters because the last step of publishing used to be a command somebody had
to remember to run, on a machine, after the merge. A tag that nobody applies is a
release consumers never see — and the gap between "merged" and "tagged" is
exactly where that is easy to forget.

## 0.12.0

### What you need to do

Nothing, unless this release or an earlier one added a deny rule you have not
merged. `hooks/permissions.json` is copied into your project's
`.claude/settings.json` by hand at install, and nothing has ever told you when
that copy fell behind. From this release something does: one line at session
start, and only when the answer changes — merge the rules and it stops; change
nothing and it stays quiet until the answer is different. `orrery:doctor` lists
exactly which rules are missing, and prints the `--reconcile` command with its
path already filled in. If you declined some on purpose, record that once with
that command; it writes `.claude/orrery-deny.json` in your
repository, so the decision is committed, reviewable, and true for everyone on
the team rather than for one laptop.

The match is by exact rule text. If you narrowed a rule rather than copying it —
`Read(/Users/someone/**/*.key)` for our `Read(**/*.key)` — it reads as missing,
and `--reconcile` is the right answer.

Worth checking now even if you have never seen the message: release 0.10.8 moved
nine classes of rule out of the Bash guard and into the deny-list — `git
checkout .` in all its spellings, `gh auth token`, `~/.claude/**`, `**/*.key`,
`~/.config/gh`, `~/.config/gcloud`, `~/.azure`, `/boot`, `/lib`. If your copy
predates that release, the guard stopped refusing them and nothing took over.

### Why it took a release to notice

An install was found sitting 28 rules behind the shipped deny-list, more than a
month after the release that added them, with every check in `orrery:doctor`
green. The missing ones were exactly the rules that release had handed over from
the Bash guard: the guard was shrunk *because* the deny-list had picked them up,
and in the plugin it had — in a settings file nobody re-merged, it had not. No
part of the system was in a position to say so, because nothing had ever
compared the two lists.

### The check

`hooks/permissions-check.sh`, a `SessionStart` hook with the `startup` matcher:
once when a session begins, and not again on `/clear` or a resume.

It compares as a **subset**. Rules you hold that this plugin does not ship are
never mentioned and never counted, and the `allow` block is not compared at all —
those rules name this plugin's own scripts by path and are none of your
project's business. It reads your project settings, your project-local settings,
your own user settings and any managed policy, so a rule you keep at user scope
counts as merged.

**It never writes a settings file, at any scope.** The finding is emitted as a
`systemMessage`, which reaches you and not the model, so nothing here can decide
to widen your permissions on your behalf. The one file it writes is the decline
record, and only when you type `--reconcile`.

**A comparison that could not be made is said out loud.** No `jq`, a settings
file that will not parse, a shipped list that cannot be read: each of those
prints what happened rather than nothing. Silence would read as all-clear, and
that reading is the whole of the failure above.

Its suite ships beside it — 36 cases, run by the same gate that runs the other
hook suites.

### `orrery:doctor` gained a seventh check

It calls `--report` rather than repeating the comparison, so there is one
implementation and one answer. Three outcomes are kept apart: **current**,
**behind** — the missing rules printed underneath, and below them the
`--reconcile` command with the plugin root resolved, because that path moves on
every update and no document can carry it — and **could not be compared**, which
is not a drift finding and says so in those words. `--report`
prints how many rules you have on record as declined on every run, clean ones
included, so a `--reconcile` typed in error cannot become invisible.

### The install page says the merge recurs

`install/into-project.md` told you to merge the deny-list once, at install. It
now says the part that was missing: every release that adds a rule adds it to the
file you copied by hand, so this is a step that comes back rather than one you
finish. It also documents `--reconcile`, why that record belongs in the
repository rather than on one machine, and why nothing here merges the list for
you.

Pre-1.0: skill names and layout may still move between releases. `jq` must be on
`PATH` before any hook fires — without it this check reports that it could not
run, which is the one thing it must never do silently.

## 0.11.0

Four ways past the Bash guard, closed. Three commands it refused that it should
never have refused. And a doctor that can tell an edited install from a fresh
one.

This is a minor rather than a patch because commands change answer in both
directions. If you have scripts or habits built on either, read the two lists.

### Commands the guard now refuses

Each of these walked past every rule in the guard, not merely the deletion rule.

- **`\rm -rf ~/dev`** — and `'rm'`, `"rm"`, `r""m`, `rm${IFS}-rf`. The guard
  compared the raw token while the shell removes quoting before deciding what to
  run. A backslash is what people type to step around an `rm -i` alias, so the
  delete boundary was one keystroke deep.
- **`docker exec <container> rm -rf ~/dev`** — and the `podman`, `nerdctl`,
  `kubectl exec` and `docker compose exec` spellings. A container runner is a
  wrapper like `sudo`, with one extra word to step over.
- **`pnpm exec rm -rf ~/dev`** — and `yarn exec`, `npm exec --`. Same wrapper
  shape, different family.
- **`npx -c "rm -rf ~/dev"`** — inline shell, exactly like `sh -c`.
- **A command carrying more than about a hundred segments.** The guard costs
  three processes per segment, and past that it could not finish inside its own
  timeout — where it is killed rather than refusing, so every rule stopped
  applying. It now refuses and says how to split the command.

### Commands the guard no longer refuses

- **A multi-line quoted argument containing a command.** A commit message with a
  command in its body, an issue body quoting a shell line, any tool handed a
  multi-line string. The guard separated segments with a newline and read them
  back a line at a time, so a newline *inside* a quoted argument split it into
  imaginary commands.
- **Prose naming a destructive SQL statement.** `git commit -m "docs: why DROP
  TABLE is denied"` and `grep -rn "DROP TABLE"` were refused. The rule now
  requires a database client at the head of the segment, which is the shape the
  git rules already use.
- Both directions are pinned by cases, including what the second one gives up:
  `echo "..." | psql` and `cat schema.sql | psql` reach a database and are not
  seen, because the client and the statement are in different segments.

### What the guard still does not cover, stated rather than implied

`docker run` with a bind mount. The container path would have to be mapped back
to the host path to mean anything, and an image can delete on start with no
command in the line at all. The guard's header now says the part that makes this
matter: **behind a container there is no second layer** — the sandbox confines
the process running `docker`, and `docker` hands work to a daemon outside that
confinement. Two `allow` cases in the corpus keep this a claim rather than a
silence.

### The doctor sees an edited install

`orrery:doctor` compared the recorded commit sha of your installed cache against
the source. That answers whether a different revision was installed; it cannot
answer whether a file inside the install was edited afterwards — the recorded
sha does not move when that happens. A content digest now answers the second
question. The baseline is trust-on-first-use, so an edit made before the check
first ran on your machine is recorded as the baseline; every edit after that is
reported.

Its state directory moves from `~/.claude/orrery-doctor-log/` to
`~/.claude/orrery/doctor/`, carrying existing history on the first run.

### The call log cannot be forged

With `ORRERY_CALL_LOG` set, one tool call could write two lines: a newline in a
field the caller controls ended the record early and began another, with a
chosen timestamp and a chosen session fingerprint. The log exists because a
session that ignores its instructions cannot be trusted to report that it did,
so a session that can also write into it leaves nothing worth reading. One call
now writes one line.

### A self-check that printed a failure and exited zero

`skills/sharpen/check-claims.sh` looks for a `hooks` key in `plugin.json`
duplicating the auto-discovered `hooks/hooks.json` — the shape that makes every
install fail to load with "Duplicate hooks file detected", and which
`claude plugin validate --strict` passes.

It found that shape, printed a red line, and exited 0 anyway: it called the
function that prints without the one that moves the failure counter. So the one
check covering a defect that breaks every install was green in any hook or CI
job reading the exit code. Fixed, and covered by a mutation suite.

The same file now also reads *every* version-shaped string in the README rather
than the first one. The version badge on this page had been two releases behind
while the check reported the version consistent, because it matched the prose
form in the footer and never the badge.

### Recording tool calls needs a gitignore line

`install/into-project.md` told you how to switch the call log on and never
mentioned that its path has to be ignored. The file grows by a line on every
tool call and is trimmed from the head at its cap, so committing it puts a
conflict in front of everyone who runs a session in your repository — and the
hashed session id it carries tells a second reader nothing. The instruction now
says so in the same place it tells you to enable it.

### Windows

Still unsupported, and the README now says support is planned and names the
three specific obstacles rather than leaving you to find out at the first
command.

---

Version 0.10.9 was prepared and cancelled before it shipped; everything it
described is in this release.

## 0.10.8

A loader that stopped loading, two guards that now have tests, and a smaller
guard with a larger deny list behind it.

### One malformed rule file silenced a whole scope

`hooks/rules-loader.sh` closed its frontmatter reader with `next` inside an awk
`END` block. That is illegal there: awk exits non-zero instead of skipping the
file, `set -e` takes the loader down with it, and every rule in that scope stops
arriving — not just the one that was malformed.

Nothing reported it. A loader that emits nothing looks exactly like a scope with
no applicable rules, so the failure was a session quietly working without the
layer it was supposed to be carrying.

Fixed, and pinned by the suite that found it.

### Every hook that runs in your session now has a test

Four of them had none: the Agent guard, the two loaders and the compaction
prompt. The Agent guard runs before every subagent spawn and had a single
assertion — that it refuses when it cannot parse its own input — while three
documents said it had a corpus.

Each now has one, beside the file it tests, and the two guards have a mutation
pass that proves the corpus still pins the code rather than merely running next
to it. `hooks/guard-test-lib.sh` holds the loops both guard suites use; what
each states for itself is the payload shape, the fail-closed probes and which of
its own lines are decisions worth mutating.

The Agent guard's accepted limit is now written as a case rather than left to be
rediscovered: a brief that mentions `SendMessage` without meaning it passes, and
no grep can tell the two apart.

### The Bash guard is smaller, and the platform carries the rest

The section that reasoned about system trees is gone — it was the largest thing
in the file, and it defended by matching strings against a list of readers,
which is the layer that keeps failing across every harness surveyed. The deny
rules take that over: file reads and edits are matched by Claude Code itself,
which the guard cannot be talked around.

The destructive git verbs went the same way. The guard now refuses only their
global-option form, because the deny list already carries the plain ones — and a
check now fails if a rule the corpus defers to has been dropped from
`hooks/permissions.json`, so that hand-off cannot rot into a comment.

What stays in the guard is what no other layer does: deletion outside the
session scratchpad, and access to credential stores and machine config from
inline interpreters. Those two sections carry a note saying why they are not the
duplication they look like where a sandbox is switched on.

`hooks/permissions.json` grows to 121 deny rules and gains an `allow` block.
That block is Orrery's own gate scripts by path — in your project those rules
match nothing, and `install/into-project.md` now says so rather than leaving you
to merge a list that does nothing for you.

### Hook matchers are anchored

`Agent|Task|Edit|Write|NotebookEdit|Bash` matched any tool name containing one
of those words, not the tool itself. They are anchored now, `Task` is gone, and
the two guard timeouts are raised to fit the work they actually do.

### The shipped bytes stopped carrying workshop provenance

Files that ship verbatim were carrying tracker references and dated incident
narratives — a pointer to an issue in a repository you cannot open. The incident
stays, since a guard's comments are where the reason for each line lives; the
date and the number are gone, and the publication scan now refuses both classes.

### One rule retired

`arm-auto-merge-only-when-told` required an explicit instruction before arming
auto-merge. Where the standing instruction is the opposite, the rule fires
against the person whose incident produced it. Retired rather than inverted, and
its two cross-references go with it.

Pre-1.0: skill names and layout may still move between releases. `jq` must be
on `PATH` before any hook fires.

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
