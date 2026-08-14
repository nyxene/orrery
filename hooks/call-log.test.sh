#!/usr/bin/env bash
# Tests hooks/call-log.sh against its contract.
#
# Named `<script>.test.sh` per the convention decided in the testing umbrella
# issue: a test is named after what it tests and sits beside it, so the pairing
# is visible in a directory listing and a test can never be mistaken for a tool.
# The two older suites predated that decision and were renamed to match, so the
# repository now runs one convention rather than two.
#
# What is worth testing here is not that a line gets written. It is the two
# properties that make this recorder allowed to exist at all: it records no
# content, and it never blocks a tool call. Both are silent when broken.
#
# git exports its own environment into hooks and this file may run as a gate;
# nothing here spawns a repository, but the log path is taken from the
# environment, so the variable is set per case rather than inherited.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
hook="$here/call-log.sh"

pass=0 fail=0
ok()  { pass=$((pass + 1)); printf '\033[32m✓\033[0m %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '\033[31m✗\033[0m %s — %s\n' "$1" "$2"; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/call-log-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# One call through the hook. Prints nothing; the log is the output.
run() { # $1 = log path (empty for unset), $2 = payload JSON
  if [ -n "$1" ]; then ORRERY_CALL_LOG="$1" bash "$hook" <<<"$2" >/dev/null 2>&1
  else env -u ORRERY_CALL_LOG bash "$hook" <<<"$2" >/dev/null 2>&1; fi
  return $?
}

bash_payload='{"session_id":"abc-123","tool_name":"Bash","tool_input":{"command":"rm -rf /Users/someone/secret"}}'
agent_payload='{"session_id":"abc-123","tool_name":"Agent","tool_input":{"subagent_type":"critic","name":"my-reviewer","prompt":"a private brief mentioning /Users/someone"}}'

# --- unset is off, and off costs nothing -----------------------------------
log="$tmp/unset.log"
run "" "$bash_payload"
if [ ! -e "$log" ] && [ -z "$(find "$tmp" -name '*.log' 2>/dev/null)" ]; then
  ok "no ORRERY_CALL_LOG means no file is created"
else
  bad "no ORRERY_CALL_LOG means no file is created" "something was written anyway"
fi

# --- a call is recorded, with the fields the analysis needs ----------------
log="$tmp/a.log"
run "$log" "$bash_payload"
line="$(head -1 "$log" 2>/dev/null || true)"
if [ -z "$line" ]; then
  bad "a Bash call is recorded" "nothing was written to $log"
elif [ "$(awk -F'\t' '{print NF}' <<<"$line")" -ne 5 ]; then
  bad "a Bash call is recorded" "expected 5 tab-separated fields, got: $line"
elif [ "$(cut -f3 <<<"$line")" != "Bash" ]; then
  bad "a Bash call is recorded" "tool field is not Bash: $line"
else
  ok "a Bash call is recorded, five fields"
fi

# --- the content is NOT recorded -------------------------------------------
# The property the whole design rests on. Both payloads above carry a command, a
# prompt, a home path and a chosen agent name; none may reach the file.
log="$tmp/b.log"
run "$log" "$bash_payload"
run "$log" "$agent_payload"
leak=""
for needle in 'rm -rf' 'secret' '/Users/someone' 'private brief' 'my-reviewer'; do
  grep -qF "$needle" "$log" 2>/dev/null && leak="$leak $needle"
done
if [ -z "$leak" ]; then ok "no command, prompt, path or agent name reaches the log"
else bad "no command, prompt, path or agent name reaches the log" "leaked:$leak"; fi

# --- one call is one line, whatever the caller supplies ---------------------
# `subagent_type` is free text the model chooses, and the record's separators are
# a tab and a newline. A newline in that field used to end the record early and
# begin another: one Agent spawn wrote two lines, the second a complete forgery
# with a chosen timestamp, a chosen fingerprint and a chosen tool. A log that the
# subject of the log can write into is not evidence about the subject.
#
# The forged first field is a marker rather than a date. A real timestamp here
# reads as a dated incident narrative to `tools/sanitize-scan.sh`, which refused
# the release that shipped this file — and the assertion never needed a date: it
# checks that the caller could not choose the field, whatever was put in it.
forge_log="$tmp/forge.log"
forged_payload="$(jq -nc --arg a "$(printf 'critic\nFORGED-STAMP\tdeadbeef\tBash\t-\tno')" \
  '{tool_name:"Agent", session_id:"abc-123", tool_input:{subagent_type:$a}}')"
run "$forge_log" "$forged_payload"
lines="$(grep -c . "$forge_log" 2>/dev/null || echo 0)"
if [ "$lines" -ne 1 ]; then
  bad "one call writes exactly one line" "wrote $lines lines: $(cat "$forge_log")"
elif [ "$(cut -f1 < "$forge_log")" = "FORGED-STAMP" ]; then
  bad "one call writes exactly one line" "the caller chose the timestamp field"
else
  ok "one call writes exactly one line, and the caller cannot choose a field"
fi

# --- the session id is fingerprinted, not stored ---------------------------
if grep -qF 'abc-123' "$log" 2>/dev/null; then
  bad "the session id is hashed rather than written" "the raw session id is in the file"
else
  ok "the session id is hashed rather than written"
fi

# --- but it still correlates: two calls in one session share a fingerprint --
if [ "$(cut -f2 "$log" | sort -u | wc -l | tr -d ' ')" = "1" ]; then
  ok "two calls in one session share one fingerprint"
else
  bad "two calls in one session share one fingerprint" "fingerprints differ, so nothing can be correlated"
fi

# --- a named spawn records that it was named, and its type -----------------
aline="$(grep -P '\tAgent\t' "$log" 2>/dev/null || grep '	Agent	' "$log" 2>/dev/null || true)"
if [ "$(cut -f4 <<<"$aline")" = "critic" ] && [ "$(cut -f5 <<<"$aline")" = "yes" ]; then
  ok "an agent spawn records its type and that it was named"
else
  bad "an agent spawn records its type and that it was named" "got: $aline"
fi

# --- it never blocks a tool call -------------------------------------------
# A recorder that denies has done more damage than a missing line is worth. The
# guards in this directory print a deny JSON; this one must print nothing and
# exit 0, including when it cannot possibly work.
out="$(ORRERY_CALL_LOG="$tmp/c.log" bash "$hook" <<<"$bash_payload" 2>/dev/null)"
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then ok "a recorded call prints nothing and exits 0"
else bad "a recorded call prints nothing and exits 0" "rc=$rc out=$out"; fi

out="$(ORRERY_CALL_LOG=/proc/nonexistent/deep/x.log bash "$hook" <<<"$bash_payload" 2>/dev/null)"
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then ok "an unwritable log path still exits 0 and blocks nothing"
else bad "an unwritable log path still exits 0 and blocks nothing" "rc=$rc out=$out"; fi

out="$(ORRERY_CALL_LOG="$tmp/d.log" bash "$hook" <<<'not json at all' 2>/dev/null)"
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then ok "a payload that is not JSON exits 0 and blocks nothing"
else bad "a payload that is not JSON exits 0 and blocks nothing" "rc=$rc out=$out"; fi

# --- the log is bounded ----------------------------------------------------
# Without this it grows forever in somebody else's repository.
log="$tmp/big.log"
i=0
while [ "$i" -lt 400 ]; do
  printf 'x%.0s' $(seq 1 40) >> "$log"; printf '\n' >> "$log"
  i=$((i + 1))
done
before="$(wc -c < "$log" | tr -d ' ')"
ORRERY_CALL_LOG="$log" ORRERY_CALL_LOG_MAX=4096 bash "$hook" <<<"$bash_payload" >/dev/null 2>&1
after="$(wc -c < "$log" | tr -d ' ')"
if [ "$after" -lt "$before" ]; then ok "the log is trimmed once it passes its size cap"
else bad "the log is trimmed once it passes its size cap" "before=$before after=$after"; fi

# --- purge empties it and says so ------------------------------------------
log="$tmp/p.log"
run "$log" "$bash_payload"
msg="$(ORRERY_CALL_LOG="$log" bash "$hook" --purge 2>&1)"
if [ -f "$log" ] && [ ! -s "$log" ] && grep -q 'purged' <<<"$msg"; then
  ok "--purge empties the log and reports what it removed"
else
  bad "--purge empties the log and reports what it removed" "msg=$msg size=$(wc -c < "$log" 2>/dev/null)"
fi

printf '\n%s cases, %s passing, %s failing\n' "$((pass + fail))" "$pass" "$fail"
[ "$fail" -eq 0 ]
