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
# Each case gets its own repository, because the log's place is named by git:
# `.orrery/local/calls.tsv` in the main checkout. git exports its own
# environment into hooks and this file runs as a gate, so that is cleared first.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
hook="$here/call-log.sh"

pass=0 fail=0
ok()  { pass=$((pass + 1)); printf '\033[32m✓\033[0m %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '\033[31m✗\033[0m %s — %s\n' "$1" "$2"; }

while IFS='=' read -r _var _; do unset "$_var"; done < <(env | grep '^GIT_')
tmp="$(mktemp -d "${TMPDIR:-/tmp}/call-log-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
tmp="$(cd "$tmp" && pwd -P)"

# A new repository; prints the path its log will have.
fresh() { # $1 = name
  mkdir -p "$tmp/$1" && git -C "$tmp/$1" init -q -b main
  git -C "$tmp/$1" config user.email t@example.invalid; git -C "$tmp/$1" config user.name t
  printf '%s/.orrery/local/calls.tsv' "$tmp/$1"
}
# One call through the hook, launched in the log's repository. Prints what the
# hook printed; the log is the output.
run_out() { # $1 = log path from fresh, $2 = payload JSON
  local r="${1%/.orrery/local/calls.tsv}"
  ( cd "$r" && env -u ORRERY_CALL_LOG CLAUDE_PROJECT_DIR="$r" bash "$hook" <<<"$2" 2>/dev/null )
}
run() { run_out "$@" >/dev/null; }

bash_payload='{"session_id":"abc-123","tool_name":"Bash","tool_input":{"command":"rm -rf /Users/someone/secret"}}'
agent_payload='{"session_id":"abc-123","tool_name":"Agent","tool_input":{"subagent_type":"critic","name":"my-reviewer","prompt":"a private brief mentioning /Users/someone"}}'

# --- declared off is off ---------------------------------------------------
log="$(fresh off)"
mkdir -p "$tmp/off/.orrery"; printf '{"callLog":false}' > "$tmp/off/.orrery/config.json"
run "$log" "$bash_payload"
if [ ! -e "$log" ]; then
  ok "\"callLog\": false means no file is created"
else
  bad "\"callLog\": false means no file is created" "something was written anyway"
fi

# --- a call is recorded, with the fields the analysis needs ----------------
log="$(fresh a)"
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
log="$(fresh b)"
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
forge_log="$(fresh forge)"
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
out="$(run_out "$(fresh c)" "$bash_payload")"
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then ok "a recorded call prints nothing and exits 0"
else bad "a recorded call prints nothing and exits 0" "rc=$rc out=$out"; fi

# `.orrery/local` as a file: the directory cannot be made.
log="$(fresh unwritable)"; mkdir -p "$tmp/unwritable/.orrery"; : > "$tmp/unwritable/.orrery/local"
out="$(run_out "$log" "$bash_payload")"
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then ok "an unwritable log path still exits 0 and blocks nothing"
else bad "an unwritable log path still exits 0 and blocks nothing" "rc=$rc out=$out"; fi

out="$(run_out "$(fresh d)" 'not json at all')"
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then ok "a payload that is not JSON exits 0 and blocks nothing"
else bad "a payload that is not JSON exits 0 and blocks nothing" "rc=$rc out=$out"; fi

# --- the log is bounded ----------------------------------------------------
# Without this it grows forever in somebody else's repository.
log="$(fresh big)"
mkdir -p "$(dirname "$log")"
i=0
while [ "$i" -lt 400 ]; do
  printf 'x%.0s' $(seq 1 40) >> "$log"; printf '\n' >> "$log"
  i=$((i + 1))
done
before="$(wc -c < "$log" | tr -d ' ')"
( cd "$tmp/big" && ORRERY_CALL_LOG_MAX=4096 CLAUDE_PROJECT_DIR="$tmp/big" bash "$hook" <<<"$bash_payload" >/dev/null 2>&1 )
after="$(wc -c < "$log" | tr -d ' ')"
if [ "$after" -lt "$before" ]; then ok "the log is trimmed once it passes its size cap"
else bad "the log is trimmed once it passes its size cap" "before=$before after=$after"; fi

# --- purge empties it and says so ------------------------------------------
log="$(fresh p)"
run "$log" "$bash_payload"
msg="$(cd "$tmp/p" && env -u CLAUDE_PROJECT_DIR bash "$hook" --purge 2>&1)"
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

log="$(fresh pair)"
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
log="$(fresh refused)"
run "$log" "$pre"
if [ "$(wc -l < "$log" | tr -d ' ')" -eq 1 ] && [ "$(cut -f6 "$log")" = call ]; then
  ok "a call that never completes leaves one unpaired call line"
else
  bad "a call that never completes leaves one unpaired call line" "$(cat "$log")"
fi

# The pair can only form if both halves watch the same tools, so the two
# registrations in hooks.json must carry the same matcher. Narrow the PostToolUse
# one and every call to the dropped tool reads as "did not run" — the false
# statement the header records. This sentence lived in hooks.json as a `_comment`
# until the CLI began rejecting that key at load; the fact moved to the header
# and the check moved here, where an edit that breaks it goes red.
hj="$here/hooks.json"
# `any(…)` and not a bare `select(.hooks[].command | …)`: the bare form emits the
# entry once per matching hook, so a second call-log hook on one entry would make
# this two lines and the comparison red with identical matchers — a false red.
pre_m="$(jq -r '.hooks.PreToolUse[]  | select(any(.hooks[]; .command | test("call-log"))) | .matcher' "$hj" 2>/dev/null)"
post_m="$(jq -r '.hooks.PostToolUse[] | select(any(.hooks[]; .command | test("call-log"))) | .matcher' "$hj" 2>/dev/null)"
if [ -n "$pre_m" ] && [ "$pre_m" = "$post_m" ]; then
  ok "the PreToolUse and PostToolUse registrations watch the same tools"
else
  bad "the PreToolUse and PostToolUse registrations watch the same tools" "pre=[$pre_m] post=[$post_m]"
fi

# --- the two ways the event field can be wrong ------------------------------

# Absent: this hook fails open, the field is newer than the log, and going
# silent because one key moved is worse than mislabelling.
log="$(fresh noevent)"
run "$log" '{"session_id":"s2","tool_name":"Bash","tool_input":{"command":"ls"}}'
if [ "$(cut -f6 "$log" 2>/dev/null)" = call ]; then
  ok "a payload with no hook_event_name is still recorded, as a call"
else
  bad "a payload with no hook_event_name is still recorded" "$(cat "$log" 2>/dev/null)"
fi

# Present and unrecognised: someone registered a third event and did not teach
# this file. Recording it unlabelled would have every reader count it as a call.
log="$(fresh unknown)"
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
log="$(fresh forge-id)"
run "$log" "$(jq -nc '{session_id:"s4",hook_event_name:"PreToolUse",tool_name:"Bash",
                       tool_use_id:"tu_1\nFORGED\tx\ty\tz\tcall\ttu_2",tool_input:{command:"ls"}}')"
if [ "$(wc -l < "$log" | tr -d ' ')" -eq 1 ] && ! grep -q FORGED <<<"$(cut -f1 "$log")"; then
  ok "a newline inside tool_use_id cannot write a second line"
else
  bad "a newline inside tool_use_id cannot write a second line" "$(cat "$log")"
fi

# --- one log per clone, wherever the call runs ------------------------------
# The defect this placement was chosen to end. The log used to sit at a path an
# environment variable named, relative in every install, and this hook resolved
# it against the directory the tool call ran in — so every `cd` into a
# subdirectory started a new log. One host project accumulated twenty.

proj="$tmp/proj"; mkdir -p "$proj/sub/deeper"
git -C "$proj" init -q -b main
git -C "$proj" config user.email t@example.invalid; git -C "$proj" config user.name t
git -C "$proj" commit -q --allow-empty -m init
git -C "$proj" worktree add -q -b w "$proj/.claude/worktrees/w" 2>/dev/null
evt='{"session_id":"r1","hook_event_name":"PreToolUse","tool_name":"Bash","tool_use_id":"r_1","tool_input":{"command":"ls"}}'

for d in "$proj" "$proj/sub" "$proj/sub/deeper"; do
  ( cd "$d" && env CLAUDE_PROJECT_DIR="$proj" bash "$hook" <<<"$evt" >/dev/null 2>&1 )
done
# The harness's cwd, not the launch directory, names the tree: a call made in a
# worktree lands in the main checkout's log all the same.
( cd "$tmp" && env CLAUDE_PROJECT_DIR="$tmp" bash "$hook" \
    <<<"$(jq -c --arg c "$proj/.claude/worktrees/w" '. + {cwd: $c}' <<<"$evt")" >/dev/null 2>&1 )
found="$(cd "$proj" && find . -name calls.tsv | sort | tr '\n' ' ')"
if [ "$found" != "./.orrery/local/calls.tsv " ]; then
  bad "every call lands in the main checkout's one log" "found: $found"
elif [ "$(wc -l < "$proj/.orrery/local/calls.tsv" | tr -d ' ')" -ne 4 ]; then
  bad "all four calls land in the one file" "$(cat "$proj/.orrery/local/calls.tsv")"
else
  ok "calls from three directories and a worktree write one file in the main checkout"
fi
if [ -z "$(git -C "$proj" status --porcelain -- .orrery)" ]; then
  ok "and git sees nothing to commit there"
else
  bad "and git sees nothing to commit there" "$(git -C "$proj" status --porcelain -- .orrery)"
fi

# Outside a repository: record nothing rather than somewhere. This hook fails
# open everywhere else, and deliberately does not here — a missing line costs a
# line, a file in someone's tree is damage they have to find.
lost="$tmp/lost"; mkdir -p "$lost/sub"
( cd "$lost/sub" && env CLAUDE_PROJECT_DIR="$lost" bash "$hook" <<<"$evt" >/dev/null 2>&1 )
rc=$?
if [ -n "$(find "$lost" -type f 2>/dev/null)" ]; then
  bad "outside a repository nothing is written" "$(find "$lost" -type f)"
elif [ "$rc" -ne 0 ]; then
  bad "and still exits 0, blocking nothing" "exit $rc"
else
  ok "outside a repository nothing is written, and nothing is blocked"
fi

# --- the old log comes with it, once, and stays ------------------------------
up="$tmp/upgrade"; log="$(fresh upgrade)"
mkdir -p "$up/.claude"; printf 'OLD-ROW\n' > "$up/.claude/orrery-calls.tsv"
run "$log" "$evt"
if [ "$(head -1 "$log" 2>/dev/null)" = OLD-ROW ] && [ "$(wc -l < "$log" | tr -d ' ')" -eq 2 ] \
   && [ "$(cat "$up/.claude/orrery-calls.tsv")" = OLD-ROW ]; then
  ok "an upgrade carries the old log's rows over and leaves the old file"
else
  bad "an upgrade carries the old log's rows over and leaves the old file" "$(cat "$log" 2>/dev/null)"
fi
log2="$(fresh upgrade-named)"
mkdir -p "$tmp/upgrade-named/logs"; printf 'NAMED-ROW\n' > "$tmp/upgrade-named/logs/x.tsv"
( cd "$tmp/upgrade-named" && ORRERY_CALL_LOG=logs/x.tsv CLAUDE_PROJECT_DIR="$tmp/upgrade-named" bash "$hook" <<<"$evt" >/dev/null 2>&1 )
if [ "$(head -1 "$log2" 2>/dev/null)" = NAMED-ROW ]; then
  ok "a log the old variable named elsewhere is the one carried over"
else
  bad "a log the old variable named elsewhere is the one carried over" "$(cat "$log2" 2>/dev/null)"
fi

# --- a skill invocation is recorded, and is not a spawn ----------------------
# `Skill` was added to the matcher after the fact. Before that no skill call was
# recorded anywhere, and the gap was invisible because the log looked complete.
# The name shares field four with the subagent type, so the pair below is what
# has to hold: the name arrives, and field three is what tells a reader which
# kind of name it is.
skill_log="$(fresh skill)"
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
forge_skill="$(fresh forge-skill)"
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
