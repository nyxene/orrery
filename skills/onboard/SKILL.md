---
name: onboard
description: Bring Orrery into a project, or move an older install onto this version — read the project, ask the owner only what is theirs to decide, draft the settings, and hand them one script to run. Invoke on "onboard", "add orrery to this project", "set up orrery here", "upgrade orrery in <project>", or before a project's first session under Orrery. Not a health check of an install that already works — that is `doctor`.
argument-hint: "[project path, default the current project]"
---

# Onboard — Orrery Into a Project, Without the Owner Explaining It

Every project needs the same dozen decisions, and without this they were explained
by hand, per project: install scope, which settings, committed or local, the deny
list, gates, labels, rulesets, the PR-names-an-issue workflow, attribution, worktree
caveats. This skill reads the project, decides what the repository already answers,
asks the owner the rest once, and ends with a checklist.

**The session writes no project file.** It drafts; the owner runs
`onboard.sh` from a terminal. What it writes — the settings that switch gates, the
deny list — a session is denied, and that is the point.

## Where it runs

Against a path, like `doctor`: `/orrery:onboard <path to the project>`.

- **From the project itself**, once it has Orrery. A fresh project first gets, typed
  in it: `claude plugin marketplace add nyxene/orrery`, then
  `claude plugin install orrery@orrery --scope local`.
- **From any other session that has this skill**, against a project whose install
  is older and does not. Reading another project needs the owner's consent — ask
  once, name the path.

The script is in this skill's own directory; give the owner its absolute path —
`$CLAUDE_PLUGIN_ROOT` is not set in their terminal.

## 1. Read before asking

| What | How | Answers |
|---|---|---|
| The install | `doctor`'s `check-install.sh <project>` | version, scope, cache, config in force, missing deny rules, leftovers, PR gate, ignored records |
| The script's view | `onboard.sh check <project>` | the same, plus what `prepare` and `update` would do |
| Declarations to migrate | the project's `CLAUDE.md`, `CLAUDE.local.md` | language, gates, plan directory, debt labels and quota, branch flow — prose that 0.32 stopped reading |
| Gates | CI workflows, `package.json`, `Makefile`, `scripts/` | `qualityGates` |
| Tracker | the `origin` remote; `gh label list` | `tracker`, and whether the debt labels exist |
| Rulesets | `gh api repos/<owner>/<repo>/rulesets` (read) | whether the default branch takes changes only by pull request |

State what you found; do not ask what the repository already says.

## 2. Ask the owner, once, with a default

| Question | Default, and why |
|---|---|
| Tracker | `github` when `origin` is on GitHub; none otherwise. Without one, records and debt are files and the gate moves to a branch's first push |
| Output language | what the project's `CLAUDE.md` declares, else English |
| Settings committed or on this machine | committed for a private or team repository — reviewed, seen by everyone; **local** for one that is or will be public, or one person's |
| Install scope | `local` — this machine, this project. `project` puts `enabledPlugins` in the committed settings for a team; `user` enables it in every repository, so avoid it |
| Gates | the commands found in step 1 |

Each config key and its effect is in the install guide, *What the project declares*.

## 3. Draft

Write the settings to **your own** project's `<main checkout>/.orrery/local/onboard/<project>/config.json`
— a session can write nowhere else, and `local/` is ignored and outlives the session.
One JSON object; only keys the owner chose or the repository answered.

Then draft, for the owner to run, never run yourself:

- **Labels** the debt keys name and the tracker lacks: `gh label create <name> --repo <owner>/<repo>`.
- **A ruleset**, where the default branch accepts direct pushes and the owner wants it
  not to: the `gh api --method POST repos/<owner>/<repo>/rulesets` call, with the
  pull-request rule — shown, explained, theirs to run.
- **Attribution**: Claude Code adds a co-author trailer to commits and a line to pull
  request descriptions. A project that wants neither, or other text, sets the
  `attribution` key in its Claude Code settings — see the attribution section below.

## 4. The owner runs the script

```
onboard.sh check    <project>
onboard.sh prepare  <project> --config <draft> --mode committed|local [--label <l>] [--pr-gate]
onboard.sh update   <project> [--records-ok]
onboard.sh rollback <project>
```

| | `--mode committed` | `--mode local` |
|---|---|---|
| `--config` | the draft; not needed once the settings are on the default branch | the draft |
| Settings | `.orrery/config.json`, in a pull request | `<main>/.orrery/local/config.json`, never committed |
| Deny list | merged into `.claude/settings.json`, same pull request | merged into `.claude/settings.local.json` — this machine only |
| `orrery-method` entries | removed | — |
| `--pr-gate` | copies the PR-names-an-issue workflow where the tracker is GitHub and the project has no gate of its own | — |
| How | an issue (with `--label` where the project requires one) and a pull request that closes it, from a worktree of its own | written at once |

**Order: `prepare`, merge its pull request, then `update`.** `update` refuses until
the settings are in force, and refuses while the default branch's recent merges carry
no `.orrery/work/*/retrospective.md`: since 0.32 the gate refuses a pull request
without one, so a project whose agents open pull requests without writing a record
would be stopped. Say that to the owner in those words; `--records-ok` is theirs to
add once they know. `update` saves the install record first; `rollback` puts it back.

**After an update that adds deny rules**, run `prepare` again in the same mode. In
committed mode, with the settings already on the default branch, it leaves them as
reviewed and opens a pull request that only brings the deny list up to date; with
nothing to change it opens nothing. `doctor` and the line at session start say when
rules are missing.

## Attribution

Claude Code's `attribution` setting, in any of its settings files
([settings reference](https://code.claude.com/docs/en/settings-reference.md)):

| Key | Default | To change |
|---|---|---|
| `attribution.commit` | a `Co-Authored-By:` trailer on each commit | other text, or `""` for none |
| `attribution.pr` | a "Generated with Claude Code" line in pull request descriptions | other text, or `""` for none |
| `attribution.sessionUrl` | the session link on commits and pull requests from cloud and Remote Control sessions | `false` to leave it out |

`"attribution": false` hides all of it, but only Claude Code 2.1.281 and later
accept it — **an earlier version skips the whole settings file that holds it**,
deny list included. Where an older version may read the file, write the three keys
instead: `"commit": ""`, `"pr": ""`, `"sessionUrl": false`. `includeCoAuthoredBy`
is the older key and is deprecated. Committed `.claude/settings.json` sets it for everyone in the project;
`settings.local.json` for this machine. Leave the platform's default unless the owner
names a policy — a public repository is the usual reason to drop the session link.

## Worktrees

- Settings in `.orrery/local/config.json` and records archived to
  `.orrery/local/work/` live in the main checkout and are read from every worktree.
- A committed `.orrery/config.json` is read from the tree the session stands in —
  a branch without it runs on defaults.
- A plugin enabled only in `settings.local.json`: whether a worktree session sees it
  is not established — run `doctor` inside a worktree once and look.

## Done

- [ ] `onboard.sh check` reports the settings in force and no missing deny rules
- [ ] the `prepare` pull request is merged (committed mode)
- [ ] `update` ran, or was deferred on purpose and the owner knows why
- [ ] every session in the project restarted
- [ ] `/orrery:doctor` in the project, and once inside a worktree, is clean
- [ ] labels and ruleset commands handed over, or not needed
