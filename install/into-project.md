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
guards deny everything rather than let one call through unchecked, the loaders
announce that they could not run, and the handoff prompt stands aside rather
than strand a session.

`orrery:handoff` writes to the task's GitHub issue, so the project needs `gh`
authenticated and an issue per task — which the flow already assumes.

## Updates arrive only once you switch them on

Claude Code updates plugins in the background only from Anthropic's own
marketplace. For every other one, this one included, auto-update is **off** by
default, so an install stays on the version it was installed at until someone
updates it by hand. Switch it on once per machine:

1. In any session: `/plugin` → Marketplaces → `orrery` → Enable auto-update.
2. The repository is private, so the background check has to reach it without
   prompting. With the GitHub CLI that is one command in a terminal:

   ```bash
   gh auth setup-git
   ```

   Without a credential helper the check fails quietly and the old version
   stays — nothing reports it.

A new version is then fetched in the background and loads on the next launch of
Claude Code, in every project where the plugin is installed at user scope. To
update by hand instead, after each release:

```bash
claude plugin marketplace update orrery
claude plugin update orrery@orrery --scope user
```

## What the project declares

Orrery holds the skills and guards. The project holds its own facts, declared in its
`CLAUDE.md`, and the skills read them by name:

| Declaration | Used by | If missing |
|---|---|---|
| `Output language: <language>` — terminal conversation only | Canon §8, `build` | Everything stays English |
| Plan directory | `plan` | Falls back to `docs/planning/plans/` |
| Debt labels — the label that marks debt, the scope labels, the priority labels, in the project's own spelling | `debt` | Its queries match nothing, and an empty pool is indistinguishable from a clean one |
| Debt pool — the area labels whose debt feeds the per-task quota | `debt` | Falls back to the area the current task touches, which in a repository with several areas is close to no narrowing at all |
| Debt quota — how many debt issues a feature task also closes | `debt`, `build` | No quota; the skill tracks and reports only |
| Model tiers — which model serves each build tier | `build` | The session's default model throughout |
| Quality gates — the commands that prove the work | `build`, Canon §3 | The agent has no proving command to run |
| Branch and PR flow | `build` | Branch-from-default, PR, squash |
| Sharpen log location | `sharpen` | `docs/sharpen-log.md`, created on first use |
| `Incident inbox: <owner>/<repo>` — see below | `learn` | Rules stay local, which is the correct default |

## Optional: record which tools get called

Nothing is recorded unless you ask for it. Set `ORRERY_CALL_LOG` to a path in
your project's `.claude/settings.json` and `hooks/call-log.sh` appends a line
per event: a timestamp, a fingerprint of the session, the tool name, the
subagent type where there is one, whether the spawn was named, the event —
`call` or `ran` — and the harness's id for that call.

**Two lines per completed call, one per call that was stopped.** `ran` is
written only when a tool succeeds, so a `call` with no `ran` under the same id
did not run, whatever stopped it — a guard, the permission system, or you
answering no. It costs one extra hook invocation per successful call, and it is
the difference between a log that records what was attempted and one that
records what happened. What it cannot tell you is *which* of refused, errored
and interrupted a given unpaired line was.

Never the command, the prompt, the file path, the branch or the agent's name.
The session id is hashed rather than stored, so a line correlates with its
neighbours and identifies nothing beyond the machine that wrote it.

```json
{ "env": { "ORRERY_CALL_LOG": ".claude/orrery-calls.tsv" } }
```

**Add that path to `.gitignore` too.** The file grows by a line on every tool
call and is trimmed from the head once it reaches the cap, so committing it puts
a conflict in front of everyone who runs a session in your repository — and the
hashed session id it carries tells a second reader nothing they can use.

**A relative path is resolved against your project root**, whatever directory a
tool call happens to be running in — one log, at the path you wrote, always. It
did not used to be. Before this version it was resolved against the working
directory, so every `cd` into a subdirectory started another log there. One
project accumulated **twenty** of them, six directories deep, and a `.gitignore`
line is anchored to the directory holding it — so the strays were not ignored,
and one of them was committed.

If you installed before this version, they are still on disk. Harmless — the log
holds no content by design — but yours to remove:

```bash
find . -name orrery-calls.tsv -not -path ./.claude/'*'      # look first
git ls-files '*orrery-calls.tsv'                            # any that got committed
```

An absolute path is used exactly as written. A relative path with no project
root to resolve against records nothing rather than guessing — the one place
this hook does not fail open, because a missing line costs a line and a file in
your source tree costs you finding it.

Remove that line and it stops. The log is capped — 256 KB by default,
`ORRERY_CALL_LOG_MAX` to change it — and `hooks/call-log.sh --purge` empties it.

**Why you might want it.** `sharpen` reads it, and the shape of a session shows
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
is the call log described above, which stays on your disk and is not written at
all unless you name a path for it. The one exception is opt-in and
mechanical: a project that declares `Incident inbox: <owner>/<repo>` in its
`CLAUDE.md` — and whose `gh` can reach that repository — asks `learn` to also
file each incident there. No declaration, or no access, means no attempt.

There is no `domain` scope in the shipped rules, and adding one would be a
mistake: a rule about a host project's subject matter belongs in that project's
local layer, not in a library that installs into all of them.

## Merge the deny-list

`hooks/permissions.json` holds 121 deny rules — system paths, secret files,
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
nothing runs it for you. It writes `<project>/.claude/orrery-deny.json` with the
set that was missing at that moment, and those rules stop appearing — in the
startup line and in the doctor's list alike. **Commit that file.** It is your
team's decision rather than your laptop's: committed, it holds for everyone in
the repository and it turns up in a pull request where someone can push back on
it, which is the only review a deliberately widened gap gets. To un-decline a
rule, edit the file and commit that. If you would rather keep the decision to
your own machine, add the path to `.gitignore` in the same edit — nothing else
will, exactly as with the call-log path above.

**Why we do not merge it for you.** `.claude/settings.json` carries every deny
decision in your project, and a plugin that edits it is a plugin that can quietly
widen what it is allowed to do. So this check reads that file and never writes
it, and no skill here will merge on your behalf. `orrery-deny.json` is the only
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

## Closing an issue now goes through a gate

`hooks/process-guard.sh` refuses `gh issue close`. This is the one hook that
will stop a command you have been running for years, so it is described here
rather than met cold.

The reason is a measurement, not a preference: across three projects in one
week, 179 issues closed and 218 pull requests merged with **two**
retrospectives between them. Nobody decided to stop writing them. There was
simply nothing that noticed.

```bash
skills/build/close-issue.sh <N> --what "one line on what actually happened"
```

That builds the spend table from the session's own transcripts, posts it, and
then closes the issue — so nothing has to verify that a comment exists. Add
`--since <iso8601>` when the session already reported on an earlier issue.
Closing an umbrella takes `--body-file <path>` instead: a phase retrospective
is summed from its children, and this session's transcripts are the closer's
spend rather than the phase's.

**And there is a way past it, which writes itself down:**

```bash
skills/build/close-issue.sh 42 --waive "why this one closes without a retrospective"
```

It posts the reason on the issue and records it locally. The older
`ORRERY_WAIVE="why" gh issue close 42` still works and records only the local
row — so in a project running `retrospective-on-close.yml` (below) the server
sees a bare close and reopens it. Use `--waive` there.

Skipping stays possible on purpose — the same argument `--no-verify` earns in a
pre-commit hook. What ends is skipping being invisible: the reason, the issue
number and a hashed session id land in `.claude/orrery-waivers.tsv`. Either a
row carries a reason, or the gate was gone around.

**Add that path to `.gitignore` too**, for the reason the call-log path above
carries — and this one was learned the same way: a manual run wrote rows into
the file and `git add -A` committed them, so the first row of a record whose
whole value is that its rows are true was a test artifact. If you would rather
keep the log in the repository, that is a defensible choice — commit it
deliberately and know that everyone's rows conflict.

**What the gate does not reach**, stated so you do not mistake its silence for
coverage: an issue closed by a merging pull request never passes a Bash hook at
all — GitHub closes it server-side. Nor does a close routed through an
interpreter, `bash -c "..."` or `eval`; both take deciding to write, and the
waiver is cheaper than either. Those two are `allow` cases in
`hooks/process-cases.tsv`, so the limit is a decision you meet rather than a
hole you discover — but read that file rather than this paragraph for the
current list, because a sentence claiming the list is complete is the first
thing to go stale.

**And it will refuse things that close nothing.** The pattern is quote-blind —
it cannot parse shell — so a metacharacter inside quoted prose reads as a
command separator, and writing *about* the gate in a commit message or a
pull-request comment can be refused. It happened three times in the session
that built it, once caused by a rule added in that same commit. The workaround
is to pass the text through a file — `git commit -F msg.txt`, `gh pr comment
--body-file` — and the alternative is a heuristic that would become a bypass.

It covers what a session types, and it is a nudge rather than a boundary.

## Opening a pull request needs an auditor first, where a call log is kept

Where `ORRERY_CALL_LOG` is set, `hooks/process-guard.sh` also refuses
`gh pr create` until an `auditor` agent has run in this session since its last
pull request. Every route in `plan`, the smallest included, ends with that
audit before the change heads for the default branch; the guard is what makes
the sentence hold where it can see the session. With no call log it passes
everything through, and the skills' text is all there is.

It sees that an auditor was spawned, not what it said. The way past it is the
owner's word, quoted:

```
ORRERY_WAIVE="owner: ship it now" gh pr create …
```

which is recorded in `.claude/orrery-waivers.tsv` like a waived close. An
agent's own view that a change needs no audit is not a reason it takes.

## Copy in the one gate a hook cannot be

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

### And its sibling: a finished issue carries its retrospective

```bash
cp "$ORRERY/install/ci/retrospective-on-close.yml" .github/workflows/
cp "$ORRERY/install/ci/retrospective-on-close.sh" "$ORRERY/install/ci/retrospective-on-close.test.sh" install/ci/
```

The hook that refuses a bare issue close sees what a session types, and a merge
is not typed: `Closes #N` closes the issue server-side. Measured on one host over
a week: more than a hundred issues closed as finished work, one with a
retrospective, while every merged pull request named an issue — the half with a
gate held and the half without one did not.

This workflow reopens an issue that closed as finished work with no
retrospective on it, with one comment naming the command that closes it
properly. Closes as *not planned* or *duplicate* are left alone. It needs
`issues: write`, which it declares.

**What it costs, said before you meet it.** A session that merges first and
posts afterwards is reopened in between; `build` avoids that by posting with
`--no-close` before the merge. An issue you close by hand as *completed* is
reopened too — close it with `close-issue.sh <N> --waive "<reason>"` instead, or
as *not planned* when that is what it was. If agents on your project take work
from open issues, a reopened one looks like work: the comment says why it
reopened, and a pool that reads comments before starting will see it.

It cannot see a merge made by a workflow running on `GITHUB_TOKEN` — a bot
auto-merge, for instance — because those raise no `issues` event. `/doctor`'s
count of closed issues without a retrospective still catches them.

Both are copies rather than something the plugin supplies at runtime, because
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
