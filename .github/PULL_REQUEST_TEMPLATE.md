<!--
Nothing is developed in this repository — see CONTRIBUTING.md. Your change is
read here and lands upstream first, then arrives back in the next release. You
will be credited in the release notes.
-->

## What is wrong

<!-- The defect, not the diff. What behaviour is incorrect today? -->

## What this changes

<!-- One or two sentences. -->

## How you know it works

<!-- The command you ran and what it printed. "Should work" means it was not run. -->

## Gates

- [ ] `claude plugin validate . --strict`
- [ ] `./hooks/guard-test.sh`
- [ ] `./skills/sharpen/check-claims.sh`
- [ ] `./hooks/guard-test.sh --mutate` — only if `hooks/bash-guard.sh` or `hooks/cases.tsv` changed

## Checks

- [ ] No project names, paths, credentials or business context of mine are in the diff
- [ ] If this adds a rule, it names a real incident and what it cost
- [ ] If this widens a guard, the reason is in the diff and not only here
