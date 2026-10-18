#!/usr/bin/env bash
# Runs `hooks/agent-cases.tsv` against `hooks/agent-guard.sh`.
#
#   hooks/agent-guard.test.sh            run the corpus, report failures
#   hooks/agent-guard.test.sh --mutate   also run the mutation pass
#
# This guard runs before every subagent spawn and had one assertion — that it
# refuses when it cannot parse its own input — while three documents said it had
# a corpus. The loops are shared with the Bash guard's suite and live in
# `hooks/guard-test-lib.sh`; what is stated here is what makes this guard
# different: the shape of the payload, the lines worth mutating, and the two
# ways it must refuse rather than judge.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
guard="$here/agent-guard.sh"
CASES="$here/agent-cases.tsv"
# The decision lines. The Bash guard's selector does not fit here: this guard
# decides with `jq -r` extractions and a `-z` test as much as with greps, and a
# selector that named only greps would skip half the file and still print
# `survived=0`.
MUTANTS_RE='grep -q|jq -r|\[ -z "\$name"'
tmp="${TMPDIR:-/tmp}/orrery-agent-guard-test.$$"
# A PATH with no `jq` in it, so the missing-jq branch is exercised as written.
# `cat` and `bash` are the only other things the guard reaches before it gives
# up, so they are the only things this shadow has to carry.
fakebin="$tmp.bin"
trap 'rm -rf "$tmp" "$tmp".* "$fakebin"' EXIT
mkdir -p "$fakebin"
ln -s "$(command -v cat)" "$fakebin/cat"
ln -s "$(command -v bash)" "$fakebin/bash"

# shellcheck source=hooks/guard-test-lib.sh
. "$here/guard-test-lib.sh"

# An unnamed spawn is not a spawn carrying an empty name: the harness omits the
# field, and `.tool_input.name // empty` is what reads it. Building the empty
# case as `{"name": ""}` would exercise a different line of jq than the one that
# runs in a session.
payload() { # $1 = agent name, $2 = brief
  if [ -z "$1" ]; then
    jq -n --arg p "$2" '{tool_input:{prompt:$p}}'
  else
    jq -n --arg n "$1" --arg p "$2" '{tool_input:{name:$n,prompt:$p}}'
  fi
}

# What a corpus of names and briefs cannot express. Both are the same failure —
# the guard not working rather than judging wrongly — and both are the expensive
# one: the harness reads a non-zero hook exit as a non-blocking error and spawns
# the agent anyway, so a guard that falls over is a guard that let it through.
probes() { # $1 = guard path — prints how many it gets wrong
  local fails=0 out
  out="$(printf 'not json at all' | bash "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" || fails=$((fails + 1))
  out="$(jq -n '{tool_input:{name:"reviewer",prompt:"no send here"}}' \
    | PATH="$fakebin" "$fakebin/bash" "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" || fails=$((fails + 1))
  # A real refusal carries the rule that governs refusals; the rule file is not
  # loaded at this moment, so this sentence is the only place it arrives.
  out="$(jq -n '{tool_input:{name:"reviewer",prompt:"no send here"}}' | bash "$1" 2>/dev/null || true)"
  grep -q "the person's to rule on" <<<"$out" || fails=$((fails + 1))
  echo "$fails"
}

trap_fails=0
report_probes "$guard" "the Agent guard" "bad input, no jq, the refusal rule" \
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
