# Contributing

Thank you for looking. Orrery is small, opinionated, and shaped by incidents
rather than by preference — reading this page first will save you a rewrite.

## The one thing that surprises people

**Nothing is developed in this repository.** It is the released product of a
private workshop, and its contents arrive by promotion: every file here is
either shipped verbatim from the workshop or rewritten for you deliberately.
A pull request is welcome and will be read, but it lands upstream first and
arrives back here in the next release — so your commit is not what appears in
the history. You will be credited in the release notes.

If that trade is not what you expected, an issue is often the better tool: it
costs you less and reaches the same place.

## What is most useful

| | |
|---|---|
| **A friction report** | A skill that fired when it should not have, a guard that refused something reasonable, a rule whose advice was wrong in your context. This is the highest-value contribution and the hardest to get any other way. |
| **A bug** | A hook that errors, a script that fails on your OS, a path that does not resolve. |
| **A rule that cost you something** | Rules here exist because something broke. If you have one with a real incident behind it, say what happened and what it cost — that is the part that makes it a rule rather than advice. |
| **Documentation that was wrong** | If a sentence here made you do the wrong thing, that is a defect. |

## What will be declined, and why

- **General best practices.** Every rule in `rules/` traces to an incident. A
  rule with no incident is advice, and advice does not survive contact with a
  session that disagrees with it.
- **Configurability nobody asked for.** Canon §4. An option with one caller is
  a maintenance cost with no reader.
- **A second way to do something that already works.** Two paths to one outcome
  is the failure this library is built to prevent.
- **Anything that makes a guard permissive by default.** The guards fail closed
  on purpose; widening one needs an argument, not a patch.

## Before you open a pull request

Enable the gates — they are in the repository but switched off in a fresh
clone, which looks exactly like having them:

```bash
git config core.hooksPath .githooks
```

Then make sure they pass:

```bash
claude plugin validate . --strict
./hooks/bash-guard.test.sh
./hooks/agent-guard.test.sh --mutate
./hooks/canon-loader.test.sh
./hooks/rules-loader.test.sh
./hooks/handoff-prompt.test.sh
./skills/sharpen/check-claims.sh
```

The Agent guard's mutation pass is in that list because it costs seconds. The
Bash guard's does not: if you changed `hooks/bash-guard.sh`, `hooks/cases.tsv`
or the shared `hooks/guard-test-lib.sh`, run it too. It takes minutes, and it is
the only thing that proves the corpus still pins the guard rather than merely
running beside it:

```bash
./hooks/bash-guard.test.sh --mutate
```

`jq` must be on `PATH` before any hook fires.

## Commits

Conventional commits, `type(scope): subject`. Write the subject as the thing
that was wrong, not the thing you did — `fix(guard): a trailing flag skipped the
segment` reads better a year later than `fix guard bug`.

## Reporting something sensitive

Do not open an issue for a security problem. [SECURITY.md](SECURITY.md) has the
private channel.

## Conduct

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).
