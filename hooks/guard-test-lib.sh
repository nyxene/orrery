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

# Reads `git diff -U0` on stdin and prints the new-side line numbers it touches,
# one per line. A hunk header is `@@ -a[,b] +c[,d] @@`: an omitted length means
# one line, and `,0` means the hunk only deleted, so it touches no new line.
# Reading an omitted length as zero is the classic slip — it yields no lines,
# no mutants and a green pass — which is why the suite checks every form.
changed_lines() {
  local start len i
  sed -n 's/^@@ -[0-9,]* +\([0-9][0-9]*\)\(,\([0-9][0-9]*\)\)\{0,1\} @@.*/\1 \3/p' |
  while read -r start len; do
    [ -n "$len" ] || len=1
    i=0
    while [ "$i" -lt "$len" ]; do echo $((start + i)); i=$((i + 1)); done
  done
}

# Prints the number of cases the given guard gets wrong; lists them when VERBOSE.
# Under STOP_AT_FIRST it returns at the first wrong case: the mutation pass needs
# only whether a mutant is killed, and the rest of the corpus after that answer
# was most of the pass's time.
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
      [ -n "${STOP_AT_FIRST:-}" ] && break
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
#
# MUTATE_LINES, when set, narrows the pass to the candidate lines it names — the
# pre-commit mode, where only what the change touched is worth minutes. Unset
# means every candidate, which is what CI and a manual `--mutate` run.
#
# MUTATE_JOBS runs that many mutants at once, each in its own file, in batches
# (bash 3.2 has no `wait -n`). Default 1. Only a guard that keeps no state
# between invocations may run in parallel, so process-guard's suite pins 1
# whatever the environment says: its gate file would be shared by every mutant.
mutant_verdict() { # $1 = guard, $2 = line, $3 = mutant file — prints one verdict word
  local op
  # Three operators, first one that both changes the line and keeps the file
  # parseable. Neutralising a grep is preferred over blanking, because blanking
  # a line inside a multi-line condition is a syntax error, not a mutant.
  for op in 's/grep -q[^;\\]*/false /' 's/grep -q[a-zA-Z]* .*<<<"[^"]*"/false/' 's/.*/:/'; do
    sed "${2}${op}" "$1" > "$3"
    cmp -s "$3" "$1" && continue
    bash -n "$3" 2>/dev/null || continue
    if [ "$(STOP_AT_FIRST=1 corpus "$3")" -eq 0 ] && [ "$(probes "$3")" -eq 0 ]; then
      echo SURVIVED
    else
      echo KILLED
    fi
    return
  done
  echo SKIP
}

mutation_pass() { # $1 = guard path, $2 = scratch file to write mutants to
  local guard="$1" tmp="$2" n v killed=0 survived=0 skipped=0 all=0 tried=0
  local jobs="${MUTATE_JOBS:-1}" lines="" batch=0 f
  for n in $(grep -nE "$MUTANTS_RE" "$guard" | cut -d: -f1); do
    all=$((all + 1))
    if [ -n "${MUTATE_LINES+set}" ]; then
      case " $MUTATE_LINES " in *" $n "*) ;; *) continue ;; esac
    fi
    tried=$((tried + 1))
    lines="$lines $n"
    # One at a time the mutant sits exactly at the path the caller named,
    # which process-guard's probe 0 pins; side by side each needs its own.
    f="$tmp"; [ "$jobs" -gt 1 ] && f="$tmp.$n"
    mutant_verdict "$guard" "$n" "$f" > "$tmp.$n.v" &
    batch=$((batch + 1))
    [ "$batch" -ge "$jobs" ] && { wait; batch=0; }
  done
  wait
  for n in $lines; do
    v="$(cat "$tmp.$n.v")"
    rm -f "$tmp.$n.v"; [ "$jobs" -gt 1 ] && rm -f "$tmp.$n"
    case "$v" in
      KILLED) killed=$((killed + 1)); continue ;;
      SURVIVED) survived=$((survived + 1)) ;;
      *) v=SKIP; skipped=$((skipped + 1)) ;;
    esac
    printf 'L%-4s %-9s %s\n' "$n" "$v" "$(sed -n "${n}p" "$guard" | sed 's/^ *//' | cut -c1-70)"
  done
  printf '\nkilled=%s survived=%s skipped=%s\n' "$killed" "$survived" "$skipped"
  [ -z "${MUTATE_LINES+set}" ] \
    || printf 'mutated %s of %s candidates — the lines this change touched; the full pass runs in CI\n' "$tried" "$all"
  [ "$survived" -eq 0 ]
}
