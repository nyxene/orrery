# Orrery (product) — project instructions

This repository is the **released product** of the Orrery method: the plugin —
canon, skills, agents, hooks, rules — and nothing else. The written methodology
lives in its own repository and is not distributed here. Everything in this one
is what consumers install; treat every file as shipped.

**Nothing is developed here.** Changes arrive one of two ways: a promotion PR
from the workshop repository, or a community pull request. If a session in
this repository finds itself designing something new, it is in the wrong
repository — file an issue instead.

Ground rules for any session here:

- A change without a version bump in `.claude-plugin/plugin.json` reaches
  nobody; the bump is part of the change, not an afterthought.
- The quality gates are `claude plugin validate . --strict`, a suite beside each
  hook that has one — the three guards, the call log, the two loaders, the handoff
  prompt and the deny-list check — and `skills/sharpen/check-claims.sh`.
  `.githooks/pre-commit` runs them; count them there rather than here. Enable it
  per clone: `git config core.hooksPath .githooks`. A gate named here that this
  repository cannot run is a defect, not a formality — every command in that
  hook has to resolve against the files this repository actually holds.
- `.github/workflows/ci.yml` runs the same gates again, because `core.hooksPath`
  is local config: a fresh clone has the hook on disk and switched off, and that
  looks exactly like having it.
- Nothing here becomes public on its own. Making this repository, a release, or
  anything in it visible happens only on the owner's explicit command at that
  moment (Canon §1).
- No file may contain private residue: run a promotion's sanitization
  discipline on anything you touch. Rules carry `evidence:`, never dated
  incident narratives.
