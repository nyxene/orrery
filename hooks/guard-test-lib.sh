#!/usr/bin/env bash
# Shared runner for the guard suites. Sourced by `hooks/bash-guard.test.sh` and
# `hooks/agent-guard.test.sh`; not runnable on its own.
#
# One corpus loop and one mutation pass serve both guards. What differs between
# them is not the machinery but three facts, and each is the caller's to state:
#
#   $CASES        the corpus file
#   $MUTANTS_RE   which lines of the guard are decisions worth mutating
#   payload()     the hook JSON one case becomes — the two guards read
#                 different fields of a different tool's input
#   probes()      the conditions a corpus cannot express, per guard
#
# The alternative was a second copy of both loops. A mutation pass that exists
# twice is a mutation pass that drifts in one copy, silently, in the direction
# of scoring less — and the thing it scores is the only executable defence in
# this library.
#
# The selector matters more than it looks. It is a regex over the guard's own
# text, so a decision line whose spelling it does not match is never mutated and
# never reported: the pass prints `survived=0` having skipped it. That is why
# each caller states its own, beside the guard it belongs to, rather than
# inheriting one written for the other file.

# Prints the number of cases the given guard gets wrong; lists them when VERBOSE.
corpus() { # $1 = guard path
  local fails=0 line want rest f1 f2 out got
  # Split by hand rather than with `IFS=$'\t' read`. Tab is an IFS *whitespace*
  # character, so that form collapses a run of tabs into one delimiter and an
  # empty field silently becomes the next one — which turned every unnamed-spawn
  # case into a spawn named after its own brief, and reported them as real
  # failures of the guard. A corpus that cannot express an empty field cannot
  # test a guard whose first decision is whether a field is empty.
  while IFS= read -r line; do
    want="${line%%$'\t'*}"
    case "$want" in deny|allow) ;; *) continue ;; esac
    rest="${line#*$'\t'}"
    case "$rest" in
      *$'\t'*) f1="${rest%%$'\t'*}"; f2="${rest#*$'\t'}" ;;
      *)       f1="$rest";          f2="" ;;
    esac
    out="$(payload "$f1" "$f2" | bash "$1" 2>/dev/null)"
    got=allow
    grep -q '"deny"' <<<"$out" && got=deny
    if [ "$got" != "$want" ]; then
      fails=$((fails + 1))
      [ -n "${VERBOSE:-}" ] && printf '  want=%-5s got=%-5s %s\n' "$want" "$got" "$f1${f2:+ | $f2}" >&2
    fi
  done < "$CASES"
  echo "$fails"
}

report_probes() { # $1 = guard path, $2 = label, $3 = what the probes cover
  local n; n="$(probes "$1")"
  if [ "$n" -eq 0 ]; then
    printf '\033[32m✓\033[0m %s refuses when it cannot run: %s\n' "$2" "$3"
  else
    printf '\033[31m✗\033[0m %s failed %s fail-closed probe(s) — it fails open\n' "$2" "$n"
  fi
  return "$n"
}

# Blanks one decision line at a time and reruns the corpus and the probes. A
# mutant that still passes both is a line nothing holds — either a missing case
# or a line that does nothing.
#
# What it cannot do: find a check that is not there. A missing branch has no
# line to blank, so the six bypasses in audit round 3 were found adversarially,
# not by this. Mutation score is a claim about the corpus, never about the guard.
mutation_pass() { # $1 = guard path, $2 = scratch file to write mutants to
  local guard="$1" tmp="$2" n ok op killed=0 survived=0 skipped=0
  for n in $(grep -nE "$MUTANTS_RE" "$guard" | cut -d: -f1); do
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
    elif [ $(( $(corpus "$tmp") + $(probes "$tmp") )) -eq 0 ]; then
      printf 'L%-4s SURVIVED  %s\n' "$n" "$(sed -n "${n}p" "$guard" | sed 's/^ *//' | cut -c1-70)"
      survived=$((survived + 1))
    else
      killed=$((killed + 1))
    fi
  done
  printf '\nkilled=%s survived=%s skipped=%s\n' "$killed" "$survived" "$skipped"
  [ "$survived" -eq 0 ]
}
