#!/usr/bin/env bash
# Tests hooks/waiver.sh — the record of every deliberate skip.
#
#   hooks/waiver.test.sh
#
# This file is the only evidence that a protocol was skipped on purpose rather
# than forgotten, so the properties that matter are the ones whose failure is
# silent: a line that does not land, a line that lands somewhere nobody looks,
# and a line a caller can forge by putting a newline in its own reason.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
script="$here/waiver.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/waiver-test.XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT

pass=0 fail=0
ok()  { pass=$((pass + 1)); printf '\033[32m✓\033[0m %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '\033[31m✗\033[0m %s — %s\n' "$1" "$2"; }
assert() { if grep -qF -- "$3" <<<"$2"; then ok "$1"; else bad "$1" "expected: $3"; fi; }
refute() { if grep -qF -- "$3" <<<"$2"; then bad "$1" "did not expect: $3"; else ok "$1"; fi; }

printf 'hooks/waiver.sh\n\n'

# --- the line ----------------------------------------------------------------
log="$tmp/one.tsv"
ORRERY_WAIVER_LOG="$log" CLAUDE_CODE_SESSION_ID=abc \
  bash "$script" "gh issue close #99042" "owner said to skip it" command >/dev/null 2>&1
line="$(cat "$log" 2>/dev/null)"

assert "the act is recorded"     "$line" 'gh issue close'
assert "the issue is nameable"   "$line" '#99042'
assert "the reason is recorded"  "$line" 'owner said to skip it'
assert "the source is recorded"  "$line" 'command'
n="$(awk -F'\t' 'END{print NF}' "$log")"
[ "$n" = 5 ] && ok "five tab-separated fields" || bad "five tab-separated fields" "got $n"
grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' "$log" \
  && ok "an ISO-8601 UTC timestamp leads" || bad "an ISO-8601 UTC timestamp leads" "no timestamp"

# The session is hashed, never stored. It correlates waivers within one session
# and identifies nothing outside this machine.
refute "the raw session id is not written" "$line" 'abc'

# --- appending, not replacing -------------------------------------------------
# A file that gets truncated on each write holds the most recent skip and no
# history, which reads as a project that has skipped once.
ORRERY_WAIVER_LOG="$log" bash "$script" "second act" "second reason" >/dev/null 2>&1
c="$(wc -l < "$log" | tr -d ' ')"
[ "$c" = 2 ] && ok "a second waiver appends" || bad "a second waiver appends" "$c lines"
assert "and the first is still there" "$(cat "$log")" 'owner said to skip it'

# --- forgery ------------------------------------------------------------------
# Both fields are free text the caller chose. A newline would end the record
# early and start a second one — a forged row with a chosen timestamp and a
# chosen act, in the one file whose value is that the party it incriminates
# cannot quietly edit it.
#
# The forged row's timestamp is generated rather than written literally.
# `sanitize-scan.sh` refuses a literal date in anything that ships — it cannot
# tell a fixture from a dated incident narrative, and this file ships. A
# generated one is what a forgery would actually carry anyway.
log2="$tmp/forge.tsv"
forged_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ORRERY_WAIVER_LOG="$log2" bash "$script" "act" \
  "$(printf 'real reason\n%s\tdeadbeef\tcommand\tsomething else\tinvented' "$forged_ts")" \
  >/dev/null 2>&1
c="$(wc -l < "$log2" | tr -d ' ')"
[ "$c" = 1 ] && ok "a newline in the reason cannot forge a second row" \
             || bad "a newline in the reason cannot forge a second row" "$c lines"
n="$(awk -F'\t' 'END{print NF}' "$log2")"
[ "$n" = 5 ] && ok "and a tab cannot forge a sixth field" || bad "and a tab cannot forge a sixth field" "got $n"

# --- the refusals -------------------------------------------------------------
# A waiver with no reason records that something was skipped and not why, which
# is the silence this file exists to end.
out="$(ORRERY_WAIVER_LOG="$tmp/none.tsv" bash "$script" "act" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "a waiver with no reason is refused" || bad "a waiver with no reason is refused" "exit $rc"
assert "and says why" "$out" 'A waiver with no reason'
[ -f "$tmp/none.tsv" ] && bad "and writes nothing" "the log was created" || ok "and writes nothing"

out="$(ORRERY_WAIVER_LOG="$tmp/none.tsv" bash "$script" "act" "why" invented 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "an unknown source is refused" || bad "an unknown source is refused" "exit $rc"

# --- where it lands -----------------------------------------------------------
# A relative path resolved against the working directory is how one host project
# collected twenty call logs, as deep as six directories. The root is named or
# the write is refused; there is no third behaviour, because a waiver written
# somewhere nobody will look reads as recorded.
proj="$tmp/proj"; mkdir -p "$proj/sub"
( cd "$proj/sub" && CLAUDE_PROJECT_DIR="$proj" ORRERY_WAIVER_LOG=".claude/w.tsv" \
    bash "$script" "act" "reason" >/dev/null 2>&1 )
[ -f "$proj/.claude/w.tsv" ] && ok "a relative path resolves against the project root" \
                             || bad "a relative path resolves against the project root" "not at the root"
[ -f "$proj/sub/.claude/w.tsv" ] && bad "and not against the working directory" "written under sub/" \
                                 || ok "and not against the working directory"

bare="$tmp/bare"; mkdir -p "$bare"
out="$( cd "$bare" && env -u CLAUDE_PROJECT_DIR ORRERY_WAIVER_LOG="rel.tsv" \
        bash "$script" "act" "reason" 2>&1 )"; rc=$?
[ "$rc" -ne 0 ] && ok "no project root and a relative path is refused" \
               || bad "no project root and a relative path is refused" "exit $rc"
assert "and names what to set" "$out" 'ORRERY_WAIVER_LOG'

printf '\n%s cases, %s failing\n' "$((pass + fail))" "$fail"
[ "$fail" -eq 0 ] || exit 1
