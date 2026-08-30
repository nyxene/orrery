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
by name. All seven hooks start firing immediately — including the one that stops
the first compaction of a session to ask whether there is unfinished work to
hand off.

Every hook needs **`jq`** on `PATH`. Install it before the plugin or nothing
will work. Each hook fails in the direction that is safe for what it does: the
guards deny everything rather than let one call through unchecked, the loaders
announce that they could not run, and the handoff prompt stands aside rather
than strand a session.

`orrery:handoff` writes to the task's GitHub issue, so the project needs `gh`
authenticated and an issue per task — which the flow already assumes.

## What the project declares

Orrery holds the method. The project holds its own facts, declared in its
`CLAUDE.md`, and the skills read them by name:

| Declaration | Used by | If missing |
|---|---|---|
| `Output language: <language>` — terminal conversation only | Canon §8, `build` | Everything stays English |
| Plan directory | `plan` | Falls back to `docs/planning/plans/` |
| Debt labels — the label that marks debt, the scope labels, the priority labels, in the project's own spelling | `debt` | Its queries match nothing, and an empty pool is indistinguishable from a clean one |
| Debt pool — the one active area whose debt feeds the per-task quota | `debt` | Falls back to the area the current task touches, which in a repository with several areas is close to no narrowing at all |
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
updates itself, your copy does not. Your install can sit a release or more behind
the shipped list with every health check green, and the rules likeliest to be
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
permission flow every time, deliberately. Shell network access is limited to the
domains listed; in-process tools are unaffected, so reading documentation and
searching the web work normally.

Add the domains your own work needs. The two above are a starting point, not a
recommendation about your project.

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
