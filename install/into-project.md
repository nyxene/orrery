# Installing Orrery into a project

```bash
/plugin marketplace add nyxene/orrery
/plugin install orrery@orrery
```

Skills become available as `orrery:frame`, `orrery:plan`, `orrery:build`,
`orrery:review`, `orrery:diagnose`, `orrery:pare`, `orrery:verify`,
`orrery:debt`, `orrery:doctor`, `orrery:feedback`, `orrery:handoff`,
`orrery:learn`,
`orrery:sharpen`. Agents (`architect`, `critic`, `auditor`) resolve
by name. All eight hooks start firing immediately — including the one that stops
the first compaction of a session to ask whether there is unfinished work to
hand off.

Every hook needs **`jq`** on `PATH`. Install it before the plugin or nothing
will work. Each hook fails in the direction that is safe for what it does: the
Bash and agent guards deny everything rather than let one call through
unchecked, the process gate lets it through, the loaders
announce that they could not run, and the handoff prompt stands aside rather
than strand a session.

`orrery:handoff` writes `.orrery/work/<work>/handoff.md` in the work's own tree,
so it needs no tracker.

## Updates arrive only once you switch them on

Claude Code updates plugins in the background only from Anthropic's own
marketplace. For every other one, this one included, auto-update is **off** by
default, so an install stays on the version it was installed at until someone
updates it by hand. Switch it on once per machine:

In any session: `/plugin` → Marketplaces → `orrery` → Enable auto-update.

A new version is then fetched in the background and loads on the next launch of
Claude Code, in every project where the plugin is installed at user scope. To
update by hand instead, after each release:

```bash
claude plugin marketplace update orrery
claude plugin update orrery@orrery --scope user
```

## What the project declares

Everything of Orrery's in a project lives in `.orrery/`, and nothing of it in a
folder that is not its own:

```
.orrery/
  config.json      the project's settings — committed; written by a person, never the model
  deny-declined.json  deny rules a person declined on purpose — committed
  local/           this machine's files, never committed: call log, waivers, gate state,
                   doctor's log, session markers. Carries its own `.gitignore`
  work/<work>/     a piece of work's record, handoff and plan — committed with the work
  work/debt/       the debt register, where there is no tracker
  sharpen-log.md   what each `sharpen` pass proposed and decided — committed
```

`<work>` is the worktree's name, or the branch on the main checkout. Outside
`.orrery/` only what the platform requires: the plugin cache, the deny rules in
your settings, and — on GitHub — the workflow below and the issue a merge closes.

**Without a tracker** you get the method and its checks; what a tracker gives is
stated rather than imitated, and is missing: issues containing their work, a
release container, closure by merge, links between items, and a gate for a change
pushed straight to the default branch.

Orrery holds the skills and guards. The project holds its own facts, in
`.orrery/config.json`, and every session is handed them at its start:

```json
{
  "tracker": "github",
  "outputLanguage": "English",
  "qualityGates": "npm test, npm run lint"
}
```

| Key | What | Used by | If missing |
|---|---|---|---|
| `tracker` | `"github"`, or leave it out for none | every skill and guard that asks a tracker | No tracker: records, handoffs and debt are files, and a branch's first push is the gated act |
| `callLog` | `false` to switch the call log off | the recorder, the audit gate | On |
| `outputLanguage` | the terminal conversation's language | Canon §8, `build` | Everything stays English |
| `planDirectory` | where plans go | `plan`, `build` | `.orrery/work/<work>/plan.md` |
| `debtLabels` | `type`, `scope`, `priority`, `pool` — the labels in the tracker's own spelling | `debt` | Its queries match nothing, and an empty pool is indistinguishable from a clean one |
| `debtQuota` | how many debt items a feature task also closes | `debt`, `build` | No quota; the skill tracks and reports only |
| `qualityGates` | the commands that prove the work | `build`, Canon §3 | The agent has no proving command to run |
| `branchFlow` | how a change reaches the default branch | `build` | Branch-from-default, PR, squash |
| `sharpenLog` | where `sharpen` keeps its log | `sharpen` | `.orrery/sharpen-log.md`, created on first use; one at the old `docs/sharpen-log.md` is moved there |
| `incidentInbox` | `<owner>/<repo>` — see below | `learn` | Rules stay local, which is the correct default |

**You write it, by hand.** The deny-list below carries `Edit(**/.orrery/config.json)`,
so a session cannot edit it — a setting that switches a gate off is a change a
person makes in a reviewed commit. A missing file beside a GitHub remote, or one
that does not parse, is said at the start of every session and by `doctor`.
Declarations that used to live in a table in your `CLAUDE.md` move here; that file
stays yours, for what Orrery does not read.

## The call log

`hooks/call-log.sh` appends a line per tool event to `.orrery/local/calls.tsv`
in the main checkout: a timestamp, a fingerprint of the session, the tool name,
the subagent type where there is one, whether the spawn was named, the event —
`call` or `ran` — and the harness's id for that call. **It is on by default,**
because the audit gate before a pull request reads it (below). It stays on this
machine: nothing in it is sent anywhere.

**Two lines per completed call, one per call that was stopped.** `ran` is
written only when a tool succeeds, so a `call` with no `ran` under the same id
did not run, whatever stopped it — a guard, the permission system, or you
answering no. What it cannot tell you is *which* of refused, errored and
interrupted a given unpaired line was.

Never the command, the prompt, the file path, the branch or the agent's name.
The session id is hashed rather than stored, so a line correlates with its
neighbours and identifies nothing beyond the machine that wrote it.

**Nothing to ignore.** `.orrery/local/` carries its own `.gitignore`, written by
Orrery before the first line lands, so nothing in it reaches a commit and your
own `.gitignore` is never edited. The path comes from git — the main checkout,
whichever worktree or subdirectory a call runs in — so there is one log per
clone. Outside a git repository nothing is recorded.

**To switch it off,** declare `"callLog": false` in `.orrery/config.json`. That
also switches off the audit gate, which has nothing else to read.

**Upgrading from a version that used `ORRERY_CALL_LOG`:** the first line written
copies the old log's rows across, once, and leaves the old file where it was, so
a rollback still finds it. The variable now only names that old file; remove it
from your settings once the new log exists. Strays from versions before 0.13.0,
when the hook resolved a relative path against the working directory, are still
yours to remove:

```bash
find . -name orrery-calls.tsv -not -path ./.claude/'*'      # look first
git ls-files '*orrery-calls.tsv'                            # any that got committed
```

The log is capped — 256 KB by default, `ORRERY_CALL_LOG_MAX` to change it — and
`hooks/call-log.sh --purge` empties it.

**What it is for.** `sharpen` reads it, and the shape of a session shows
there in a way it does not anywhere else: how often a checker actually ran,
whether anything was executed before one was hired, how many agents a piece of
work cost. A skill cannot report the run in which it ignored its own
instructions — the same omission removes the behaviour and the record of it — so
the recorder sits outside the skills.

Nothing is transmitted. It is a file on your disk. If you send a friction report
and choose to attach it, that is a file you attach, having read it.

## The rules layer, and where your lessons live

`CANON.md` enters every session through the `SessionStart` hook. `rules/`
loads **by scope, on entry**, through the `PreToolUse` hook — spawning an agent
brings in `rules/agents/`, editing a file brings in `rules/craft/`, a `git` or
`gh` command brings in its own. Once per scope per session; what arrives is
each rule's sentence and its evidence line, with the full text one `Read` away.

The loader reads **two layers with the same weight**: the rules this plugin
ships, and this project's own `.claude/rules/<scope>/` — which is where
`orrery:learn` files the lessons your incidents earn. Local rules live in your
repository, survive every plugin update, and never leave: **nothing is
transmitted anywhere, ever**. The only thing this plugin writes about your usage
is the call log described above, which stays on your disk and is switched off
with `"callLog": false`. The one exception is opt-in and mechanical: a project
that declares `"incidentInbox": "<owner>/<repo>"` in `.orrery/config.json` — and
whose `gh` can reach that repository — asks `learn` to also file each incident
there. No declaration, or no access, means no attempt.

There is no `domain` scope in the shipped rules, and adding one would be a
mistake: a rule about a host project's subject matter belongs in that project's
local layer, not in a library that installs into all of them.

## Merge the deny-list

`hooks/permissions.json` holds 122 deny rules — system paths, secret files,
destructive git. Merge its `permissions.deny` array into the project's
`.claude/settings.json`. It is additive and safe to apply to any repository.

**Only that array.** The same file also carries an `allow` block, and it is not
yours: it names Orrery's own gate scripts by path, so in your project those
rules match nothing. Your allow list is your own quality gates, written the same
way.

There are no `Write(...)` rules in it, and adding one back does nothing: file
permission checks are matched by `Edit(...)` alone, which covers every
file-editing tool including `Write`. Claude Code says so on every config run,
once per rule.

**0.32.0 adds `Edit(**/.orrery/config.json)`**, the rule that keeps a session
from editing the settings file. Merge again to get it.

**Then merge it again after an update.** This is not a step you finish. Every
release that adds a deny rule adds it to the file you copied by hand — the plugin
updates once auto-update is on (see above), your copy does not. Your install
can sit a release or more behind the shipped list with every health check
green, and the rules likeliest to be
missing are the ones a release moved here out of the Bash guard, which was shrunk
because this list had picked them up. It had, in the plugin. In a settings file
nobody re-merged, it had not.

**How you hear about it.** One line at session start, and only when the answer
changes: the first startup after a rule goes missing tells you, and you are not
told again until the finding is different. Merge the rules and it stops. Change
nothing and it stays quiet — a signal, not a nag. The line gives you a count;
`orrery:doctor` prints the rules themselves. Anything you already have at user or
managed scope counts as merged: the check reads your project's two settings
files, your own user settings and any managed policy — not just the project one.

**If you diverged on purpose.** You may have narrowed one of these rules, or
decided one does not apply to you. Say so once:

```bash
<plugin root>/hooks/permissions-check.sh --reconcile <project>
```

That root is a version-pinned cache directory that moves every time the plugin
updates, so a copy you keep in a note goes stale — `orrery:doctor` prints the
command with the path already resolved, and that is the one to run.

Running it states that you read the missing rules and declined them, which is why
nothing runs it for you. It writes `<project>/.orrery/deny-declined.json` with the
set that was missing at that moment, and those rules stop appearing — in the
startup line and in the doctor's list alike. **Commit that file.** It is your
team's decision rather than your laptop's: committed, it holds for everyone in
the repository and it turns up in a pull request where someone can push back on
it, which is the only review a deliberately widened gap gets. To un-decline a
rule, edit the file and commit that. If you would rather keep the decision to
your own machine, add the path to your `.gitignore` in the same edit — Orrery
never edits that file, so nothing else will.

**Why we do not merge it for you.** `.claude/settings.json` carries every deny
decision in your project, and a plugin that edits it is a plugin that can quietly
widen what it is allowed to do. So this check reads that file and never writes
it, and no skill here will merge on your behalf. `deny-declined.json` is the only
file it writes, and it is a different kind of thing: no permission rules, no
grants, read by this check alone, and written only when you type the command
above.

**The comparison is by exact rule text.** A rule you narrowed —
`Read(/Users/someone/**/*.key)` where we ship `Read(**/*.key)` — or re-spelled —
`Bash(git checkout:*)` for our `Bash(git checkout .)` — is reported missing even
though you have it in effect. That is deliberate, not an oversight: telling those
two apart means reimplementing Claude Code's own permission matcher and keeping
it in step with it, a second copy of the thing being defended that would be wrong
without saying so. Use `--reconcile` instead — one command, and the difference is
on the record as your decision.

## Optional: switch on the sandbox

Everything above is enforced by hooks and by the deny-list — both of them
in-process, both of them things that can be wrong. Underneath there is one more
layer, and **installing this plugin does not give it to you.**

It is a `sandbox` block in `.claude/settings.json`, and a plugin cannot write
that file, for the same reason it never merges the deny-list on your behalf. So
it does not arrive, and nothing about a healthy install says otherwise.
`orrery:doctor` reports whether the block is present; it does not fail the run,
because whether to sandbox is your decision and not this plugin's.

What it buys: the platform confines every shell command to your project
directory and to a named set of domains, at the kernel rather than in a hook.
It is the only layer that still holds when a hook is wrong. Paste it beside
`permissions`:

```json
"sandbox": {
  "enabled": true,
  "failIfUnavailable": true,
  "allowUnsandboxedCommands": true,
  "excludedCommands": [],
  "filesystem": { "allowRead": ["/bin", "/usr", "/etc", "/private/etc", "/var/db", "/lib"] },
  "network": { "allowedDomains": ["github.com", "api.github.com"] }
}
```

Three of those are the argument rather than the configuration.
`failIfUnavailable` makes a sandbox that cannot start refuse rather than pass
through silently. `allowUnsandboxedCommands` sends a command that cannot run
sandboxed to the permission flow instead of refusing it outright, and that is
what lets `excludedCommands` stay **empty** — which it should. An exclusion
lifts the sandbox for the whole Bash call, so anything sharing a line with an
excluded command escapes with it. Keep the escape hatch a decision per call
rather than a name on a list.

**What it costs, so that none of it reads as breakage.** Writes outside the
project come back `Operation not permitted` from the kernel rather than from a
hook. Anything that writes `.claude/settings.json` has to be run from a terminal
rather than from a session. `gh` does not work inside the sandbox at all — it
cannot verify TLS there and cannot reach its keyring — so it goes through the
permission flow every time, deliberately. In-process tools are unaffected, so
reading documentation and searching the web work normally.

**What this block does *not* buy is egress confinement.** `allowedDomains` in a
project settings file **pre-allows**: it removes the prompt for the hosts you
list. It cannot deny the ones you did not — an unlisted domain is asked about
rather than refused, and in auto mode that question goes to the classifier.
Denial needs `network.strictAllowlist`, which the platform reads only from user
settings, managed settings, or `--settings` on the command line, and ignores
from this file.

Measured rather than inferred: with this exact block in place, `curl` to two
domains outside the list returned `200` and `401` — both connections completed.
So what you switch on here is **layer 4**, the filesystem half, plus a list that
removes prompts.

Two of those three sources are machine-wide. User and managed settings govern
**every project you have**, so switching strict egress on for this one would
tighten the rest, and you would meet that somewhere else with nothing to connect
it to a plugin you installed here. This guide does not hand you that line.

**The third is per project, and it works.** `--settings` takes a file and binds
the session it starts. Put the strict block somewhere in the repository:

```json
{ "sandbox": { "enabled": true, "failIfUnavailable": true,
    "allowUnsandboxedCommands": false, "excludedCommands": [],
    "network": { "strictAllowlist": true,
                 "allowedDomains": ["github.com", "api.github.com"] } } }
```

and start work with `claude --settings .claude/strict-sandbox.json`. Needs
Claude Code **2.1.219 or newer** — older than that, `strictAllowlist` parses,
sits in the file and denies nothing, which looks exactly like the state it is
meant to prevent.

Measured rather than argued, by running the same two requests with the file and
without it. Listed host `200` both times; unlisted host `200` without and **no
connection at all** with. That difference is the whole evidence — a single
reading could not tell "the setting did nothing" from "it worked and the request
was approved anyway".

**`allowUnsandboxedCommands` is `false` here and `true` in the block above, and
that is the difference between the two files rather than an oversight.** With
`true`, a command the sandbox refuses is offered to the permission flow and can
be retried outside the sandbox — and in auto mode that offer goes to the
classifier rather than to you, so the egress you just denied can happen anyway
one decision later. That is a reasonable trade for the everyday block. It is not
one for a file whose whole purpose is the deny, and it is not what was measured:
the probe set `false` deliberately, because an escape hatch answers a different
question than the one being asked.

**What `false` costs, said plainly.** With the everyday block above,
`allowUnsandboxedCommands: true` sends a command the sandbox cannot run to the
permission flow — which is how `gh` works at all under Seatbelt, since it fails
TLS verification there. Under this strict file there is no such offer: those
commands simply fail. `gh` is the one you meet first, and it is not alone —
process substitution (`diff <(…) <(…)`) is refused because `/dev/fd` is,
`mktemp -d` without a template lands outside the writable scope, writing
`.claude/settings.json` is refused outright, and `git checkout` and `git stash`
fail partway on paths the platform protects. Under the everyday block each of
those is recoverable through the retry; under this one they are dead ends, and
a dead end is what sends a reader looking for an exclusion. That is the trade a file
whose purpose is the deny has to make, and it is why this is a second file you
launch into rather than a replacement for the first.

**And a strict file cannot subtract, which is the part to read twice.** Array
keys *merge* across every scope a session loads; they do not override. Measured,
as a third run of the same probe with a third host in it: a domain added to the
project's own `.claude/settings.json` and to nothing else was reachable from the
strict session, and a host listed nowhere was refused by the proxy in the same
run — `200` beside `000/403/56`. The project entry joined the strict list and
the strict list held. Two consequences follow, and neither is visible from
inside the strict file:

- `excludedCommands: []` here enforces nothing. An exclusion set anywhere else
  rides into the strict session, and an excluded command lifts the sandbox for
  the whole Bash call — which under `allowUnsandboxedCommands: false` is the one
  full escape left. The platform's own troubleshooting steers a reader whose
  `gh` or `docker` "simply fails" toward exactly that entry, so the pressure to
  add one arrives precisely here.
- The effective allowlist is the union of every scope's `allowedDomains` *plus*
  every `WebFetch(domain:…)` allow rule the session loads, including one saved
  by a past "don't ask again". The two domains in the file are a floor, not the
  session's reach.

The merge rule behind the first is measured for `allowedDomains`; the
`excludedCommands` case follows from that rule and was not probed separately,
and this guide says so rather than letting one measurement stand for two. The second is a separately documented fact — the
allowlist is `allowedDomains` plus `WebFetch` allow rules — and is not measured
here at all. Either way the file is a floor, not a ceiling: audit what the other
scopes carry before trusting it.

**Its ceiling, which travels with the recipe.** It binds *that session*. Every
other session started in the same directory the ordinary way has egress open,
and nothing on screen distinguishes the two. A control that holds only while
someone remembers is the failure this library names in three of its own files,
so treat the flag as the mechanism and not as the habit: a shell function that
adds `--settings` when the file is present costs a few lines in your profile and
is inert in every repository that does not have one.

Add the domains your own work needs. The two above are a starting point, not a
recommendation about your project.

## A pull request needs the work's record, and an auditor before it

`hooks/process-guard.sh` refuses `gh pr create` until two things hold. In a
project whose `.orrery/config.json` declares no tracker, the act is instead a
branch's **first push** — no remote-tracking ref for it yet, a URL for a
remote, or `-u` — and the record must be in the pushed branch. The audit there
counts from the branch's first reflog entry; later pushes pass, and so does a
push straight to the default branch, which this gate does not serve.

**The record of the work is committed.** Each piece of work keeps a record in
its own tree, `.orrery/work/<work>/retrospective.md`, where `<work>` is the
worktree's name, or the branch on the main checkout:

```bash
"$ORRERY/skills/build/record.sh" write --what "one line on what actually happened"
```

That writes the spend table from the session's own transcripts — model, tokens
and tool calls per stage — and the line. Commit it with the work. It travels in
the pull request and reaches the default branch with the merge, which is the
closing act; re-run it before a later push and it refreshes. Work that ends
without merging is closed on its branch with
`record.sh close refused|withdrawn|answered|enacted --why "…"`, once.

**Or keep records off the branch.** Add `.orrery/work/` to your own
`.gitignore` — your edit; Orrery never makes it. The gate then accepts a record
on disk, and each record lives only in its worktree: removing the worktree
deletes it, and `doctor` says so on every run.

The reason is a measurement, not a preference: across three projects in one
week, 179 issues closed and 218 pull requests merged with **two** retrospectives
between them. Nobody decided to stop writing them. There was simply nothing that
noticed. Until this release that refusal sat on `gh issue close`, with a copied
workflow reopening what a merge closed bare; both are gone, and closing an issue
is yours again.

**An auditor has run in this session since its last pull request.** Every route
in `plan`, the smallest included, ends with that audit before the change heads
for the default branch; the guard is what makes the sentence hold where it can
see the session. It reads the call log, so with the log switched off this half
passes everything through. It sees that an auditor was spawned, not what it
said.

**And there is a way past both, which writes itself down:** the owner's word,
quoted.

```
ORRERY_WAIVE="owner: ship it now" gh pr create …
```

Skipping stays possible on purpose — the same argument `--no-verify` earns in a
pre-commit hook. What ends is skipping being invisible: the reason and a hashed
session id land in `.orrery/local/waivers.tsv`. Either a row carries a reason,
or the gate was gone around. An agent's own view that a change needs no audit is
not a reason it takes.

It is per machine and never committed: `.orrery/local/` ignores itself. That was
learned the hard way when the file sat in `.claude/` — a manual run wrote rows
into it and `git add -A` committed them, so the first row of a record whose
whole value is that its rows are true was a test artifact.

**What the gate does not reach**, stated so you do not mistake its silence for
coverage: a pull request opened in the web UI or through `gh api`, or through an
interpreter, `bash -c "..."` or `eval` — those take deciding to write, and the
waiver is cheaper. They are `allow` cases in `hooks/process-cases.tsv`, so the
limit is a decision you meet rather than a hole you discover; read that file
rather than this paragraph for the current list. A machine without the plugin is outside it too.
Orrery adds no check to your CI to close that gap: your pipelines are yours.

**And it can refuse text that opens nothing.** The pattern is quote-blind — it
cannot parse shell — so a metacharacter inside quoted prose reads as a command
separator, and writing *about* the gate in a commit message or a pull-request
comment can be refused. The workaround is to pass the text through a file —
`git commit -F msg.txt`, `gh pr comment --body-file` — and the alternative is a
heuristic that would become a bypass.

It covers what a session types, and it is a nudge rather than a boundary.

## Copy in the one gate a hook cannot be

Only where `.orrery/config.json` declares `"tracker": "github"`. Without a
tracker there is no issue to name, so skip this section — all but the
`retrospective-on-close.yml` paragraph, which binds anyone who copied it.

```bash
mkdir -p .github/workflows install/ci
cp "$ORRERY/install/ci/pr-names-an-issue.yml" .github/workflows/
cp "$ORRERY/install/ci/names-an-issue.sh" "$ORRERY/install/ci/names-an-issue.test.sh" install/ci/
```

`$ORRERY` is wherever the plugin is installed; `/doctor` prints the path.

This refuses a pull request that names no issue, which
`rules/git/every-merge-is-recorded-in-an-issue.md` requires and nothing else
here can enforce. **A hook cannot do it.** The hooks see commands a session
types; a merge closes an issue server-side, from an event no local hook is
present for. Measured across three projects in one week before this existed:
nine pull requests merged carrying no issue reference at all, in projects where
that rule was loaded into every session.

**If you copied `retrospective-on-close.yml` before this release, delete it.**
It reopened an issue that closed with no retrospective comment, and records are
files now, never comments — left in place it reopens every issue a merge closes.
`/doctor` fails while it is there.

It is a copy rather than something the plugin supplies at runtime, because
GitHub Actions runs against your repository's checkout and cannot read a plugin
cache. That means it can go stale; `/doctor` reports when the workflow is
missing, and re-copying is the whole update.

## What stays your responsibility

Everything this plugin enforces arrives through two doors: the hooks, which see
Bash commands and agent spawns, and the deny-list above, which Claude Code
applies to file reads and edits. Both doors are about the shell and the
filesystem.

**MCP servers and plugins pass through neither.** A tool an MCP server exposes is
not a Bash command and not a file edit, so no hook sees it, no deny rule matches
it, and nothing here constrains what it does or where it sends what it read.
Which servers a session carries is your configuration — a different project
carries a different set, and a plugin that installs into all of them cannot know
yours.

So the line is: this plugin covers what a session does through the shell and the
filesystem. It does not cover what a connected server does on the session's
behalf, and it does not cover a plugin you install beside it. **That second list
is not a roadmap.** Those choices are yours, they stay yours after this is
installed, and saying so is the difference between a boundary and a promise.

## What must never be copied into the library

The project's own `CLAUDE.md` keeps everything Orrery deliberately excludes:
stack invariants, domain rules, business decisions, deadlines, prices, anything
with a credential in it. `.claude/settings.local.json` regularly holds secrets.
Extraction into a shared library is done file by file, by hand — `cp -r` is
never the right move.
