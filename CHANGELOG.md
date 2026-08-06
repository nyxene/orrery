# Changelog

Every release of Orrery is recorded here, newest first. The version is the
`version` field in `.claude-plugin/plugin.json`: Claude Code decides an
installed plugin has an update from that number and nothing else, so a change
without a bump reaches nobody.

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
