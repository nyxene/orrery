#!/usr/bin/env bash
# Tests hooks/handoff-prompt.sh against its contract.
#
# This is the only hook in the library that *blocks*, and both of its failure
# directions are expensive. Silent: the compaction it was meant to interrupt goes
# through and the session's dead ends are gone. Repeating: a blocked compaction
# is cancelled rather than deferred, so a hook that fires twice can strand a
# session that was already running out of room.
#
# So the property is not "it prints something". It is that it blocks exactly
# once per session, and declines to block at all when it cannot read its input.
#
# The once-per-session marker lives in $TMPDIR, so each case below gets its own
# and the live session's marker is neither read nor written.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
hook="$here/handoff-prompt.sh"

pass=0 fail=0
ok()  { pass=$((pass + 1)); printf '\033[32m✓\033[0m %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '\033[31m✗\033[0m %s — %s\n' "$1" "$2"; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/handoff-prompt-test.XXXXXX")"
state="$tmp/state"; mkdir -p "$state"
fakebin="$tmp/nojq"; mkdir -p "$fakebin"
for c in cat bash; do ln -s "$(command -v "$c")" "$fakebin/$c"; done
trap 'rm -rf "$tmp"' EXIT

run() { # $1 = payload JSON
  TMPDIR="$state" bash "$hook" <<<"$1" 2>/dev/null
}
payload() { # $1 = session id, $2 = trigger
  jq -n --arg s "$1" --arg t "$2" '{session_id:$s,trigger:$t,custom_instructions:""}'
}

# --- the first compaction of a session is stopped, and told why -------------
out="$(run "$(payload a1 auto)")"
if ! jq -e . >/dev/null 2>&1 <<<"$out"; then
  bad "the first compaction is blocked" "output is not valid JSON: $out"
elif [ "$(jq -r '.decision' <<<"$out")" != "block" ]; then
  bad "the first compaction is blocked" "decision is not block"
elif ! grep -q 'handoff' <<<"$(jq -r '.reason' <<<"$out")"; then
  bad "the first compaction is blocked" "the reason never names the skill to run"
else
  ok "the first compaction of a session is blocked, naming the skill"
fi

# --- and the reason has to say what to do when there is no residue ----------
# Without that half, the hook reads as "write a handoff", and a tracker that
# collects handoffs with no work in them stops being read.
if grep -q 'leaves no residue' <<<"$(jq -r '.reason' <<<"$out")"; then
  ok "the reason permits leaving nothing, not only writing something"
else
  bad "the reason permits leaving nothing" "only the write path is described"
fi

# --- and never a second time in that session --------------------------------
# A blocked compaction is cancelled, not deferred. Blocking again is how a
# session that is out of context gets stranded rather than helped.
out="$(run "$(payload a1 auto)")"; rc=$?
if [ -n "$out" ]; then
  bad "a session is interrupted at most once" "it blocked a second time: $out"
elif [ "$rc" -ne 0 ]; then
  bad "a session is interrupted at most once" "exit $rc"
else
  ok "the second compaction of the same session passes through, exit 0"
fi

# --- a different session is a different session -----------------------------
out="$(run "$(payload a2 auto)")"
if [ "$(jq -r '.decision' 2>/dev/null <<<"$out")" = "block" ]; then
  ok "a new session is interrupted on its own first compaction"
else
  bad "a new session is interrupted" "the marker leaked across sessions"
fi

# --- both triggers qualify --------------------------------------------------
# `trigger` separates manual from auto and the hook deliberately reads neither:
# auto is the one that arrives unannounced, and manual is the one where somebody
# is present to answer.
out="$(run "$(payload a3 manual)")"
if [ "$(jq -r '.decision' 2>/dev/null <<<"$out")" = "block" ]; then
  ok "a manual compaction is interrupted too"
else
  bad "a manual compaction is interrupted too" "only auto blocks"
fi

# --- a payload with no session id still gets one chance ---------------------
out="$(run '{"trigger":"auto"}')"
if [ "$(jq -r '.decision' 2>/dev/null <<<"$out")" != "block" ]; then
  bad "a payload with no session id still blocks once" "it stayed silent"
elif [ -n "$(run '{"trigger":"auto"}')" ]; then
  bad "a payload with no session id blocks once" "it blocked again"
else
  ok "a payload with no session id blocks once, under a fixed marker"
fi

# --- without jq it must not block ------------------------------------------
# Refusing here protects nothing and can strand a full session, so this is the
# one hook whose no-jq branch declines to act rather than failing closed.
out="$(printf '{"session_id":"a4"}' | TMPDIR="$state" PATH="$fakebin" "$fakebin/bash" "$hook" 2>/dev/null)"
if ! jq -e . >/dev/null 2>&1 <<<"$out"; then
  bad "no jq declines to act" "output is not valid JSON: $out"
elif [ "$(jq -r '.decision // empty' <<<"$out")" = "block" ]; then
  bad "no jq declines to act" "it blocked a compaction it could not read"
elif ! grep -q 'handoff' <<<"$(jq -r '.systemMessage // empty' <<<"$out")"; then
  bad "no jq declines to act" "it said nothing about what was skipped"
else
  ok "no jq says what was skipped and lets the compaction proceed"
fi

printf '\n%s cases, %s passing, %s failing\n' "$((pass + fail))" "$pass" "$fail"
[ "$fail" -eq 0 ]
