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
elif [ "$(awk -F'\t' '{print NF}' <<<"$line")" -ne 7 ]; then
  bad "a Bash call is recorded" "expected 7 tab-separated fields, got: $line"
elif [ "$(cut -f3 <<<"$line")" != "Bash" ]; then
  bad "a Bash call is recorded" "tool field is not Bash: $line"
elif [ "$(cut -f6 <<<"$line")" != "call" ]; then
  bad "a Bash call is recorded" "event field is not 'call': $line"
else
  ok "a Bash call is recorded, seven fields"
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

# --- the pair, which is the only thing that says a call ran ----------------
# Before this the log recorded intent and never outcome: a refused call and a
# completed one were byte-identical rows. PostToolUse fires only on success and
# carries the same tool_use_id, so a `call` with no `ran` did not run — and that
# holds for every cause at once, with no list of causes to leave something off.

pre='{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"Bash","tool_use_id":"tu_777","tool_input":{"command":"ls"}}'
post='{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"Bash","tool_use_id":"tu_777","tool_input":{"command":"ls"}}'

log="$tmp/pair.log"
run "$log" "$pre"
run "$log" "$post"
ev="$(cut -f6 "$log" | tr '\n' ' ')"
ids="$(cut -f7 "$log" | sort -u | tr '\n' ' ')"
if [ "$ev" != "call ran " ]; then
  bad "a completed call writes call then ran" "events: $ev"
elif [ "$ids" != "tu_777 " ]; then
  bad "both halves carry the same tool_use_id" "ids: $ids"
else
  ok "a completed call writes call then ran, both under one tool_use_id"
fi

# A refused call is the pre with no post, which is the state this whole change
# exists to make visible. Asserted as the absence, because that is how it will
# be read.
log="$tmp/refused.log"
run "$log" "$pre"
if [ "$(wc -l < "$log" | tr -d ' ')" -eq 1 ] && [ "$(cut -f6 "$log")" = call ]; then
  ok "a call that never completes leaves one unpaired call line"
else
  bad "a call that never completes leaves one unpaired call line" "$(cat "$log")"
fi

# --- the two ways the event field can be wrong ------------------------------

# Absent: this hook fails open, the field is newer than the log, and going
# silent because one key moved is worse than mislabelling.
log="$tmp/noevent.log"
run "$log" '{"session_id":"s2","tool_name":"Bash","tool_input":{"command":"ls"}}'
if [ "$(cut -f6 "$log" 2>/dev/null)" = call ]; then
  ok "a payload with no hook_event_name is still recorded, as a call"
else
  bad "a payload with no hook_event_name is still recorded" "$(cat "$log" 2>/dev/null)"
fi

# Present and unrecognised: someone registered a third event and did not teach
# this file. Recording it unlabelled would have every reader count it as a call.
log="$tmp/unknown.log"
run "$log" '{"session_id":"s3","hook_event_name":"Nonesuch","tool_name":"Bash","tool_input":{"command":"ls"}}'
if [ ! -s "$log" ]; then
  ok "an unrecognised hook event records nothing rather than an unlabelled row"
else
  bad "an unrecognised hook event records nothing" "$(cat "$log")"
fi

# --- the id cannot break the line either ------------------------------------
# The forgery case, one field further right. `subagent_type` already has its own
# case; this is the same law applied to a field nobody expects to be hostile,
# because "harness-supplied" is an assumption and the property is not.
log="$tmp/forge-id.log"
run "$log" "$(jq -nc '{session_id:"s4",hook_event_name:"PreToolUse",tool_name:"Bash",
                       tool_use_id:"tu_1\nFORGED\tx\ty\tz\tcall\ttu_2",tool_input:{command:"ls"}}')"
if [ "$(wc -l < "$log" | tr -d ' ')" -eq 1 ] && ! grep -q FORGED <<<"$(cut -f1 "$log")"; then
  ok "a newline inside tool_use_id cannot write a second line"
else
  bad "a newline inside tool_use_id cannot write a second line" "$(cat "$log")"
fi

# --- a relative path belongs to the project, not to the working directory ---
# The defect this file was written to prevent a repeat of. Every install sets a
# relative path, because the install guide recommends one, and this hook used to
# resolve it against whatever directory the tool call ran in — so every `cd` into
# a subdirectory started a new log there. One host project accumulated twenty,
# and a `.gitignore` line anchored to the repository root did not cover them.

proj="$tmp/proj"; mkdir -p "$proj/sub/deeper"
rel='.claude/orrery-calls.tsv'
evt='{"session_id":"r1","hook_event_name":"PreToolUse","tool_name":"Bash","tool_use_id":"r_1","tool_input":{"command":"ls"}}'

for d in "$proj" "$proj/sub" "$proj/sub/deeper"; do
  ( cd "$d" && env ORRERY_CALL_LOG="$rel" CLAUDE_PROJECT_DIR="$proj" bash "$hook" <<<"$evt" >/dev/null 2>&1 )
done
found="$(cd "$proj" && find . -name orrery-calls.tsv | sort | tr '\n' ' ')"
if [ "$found" != "./.claude/orrery-calls.tsv " ]; then
  bad "a relative path resolves against the project, from any working directory" "found: $found"
elif [ "$(wc -l < "$proj/.claude/orrery-calls.tsv" | tr -d ' ')" -ne 3 ]; then
  bad "all three calls land in the one file" "$(cat "$proj/.claude/orrery-calls.tsv")"
else
  ok "three calls from three directories write one file at the project root"
fi

# Nothing to resolve against: record nothing rather than somewhere. This hook
# fails open everywhere else, and deliberately does not here — a missing line
# costs a line, a file in someone's source tree is damage they have to find.
lost="$tmp/lost"; mkdir -p "$lost/sub"
( cd "$lost/sub" && env -u CLAUDE_PROJECT_DIR ORRERY_CALL_LOG="$rel" bash "$hook" <<<"$evt" >/dev/null 2>&1 )
rc=$?
if [ -n "$(find "$lost" -name orrery-calls.tsv 2>/dev/null)" ]; then
  bad "a relative path with no project root writes nothing" "$(find "$lost" -name orrery-calls.tsv)"
elif [ "$rc" -ne 0 ]; then
  bad "and still exits 0, blocking nothing" "exit $rc"
else
  ok "a relative path with no CLAUDE_PROJECT_DIR writes nothing, and blocks nothing"
fi

# An absolute path was never the broken case and must stay untouched by cwd.
abspath="$tmp/abs.log"
( cd "$tmp" && env ORRERY_CALL_LOG="$abspath" CLAUDE_PROJECT_DIR="$proj" bash "$hook" <<<"$evt" >/dev/null 2>&1 )
if [ -f "$abspath" ] && [ ! -e "$proj/$abspath" ]; then
  ok "an absolute path is used as given, not appended to the project root"
else
  bad "an absolute path is used as given" "abs exists: $([ -f "$abspath" ] && echo yes || echo no)"
fi

# --- a skill invocation is recorded, and is not a spawn ----------------------
# `Skill` was added to the matcher after the fact. Before that no skill call was
# recorded anywhere, and the gap was invisible because the log looked complete.
# The name shares field four with the subagent type, so the pair below is what
# has to hold: the name arrives, and field three is what tells a reader which
# kind of name it is.
skill_log="$tmp/skill.log"
run "$skill_log" '{"session_id":"abc-123","tool_name":"Skill","tool_input":{"skill":"sharpen","args":"the whole library"}}'
sline="$(grep '	Skill	' "$skill_log" 2>/dev/null || true)"
if [ -n "$sline" ]; then
  ok "a Skill call is recorded at all"
else
  bad "a Skill call is recorded at all" "no Skill row in $skill_log"
fi
if [ "$(printf '%s' "$sline" | cut -f4)" = sharpen ]; then
  ok "the skill name lands in the kind column"
else
  bad "the skill name lands in the kind column" "field 4 was: $(printf '%s' "$sline" | cut -f4)"
fi
if [ "$(printf '%s' "$sline" | cut -f3)" = Skill ]; then
  ok "and the tool column says which reading of that column applies"
else
  bad "and the tool column says which reading applies" "field 3 was: $(printf '%s' "$sline" | cut -f3)"
fi

# The property the whole recorder is built around, restated for the new field:
# names, never content. `args` is what a person typed and must not survive.
if grep -q 'the whole library' "$skill_log"; then
  bad "skill arguments are never recorded" "the args string reached the log"
else
  ok "skill arguments are never recorded"
fi

# The same forgery guard as the subagent type, because a skill name is
# caller-supplied free text by exactly the same route.
forge_skill="$tmp/forge-skill.log"
# A marker rather than a timestamp, for the reason given at the case above: a
# real date here is a dated incident narrative to `tools/sanitize-scan.sh`, and
# the assertion never needed one.
run "$forge_skill" "$(jq -cn --arg s $'ok\nFORGED-STAMP\tdeadbeef\tBash\t-\tno\tcall\tforged' \
  '{tool_name:"Skill", session_id:"abc-123", tool_input:{skill:$s}}')"
if [ "$(wc -l < "$forge_skill" | tr -d ' ')" = 1 ]; then
  ok "a newline in a skill name cannot forge a second line"
else
  bad "a newline in a skill name cannot forge a second line" "$(wc -l < "$forge_skill") lines"
fi

printf '\n%s cases, %s passing, %s failing\n' "$((pass + fail))" "$pass" "$fail"
[ "$fail" -eq 0 ]
