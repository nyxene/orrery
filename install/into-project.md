# Installing Orrery into a project

```bash
/plugin marketplace add nyxene/orrery
/plugin install orrery@orrery
```

Skills become available as `orrery:frame`, `orrery:plan`, `orrery:build`,
`orrery:review`, `orrery:diagnose`, `orrery:pare`, `orrery:verify`,
`orrery:debt`, `orrery:doctor`, `orrery:feedback`, `orrery:handoff`,
`orrery:learn`,
`orrery:sharpen`. Agents (`planner`, `architect`, `critic`, `auditor`) resolve
by name. All six hooks start firing immediately — including the one that stops
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
| Debt quota — how many debt issues a feature task also closes | `debt`, `build` | No quota; the skill tracks and reports only |
| Model tiers — which model serves each build tier | `build` | The session's default model throughout |
| Quality gates — the commands that prove the work | `build`, Canon §3 | The agent has no proving command to run |
| Branch and PR flow | `build` | Branch-from-default, PR, squash |
| Sharpen log location | `sharpen` | `docs/sharpen-log.md`, created on first use |
| `Incident inbox: <owner>/<repo>` — see below | `learn` | Rules stay local, which is the correct default |

## Optional: record which tools get called

Nothing is recorded unless you ask for it. Set `ORRERY_CALL_LOG` to a path in
your project's `.claude/settings.json` and `hooks/call-log.sh` appends one line
per tool call: a timestamp, a fingerprint of the session, the tool name, the
subagent type where there is one, and whether the spawn was named.

Never the command, the prompt, the file path, the branch or the agent's name.
The session id is hashed rather than stored, so a line correlates with its
neighbours and identifies nothing beyond the machine that wrote it.

```json
{ "env": { "ORRERY_CALL_LOG": ".claude/orrery-calls.tsv" } }
```

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

`hooks/permissions.json` holds 99 deny rules — system paths, secret files,
destructive git. Merge its `permissions.deny` array into the project's
`.claude/settings.json`. It is additive and safe to apply to any repository.

## What must never be copied into the library

The project's own `CLAUDE.md` keeps everything Orrery deliberately excludes:
stack invariants, domain rules, business decisions, deadlines, prices, anything
with a credential in it. `.claude/settings.local.json` regularly holds secrets.
Extraction into a shared library is done file by file, by hand — `cp -r` is
never the right move.
