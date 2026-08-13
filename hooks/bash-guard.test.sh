#!/usr/bin/env bash
# Runs `hooks/cases.tsv` against `hooks/bash-guard.sh`.
#
#   hooks/bash-guard.test.sh            run the corpus, report failures
#   hooks/bash-guard.test.sh --mutate   also run the mutation pass
#
# The header used to say "against the guards", plural, and that was the last
# document in the repository still claiming the Agent guard was covered here. It
# has its own suite now: `hooks/agent-guard.test.sh`. The loops both files use
# live in `hooks/guard-test-lib.sh`.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
guard="$here/bash-guard.sh"
CASES="$here/cases.tsv"
# Which lines of the guard are decisions. Read `guard-test-lib.sh` before
# changing it: a decision whose spelling this misses is never mutated, and the
# pass reports `survived=0` without ever having tried it.
MUTANTS_RE='grep -q|deny "|sys_danger=1|resolved='
tmp="${TMPDIR:-/tmp}/orrery-bash-guard-test.$$"
# A PATH shadow holding one fake `uname`, so the unmodelled-platform branch can
# be exercised as written rather than by asking the guard to pretend.
fakebin="$tmp.bin"
trap 'rm -rf "$tmp" "$fakebin"' EXIT
mkdir -p "$fakebin"
printf '#!/bin/sh\necho Plan9\n' > "$fakebin/uname"
chmod +x "$fakebin/uname"

# shellcheck source=hooks/guard-test-lib.sh
. "$here/guard-test-lib.sh"

# The corpus is written for a session whose cwd is the repo, on any machine:
# `{ROOT}` and `{SCRATCH}` are substituted here, and the guard runs from the
# repo root — a literal absolute path in a case is a bug this file once had.
root="$(cd "$here/.." && pwd -P)"
if [ "$(uname)" = "Darwin" ]; then
  scratch="/private/tmp/claude-$(id -u)"
else
  scratch="/tmp/claude-$(id -u)"
fi

# The deletion cases say "outside the session scratchpad", and a relative target
# is resolved against the guard's working directory — so a tree that lives
# *inside* the scratchpad makes twenty of them assert the opposite of what they
# read, and they do it by passing. Not hypothetical: it is where the promotion
# door used to assemble the product tree, and the corpus was found there
# measuring the checkout's location rather than the guard.
#
# Refusing is the honest answer, and moving the cases elsewhere is not: a shell
# whose working directory is outside the sandbox's writable set cannot open a
# here-document at all, so the runner itself stops working before the corpus
# does. What assembles a tree has to assemble it somewhere real.
if [ "${root#"$scratch"/}" != "$root" ]; then
  printf '\033[31m✗\033[0m this tree is inside the session scratchpad (%s).\n' "$scratch" >&2
  printf '  Every deletion case resolves inside it and passes for the wrong reason.\n' >&2
  printf '  Run the suite from a checkout outside the scratchpad.\n' >&2
  exit 1
fi
cd "$root"

# The scratchpad root has to exist, or one whole branch of the guard is never
# reached and the case that pins it passes for the wrong reason.
#
# Section 3b resolves a delete target physically — `cd "$(dirname ...)" && pwd -P`
# — and falls back to collapsing `..` textually only when that `cd` fails. The
# case `rm -rf {SCRATCH}/../x` exists to pin the physical branch: unresolved, the
# path still starts with the scratchpad prefix and would be allowed, so blanking
# the resolution line must turn it red.
#
# On a machine that has run sessions the root is simply there, so it did. On a
# clean runner it is not: the `cd` fails, the textual fallback runs instead, both
# spellings land outside the scratchpad, and the mutant survives. Found on CI the
# day after CI was added, on the very file whose earlier version produced
# `rules/craft/gates-must-run-where-nobody-works.md` — that rule was written for
# the guard refusing a scratchpad that did not exist yet; this is its corpus
# depending on one that does.
#
# Created, never removed: on a developer machine this is the live session's own
# scratchpad, and a test suite does not delete the caller's working state.
mkdir -p "$scratch"

# One case is one command string, and the substitutions belong here rather than
# in the shared loop: only this corpus has a repo root and a scratchpad in it.
payload() { # $1 = command, $2 = unused (the third column is a note)
  local cmd="$1"
  cmd="${cmd//\{ROOT\}/$root}"
  cmd="${cmd//\{SCRATCH\}/$scratch}"
  # `\n` becomes a real newline, so a case can be a heredoc or any other
  # multi-line command. One case per line is what keeps this file readable, and
  # until now it also meant the guard's handling of multi-line input could not
  # be pinned at all — which is how a heredoc's body came to be segmented as if
  # it were shell, unnoticed, until it refused four read-only commands.
  cmd="${cmd//\\n/$'\n'}"
  cmd="${cmd//\\t/$'\t'}"
  jq -n --arg c "$cmd" '{tool_input:{command:$c}}'
}

# Conditions the corpus cannot express, because its runner builds valid JSON by
# construction and every case is a command string. Both are about the guard
# failing to *work* rather than judging wrongly: the harness reads a non-zero
# hook exit as a non-blocking error and runs the command anyway, so a guard that
# falls over — or one running somewhere it does not understand, where no pattern
# in it can match — is a guard that let something through.
#
# Counted rather than printed, so the mutation pass can score them too. A line
# only the corpus scores is a line these probes cannot pin, and the
# unmodelled-platform branch is reachable from nowhere else.
probes() { # $1 = guard path — prints how many it gets wrong
  local fails=0 out
  out="$(printf 'not json at all' | bash "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" || fails=$((fails + 1))
  out="$(jq -n '{tool_input:{command:"ls"}}' \
    | PATH="$fakebin:$PATH" bash "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" || fails=$((fails + 1))
  echo "$fails"
}

trap_fails=0
report_probes "$guard" "the Bash guard" "bad input, unknown platform" \
  || trap_fails=$((trap_fails + $?))

total="$(grep -cE '^(deny|allow)	' "$CASES")"
fails="$(VERBOSE=1 corpus "$guard")"
printf '%s cases, %s failing\n' "$total" "$fails"

if [ "${1:-}" != "--mutate" ]; then
  [ "$fails" -eq 0 ] && [ "$trap_fails" -eq 0 ] || exit 1
  exit 0
fi

[ "$fails" -eq 0 ] || { echo "corpus is red; fix it before mutating" >&2; exit 1; }

echo
mutation_pass "$guard" "$tmp"
