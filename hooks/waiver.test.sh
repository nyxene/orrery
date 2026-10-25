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

while IFS='=' read -r _var _; do unset "$_var"; done < <(env | grep '^GIT_')
tmp="$(mktemp -d "${TMPDIR:-/tmp}/waiver-test.XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT
tmp="$(cd "$tmp" && pwd -P)"

# A new repository; prints the path its waiver log will have.
fresh() { mkdir -p "$tmp/$1" && git -C "$tmp/$1" init -q -b main
  git -C "$tmp/$1" config user.email t@example.invalid; git -C "$tmp/$1" config user.name t; printf '%s/.orrery/local/waivers.tsv' "$tmp/$1"; }
# waiver.sh run from inside the log's repository.
w() { local r="${1%/.orrery/local/waivers.tsv}"; shift; ( cd "$r" && env -u ORRERY_WAIVER_LOG bash "$script" "$@" ); }

pass=0 fail=0
ok()  { pass=$((pass + 1)); printf '\033[32m✓\033[0m %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '\033[31m✗\033[0m %s — %s\n' "$1" "$2"; }
assert() { if grep -qF -- "$3" <<<"$2"; then ok "$1"; else bad "$1" "expected: $3"; fi; }
refute() { if grep -qF -- "$3" <<<"$2"; then bad "$1" "did not expect: $3"; else ok "$1"; fi; }

printf 'hooks/waiver.sh\n\n'

# --- the line ----------------------------------------------------------------
log="$(fresh one)"
CLAUDE_CODE_SESSION_ID=abc w "$log" "gh issue close #99042" "owner said to skip it" command >/dev/null 2>&1
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
w "$log" "second act" "second reason" >/dev/null 2>&1
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
log2="$(fresh forge)"
forged_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
w "$log2" "act" \
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
none="$(fresh none)"
out="$(w "$none" "act" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "a waiver with no reason is refused" || bad "a waiver with no reason is refused" "exit $rc"
assert "and says why" "$out" 'A waiver with no reason'
[ -f "$none" ] && bad "and writes nothing" "the log was created" || ok "and writes nothing"

out="$(w "$none" "act" "why" invented 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "an unknown source is refused" || bad "an unknown source is refused" "exit $rc"

# --- where it lands -----------------------------------------------------------
# A path resolved against the working directory is how one host project
# collected twenty call logs, as deep as six directories. The place is named by
# git or the write is refused; there is no third behaviour, because a waiver
# written somewhere nobody will look reads as recorded.
proj="$tmp/proj"; mkdir -p "$proj/sub"; git -C "$proj" init -q -b main
git -C "$proj" config user.email t@example.invalid; git -C "$proj" config user.name t
( cd "$proj/sub" && env -u ORRERY_WAIVER_LOG bash "$script" "act" "reason" >/dev/null 2>&1 )
[ -f "$proj/.orrery/local/waivers.tsv" ] && ok "it lands in the main checkout's .orrery/local/" \
  || bad "it lands in the main checkout's .orrery/local/" "not there"
[ -e "$proj/sub/.orrery" ] && bad "and not under the working directory" "written under sub/" \
  || ok "and not under the working directory"

bare="$tmp/bare"; mkdir -p "$bare"
out="$( cd "$bare" && bash "$script" "act" "reason" 2>&1 )"; rc=$?
[ "$rc" -ne 0 ] && ok "outside a repository it is refused" \
               || bad "outside a repository it is refused" "exit $rc"
assert "and says why" "$out" 'not inside a git repository'

# --- an upgrade keeps the history --------------------------------------------
up="$(fresh up)"; mkdir -p "$tmp/up/.claude"; printf 'OLD-WAIVER\n' > "$tmp/up/.claude/orrery-waivers.tsv"
w "$up" "act" "reason" >/dev/null 2>&1
assert "the old waivers are carried over on the first write" "$(head -1 "$up" 2>/dev/null)" 'OLD-WAIVER'
assert "and the old file is left for a rollback" "$(cat "$tmp/up/.claude/orrery-waivers.tsv")" 'OLD-WAIVER'

printf '\n%s cases, %s failing\n' "$((pass + fail))" "$fail"
[ "$fail" -eq 0 ] || exit 1
