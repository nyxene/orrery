#!/usr/bin/env bash
# PreToolUse recorder. Appends one line per tool call to a local file so that a
# change to how the library works can be observed instead of assumed.
#
#   ORRERY_CALL_LOG=<path>   enables it. Unset, this exits before doing anything.
#   ORRERY_CALL_LOG_MAX=<n>  bytes to keep, default 262144. Trimmed oldest-first.
#   hooks/call-log.sh --purge   empties the log and says how much it removed.
#
# ## Why a hook rather than a line inside each skill
#
# A skill that logs its own behaviour cannot record the run where it ignored its
# own instructions — the same omission removes the behaviour and the evidence of
# it. The case this exists to catch is exactly that: a plan that spiked and then
# skipped its checkers, which `skills/plan/SKILL.md` argues against and cannot
# enforce. From here it is a session with a planner spawn, some Bash, and no
# critic — visible without the skill cooperating and without reading anything it
# produced.
#
# ## What is recorded, and what is deliberately next to it and not recorded
#
# Five fields, tab separated: an ISO-8601 UTC timestamp, a session fingerprint,
# the tool name, the subagent type where there is one, and whether the spawn was
# named.
#
# Not the prompt. Not the command. Not the file path, the branch, the cwd, or
# the name given to a named agent. `agent-guard.sh` reads `.tool_input.prompt`
# two files away, to make a decision and never to keep one — and this paragraph
# exists because the field sits right next to the ones below, so the first person
# who wants it "just for debugging" finds a sentence here instead of a silence.
#
# The session id is hashed rather than stored. It correlates calls within one
# session, which is the whole purpose, and identifies nothing outside the machine
# that wrote it. That matters because these lines are meant to be attachable to a
# feedback report by hand.
#
# ## It fails open, unlike every other hook here
#
# The guards deny when they cannot run, because a guard that cannot check must
# not let a command through. This is not a guard. A recorder that blocks work
# when its disk is full has done more damage than the missing line was worth, so
# every failure path here exits 0 silently.
set -euo pipefail

log="${ORRERY_CALL_LOG:-}"

if [ "${1:-}" = --purge ]; then
  [ -n "$log" ] || { printf 'ORRERY_CALL_LOG is not set, so there is no log to purge.\n' >&2; exit 1; }
  if [ -f "$log" ]; then
    lines="$(wc -l < "$log" | tr -d ' ')"
    : > "$log"
    printf 'purged %s lines from %s\n' "$lines" "$log"
  else
    printf 'nothing to purge: %s does not exist\n' "$log"
  fi
  exit 0
fi

# Not configured is the normal case for anyone who did not ask for this, and it
# costs one variable test per tool call.
[ -n "$log" ] || exit 0

input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

tool="$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null || true)"
[ -n "$tool" ] || exit 0

session="$(jq -r '.session_id // "nosession"' <<<"$input" 2>/dev/null || true)"
# Whichever of the two is present; neither is a personal identifier and both are
# fixed vocabulary chosen by the caller, not free text.
agent="$(jq -r '.tool_input.subagent_type // .tool_input.agentType // "-"' <<<"$input" 2>/dev/null || true)"
# Whether a name was given, never the name itself.
named=no
[ -z "$(jq -r '.tool_input.name // empty' <<<"$input" 2>/dev/null || true)" ] || named=yes

# `|| true` on both, because the claim above is that every failure path here
# exits 0 and these were the two that did not: under `set -e` a hashing tool
# that fails takes the hook down with it. Nothing blocks either way — the
# harness treats a non-zero hook as a non-blocking error — but a recorder that
# exits non-zero is a recorder that shows up in logs as broken.
if command -v shasum >/dev/null 2>&1; then
  fp="$(printf '%s' "$session" | shasum -a 256 2>/dev/null | cut -c1-8 || true)"
elif command -v sha256sum >/dev/null 2>&1; then
  fp="$(printf '%s' "$session" | sha256sum 2>/dev/null | cut -c1-8 || true)"
fi
[ -n "${fp:-}" ] || fp=nohash

mkdir -p "$(dirname "$log")" 2>/dev/null || exit 0
printf '%s\t%s\t%s\t%s\t%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$fp" "$tool" "${agent:--}" "$named" >> "$log" 2>/dev/null || exit 0

# Trimming is checked by size rather than by counting lines: this runs on every
# tool call, and `wc -l` on a file that only grows is the kind of cost that is
# invisible until the file is large. `stat` is one syscall.
max="${ORRERY_CALL_LOG_MAX:-262144}"
size="$(stat -f%z "$log" 2>/dev/null || stat -c%s "$log" 2>/dev/null || echo 0)"
if [ "$size" -gt "$max" ] 2>/dev/null; then
  # By bytes, not by a line count. Keeping "the last N lines" does not shrink a
  # file whose lines are long — the first version kept 2000 of them and left a
  # file of 401 unchanged, which the test caught. Halving is what makes the trim
  # amortised: it happens once every max/2 bytes rather than on every call from
  # the moment the cap is first crossed.
  tmp="$log.trim.$$"
  # `tail -c` can land mid-line, so the first (partial) one is dropped.
  if tail -c "$((max / 2))" "$log" 2>/dev/null | tail -n +2 > "$tmp" 2>/dev/null; then
    mv "$tmp" "$log" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
  else
    rm -f "$tmp" 2>/dev/null || true
  fi
fi

exit 0
