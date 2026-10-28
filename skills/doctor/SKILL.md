---
name: doctor
description: Check whether orrery is actually loaded and current in a host project — enabled on the checked-out branch, cache matching the marketplace source, no conflicting global install, and no leftover `orrery-method` plugin. It also reports whether any of it is actually being *used* here — which skills fired, whether agent spawns carried a type, and whether the pull-request gate a hook cannot be is installed. Invoke on "doctor", "is orrery working", "check the plugin install", "why isn't the plugin loading", "is anyone using this", or periodically as a health check independent of any specific symptom.
argument-hint: "[optional: a project path, default is the current one]"
---

# Doctor — Is the Install Actually What You Think It Is

A plugin install has more failure states than "works" or "doesn't": disabled on
this branch but not another, a stale cache holding a version the source moved
past an hour ago, a global-scope install shadowing a project-scoped one. None
of these throw — they sit quietly and produce behavior that looks like the
plugin, minus whatever changed.

Nothing here relies on a validator passing — `claude plugin validate --strict`
can pass a manifest that still fails to load. The reliable evidence is what
`claude plugin list` reports from inside the host project, and that is what
this reads.

## Run it

```bash
# from inside the orrery checkout itself
skills/doctor/check-install.sh [project-dir]

# installed as a plugin in a host project — the script lives in the cache
"$CLAUDE_PLUGIN_ROOT/skills/doctor/check-install.sh" [project-dir]
```

`project-dir` defaults to `$CLAUDE_PROJECT_DIR` or the current directory. No
Claude session required — plain bash, `jq`, and (for most checks) the `claude`
CLI on `PATH`. Run it from cron, from a terminal, or invoke this skill inside a
session; either way it runs every check and exits non-zero if any of them
needs attention, so it is scriptable without anyone reading prose to find out.
If `claude` isn't reachable (common under cron — login-shell PATH additions
like nvm/homebrew shims often aren't loaded), it says so explicitly rather than
reporting "not installed."

It checks, in order: `jq` and `claude` on `PATH` · what `claude plugin list`
(both `--json`, for install metadata and the `enabled` flag, and plain text,
for the "failed to load" status and error message `--json` doesn't carry) says
about this project's install, at **project, local or user scope** · whether
`enabledPlugins` is true in either `.claude/settings.json` — where it is a fact
about **the branch actually checked out**, not main and not whatever branch the
install commit landed on — or `.claude/settings.local.json`, where it is
untracked and therefore not a branch fact at all · whether user scope and a
project-local scope are *both* enabling orrery at once, which double-fires every
hook · the cached git SHA matches the marketplace source's current HEAD (a
version-string match alone misses a source change that forgot a version bump)
· the loaded cache's `plugin.json` doesn't redeclare a hooks path (a manifest
shape that loads nothing while passing validation) · whether this project's
copy of the deny-list still matches the one the plugin ships · whether an
`orrery-method` plugin from before the method became text is still installed · in a repository, whether
`.orrery/config.json` is there and parses, which files were left at the places
used before `.orrery/`, and how many changes on the default branch brought a
record of their work.

The deny-list check calls `hooks/permissions-check.sh --report` rather than repeating
the comparison; the same script runs as a `SessionStart` hook and says it once
per session. It exists because the deny rules in `hooks/permissions.json` are
merged into your project's settings **by hand**: the plugin updates itself,
that copy does not, and nothing else reports the gap — an install can sit
dozens of rules behind with every other check here green. `--report` compares
the rules of the copy that is running, not the rules of whatever version the
inspected project has cached.

Each run appends one row to `.orrery/local/doctor/log.md` in the project's
main checkout — beside the call log, outside any plugin cache, since
installed-as-a-plugin this script runs from a version-pinned cache directory
that gets replaced on every update and would otherwise reset its own history.
Outside a repository it is `~/.claude/orrery/doctor/<project-slug>.md`, where
it lived before, and a repository's first run carries that history over.
Oldest run at the top of that file, newest at the bottom. Read the last few
before treating one red run as a regression — a branch that predates the
install commit fails the branch-enablement check every time, and that is not
news.

## When it's red

- **Load status: failed to load** — the plain-text error line is printed
  alongside; it names the exact manifest problem, not a guess.
- **Cache stale (SHA mismatch)** — the source moved since install. Run
  `claude plugin update orrery@orrery --scope <scope>`, then **restart the
  Claude Code session** — the cache is a snapshot pinned to a git SHA, taken at
  install/update time; it does not follow the source directory live even when
  the marketplace source is a local path.
- **Not enabled on this branch** — check whether the branch actually has the
  commit that added `enabledPlugins` to `.claude/settings.json`. This is a git
  state question, not a plugin bug. It is only ever said of the *tracked* file:
  a project that enables orrery in the untracked `.claude/settings.local.json`
  — which is what any repository whose index other people read does, to keep
  the owner's configuration out of it, private ones included — gets `yes (local file)` and no branch named, because that
  file does not vary by branch and claiming otherwise would be a check that
  cannot fire.
- **Global conflict: double-enabled** — user scope and one of the project's
  own settings files both enable orrery for the same project; every hook fires
  twice. Decide which scope should own it and disable the other. (User scope
  alone, with no project-local entry, is not a conflict — that's just a global
  install.)
- **Manifest shape: buggy** — the cached `plugin.json` redeclares a hooks
  path. Fix the source, `claude plugin update`, restart.
- **Deny-list: behind** — the rules printed underneath are shipped by this
  plugin and absent, by exact text, from this project's settings. Report the
  missing rules to the user and stop. Do not edit their
  `.claude/settings.json` — merging the deny-list is their edit to make. Do not
  run `--reconcile`: it records that a human looked at these rules and declined
  them, and running it on their behalf makes that record false and silences the
  warning permanently. The doctor prints that command underneath, with its path
  resolved, because the plugin root moves on every update and no document can
  carry it — **it is printed for you to hand over, not to run.** Pass it on
  exactly as printed.
- **Method plugin: leftover** — `orrery-method` is still installed as a
  plugin. Until 0.30.0 this plugin depended on it; the method is text now,
  ships no plugin, and orrery does not use it. Left installed it loads a second
  canon into every session from a repository that no longer serves it.
  `/plugin marketplace remove orrery-method` takes out the marketplace and the
  plugin installed from it.
- **Usage: no log** — no call log, so nothing can say what ran here. Either
  `.orrery/config.json` (or this machine's `.orrery/local/config.json`) says `"callLog": false`, or no session has run since
  the install. Not an install fault.
- **Usage: no skills in N days** — the plugin loads and nothing invokes it.
  Nothing to repair in the install; say it to whoever directs the work, since
  a library nobody calls still spends every session's context.
- **Spawns: k/n untyped** — those agents ran with no type or as
  `general-purpose`, so no role's model or tool list applied. Pass the role as
  `subagent_type` (`orrery:critic`, `orrery:auditor`, …) when spawning.
- **Config: missing** — a GitHub remote, no `.orrery/config.json` and no tracker in `.orrery/local/config.json`, so the
  tracker reads as none and the guard gates a branch's first push rather than
  `gh pr create`. Declaring `"tracker": "github"` is the project's edit to make;
  the model may not write that file. **malformed** — it does not parse, and every
  declaration in it reads as its default.
- **Old files: n left** — files a hook used before `.orrery/` existed, copied
  once and read no more. Safe to delete once the old rows are not wanted.
- **Records: r/n** — of the changes on the default branch in the window, how
  many brought `.orrery/work/*/retrospective.md`. Counted, not failed: a waived
  gate, a change from before records, or a rebase merge — several commits per
  work, one carrying the record — explains a gap. Not counted where the
  project ignores `.orrery/work/`.
- **PR gate: missing** — nothing in the host's workflows refuses a pull request
  that names no issue, and no hook can see a merge. Install it per
  `install/into-project.md`. **own (unverified)** means a workflow reads the
  pull request body — likely the project's own gate; read it to confirm.
  **n/a — no tracker**: the project has no tracker, so there is no issue for a
  pull request to name.
- **Deny-list: unknown** — the comparison could not be made: a settings file
  that will not parse, an unreadable shipped list, no `jq`. The message says
  which. This is **not** a drift finding and must not be repeated as one — fix
  what it names and run the doctor again.

## What this does not check

Whether the *skills and agents themselves* still do the right thing — that is
what actually invoking them and reading the result tells you. This only proves
the delivery mechanism is intact, the same way `verify` proves a fix and not
the absence of every other bug. It also can't see a load failure that doesn't
surface in `claude plugin list` at all (unverified: whether every possible
manifest error still leaves an `installPath` entry to inspect) — a clean run
is evidence, not a guarantee.

The plain-text load-status line carries no project attribution, unlike
`--json`. If orrery is installed at project or local scope in more than one
project at once — the ordinary case on a machine with several host projects —
the block picked up here belongs to whichever install the CLI printed first,
which is usually not this one.

So the text is consulted **only when the output contains exactly one
`orrery@orrery` block**. Enabled versus disabled comes from the `enabled` field
on the entry already matched by `projectPath`, and is correct either way; what
the ambiguity costs is the third state, `failed to load`, which no boolean can
express. Where it cannot be ruled out the report says so —
`enabled (load failure not ruled out)` — rather than printing a clean pass or
attributing a neighbour's failure to this project.
