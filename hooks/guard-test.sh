#!/usr/bin/env bash
# Runs `hooks/cases.tsv` against the guards.
#
#   hooks/guard-test.sh            run the corpus, report failures
#   hooks/guard-test.sh --mutate   also run the mutation pass
#
# The mutation pass blanks one decision line of `bash-guard.sh` at a time and
# reruns the corpus. A mutant the corpus still fully passes is a line no case
# holds — every such survivor is either a missing case or a line that does
# nothing. This is the check `verify` demands of any test suite, applied to the
# one part of this library that executes.
#
# What it cannot do: find a check that is not there. A missing branch has no
# line to blank, so the six bypasses in audit round 3 were found adversarially,
# not by this. Mutation score is a claim about the corpus, never about the guard.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
guard="$here/bash-guard.sh"
cases="$here/cases.tsv"
tmp="${TMPDIR:-/tmp}/orrery-guard-test.$$"
trap 'rm -f "$tmp"' EXIT

# The corpus is written for a session whose cwd is the repo, on any machine:
# `{ROOT}` and `{SCRATCH}` are substituted here, and the guard runs from the
# repo root — a literal absolute path in a case is a bug this file once had.
root="$(cd "$here/.." && pwd -P)"
cd "$root"
if [ "$(uname)" = "Darwin" ]; then
  scratch="/private/tmp/claude-$(id -u)"
else
  scratch="/tmp/claude-$(id -u)"
fi

# Prints the number of cases the given guard gets wrong; lists them when VERBOSE.
corpus() {
  local fails=0 want cmd out got
  while IFS=$'\t' read -r want cmd _; do
    case "$want" in ''|'#'*) continue ;; esac
    [ -z "${cmd:-}" ] && continue
    cmd="${cmd//\{ROOT\}/$root}"
    cmd="${cmd//\{SCRATCH\}/$scratch}"
    # `\n` becomes a real newline, so a case can be a heredoc or any other
    # multi-line command. One case per line is what keeps this file readable, and
    # until now it also meant the guard's handling of multi-line input could not
    # be pinned at all — which is how a heredoc's body came to be segmented as if
    # it were shell, unnoticed, until it refused four read-only commands.
    cmd="${cmd//\\n/$'\n'}"
    cmd="${cmd//\\t/$'\t'}"
    out="$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}' | bash "$1" 2>/dev/null)"
    got=allow
    grep -q '"deny"' <<<"$out" && got=deny
    if [ "$got" != "$want" ]; then
      fails=$((fails + 1))
      [ -n "${VERBOSE:-}" ] && printf '  want=%-5s got=%-5s %s\n' "$want" "$got" "$cmd" >&2
    fi
  done < "$cases"
  echo "$fails"
}

total="$(grep -cE '^(deny|allow)	' "$cases")"
fails="$(VERBOSE=1 corpus "$guard")"
printf '%s cases, %s failing\n' "$total" "$fails"

if [ "${1:-}" != "--mutate" ]; then
  [ "$fails" -eq 0 ] || exit 1
  exit 0
fi

[ "$fails" -eq 0 ] || { echo "corpus is red; fix it before mutating" >&2; exit 1; }

echo
killed=0 survived=0 skipped=0
for n in $(grep -nE 'grep -q|deny "|sys_danger=1|resolved=' "$guard" | cut -d: -f1); do
  ok=0
  # Three operators, first one that both changes the line and keeps the file
  # parseable. Neutralising a grep is preferred over blanking, because blanking
  # a line inside a multi-line condition is a syntax error, not a mutant.
  for op in 's/grep -q[^;\\]*/false /' 's/grep -q[a-zA-Z]* .*<<<"[^"]*"/false/' 's/.*/:/'; do
    sed "${n}${op}" "$guard" > "$tmp"
    cmp -s "$tmp" "$guard" && continue
    bash -n "$tmp" 2>/dev/null && { ok=1; break; }
  done
  if [ "$ok" -eq 0 ]; then
    printf 'L%-4s SKIP      %s\n' "$n" "$(sed -n "${n}p" "$guard" | sed 's/^ *//' | cut -c1-70)"
    skipped=$((skipped + 1))
  elif [ "$(corpus "$tmp")" -eq 0 ]; then
    printf 'L%-4s SURVIVED  %s\n' "$n" "$(sed -n "${n}p" "$guard" | sed 's/^ *//' | cut -c1-70)"
    survived=$((survived + 1))
  else
    killed=$((killed + 1))
  fi
done

printf '\nkilled=%s survived=%s skipped=%s\n' "$killed" "$survived" "$skipped"
[ "$survived" -eq 0 ]
