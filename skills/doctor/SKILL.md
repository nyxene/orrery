---
name: doctor
description: Check whether orrery is actually loaded and current in a host project — enabled on the checked-out branch, cache matching the marketplace source, no conflicting global install. Invoke on "doctor", "is orrery working", "check the plugin install", "why isn't the plugin loading", or periodically as a health check independent of any specific symptom.
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
(both `--json`, for install metadata, and plain text, for the load-status line
and error message `--json` doesn't carry) says about this project's install ·
`enabledPlugins` is true on **the branch actually checked out** — not main,
not whatever branch the install commit landed on · whether user scope and
project scope are *both* enabling orrery at once, which double-fires every
hook · the cached git SHA matches the marketplace source's current HEAD (a
version-string match alone misses a source change that forgot a version bump)
· the loaded cache's `plugin.json` doesn't redeclare a hooks path (a manifest
shape that loads nothing while passing validation) · whether this project's
copy of the deny-list still matches the one the plugin ships.

That last one calls `hooks/permissions-check.sh --report` rather than repeating
the comparison; the same script runs as a `SessionStart` hook and says it once
per session. It exists because the deny rules in `hooks/permissions.json` are
merged into your project's settings **by hand**: the plugin updates itself,
that copy does not, and nothing else reports the gap — an install can sit
dozens of rules behind with every other check here green. `--report` compares
the rules of the copy that is running, not the rules of whatever version the
inspected project has cached.

Each run appends one row to `~/.claude/orrery/doctor/<project-slug>.md` —
one file per host project, deliberately outside any plugin cache, since
installed-as-a-plugin this script runs from a version-pinned cache directory
that gets replaced on every update and would otherwise reset its own history.
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
  state question, not a plugin bug.
- **Global conflict: double-enabled** — user scope and project scope both
  enable orrery for the same project; every hook fires twice. Decide which
  scope should own it and disable the other. (User scope alone, with no
  project-scope entry, is not a conflict — that's just a global install.)
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
`--json`. If orrery is project-scope-installed in more than one project at
once, the status line picked up here could in principle belong to a different
project's entry rather than this one's — this script only trusts it once
`--json` has confirmed *some* install exists for this exact project, which
narrows but does not eliminate the ambiguity.
