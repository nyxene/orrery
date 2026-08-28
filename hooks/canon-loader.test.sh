#!/usr/bin/env bash
# Tests hooks/canon-loader.sh against its contract.
#
# This hook fires at every session start and its failure mode is silence: a
# session that never received the canon looks exactly like a session that did,
# from the inside. Nothing else in the repository would notice, which is why the
# cases below assert on what reaches the harness rather than on an exit code.
#
# The emission is JSON built by jq. Malformed JSON is dropped by the harness
# without a message, so "valid JSON carrying the file's own bytes" is the
# property, not "something was printed".
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
hook="$here/canon-loader.sh"

pass=0 fail=0
ok()  { pass=$((pass + 1)); printf '\033[32m✓\033[0m %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '\033[31m✗\033[0m %s — %s\n' "$1" "$2"; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/canon-loader-test.XXXXXX")"
# A PATH carrying no jq, for the branch that has to speak up rather than exit
# 127 into silence. It carries everything else the hook reaches before it gives
# up: a shadow missing `dirname` too kills the script under `set -e` one line
# earlier, and the case then passes or fails for the wrong reason. Only jq is
# plausibly absent on a real machine — coreutils are not.
fakebin="$tmp/nojq"
mkdir -p "$fakebin"
for c in cat bash dirname; do ln -s "$(command -v "$c")" "$fakebin/$c"; done
trap 'rm -rf "$tmp"' EXIT

run() { # $1 = plugin root, empty for unset — prints what the harness would read
  if [ -n "$1" ]; then CLAUDE_PLUGIN_ROOT="$1" bash "$hook" 2>/dev/null
  else env -u CLAUDE_PLUGIN_ROOT bash "$hook" 2>/dev/null; fi
}

context() { jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null <<<"$1"; }

# --- a canon that exists reaches the session, intact ------------------------
root="$tmp/root"; mkdir -p "$root"
marker='CANON FIXTURE MARKER'
printf '%s\n' "$marker" > "$root/CANON.md"
out="$(run "$root")"
if ! jq -e . >/dev/null 2>&1 <<<"$out"; then
  bad "a canon that exists is emitted" "output is not valid JSON: $out"
elif [ "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$out")" != "SessionStart" ]; then
  bad "a canon that exists is emitted" "wrong hookEventName"
elif ! grep -qF "$marker" <<<"$(context "$out")"; then
  bad "a canon that exists is emitted" "the file's text is not in additionalContext"
else
  ok "a canon that exists is emitted as SessionStart context"
fi

# --- and the harness is told what it is reading -----------------------------
# The bare file would be a wall of text with no standing. The framing sentence is
# what makes it binding rather than informational, and it is one string away from
# being dropped by an edit that only meant to change the file.
if grep -q 'non-negotiable core' <<<"$(context "$out")"; then
  ok "the canon arrives framed as binding, not as a document"
else
  bad "the canon arrives framed as binding" "the framing sentence is gone"
fi

# --- a canon file that would break naive quoting -----------------------------
# Built with printf rather than a heredoc so the case is legible: a quote, a
# backslash and a newline are exactly what turns hand-rolled JSON into output the
# harness silently discards.
printf 'a "quoted" line\\\\ and a backslash\nsecond line\n' > "$root/CANON.md"
out="$(run "$root")"
if ! jq -e . >/dev/null 2>&1 <<<"$out"; then
  bad "quotes and backslashes survive" "output is not valid JSON"
elif ! grep -qF 'a "quoted" line' <<<"$(context "$out")"; then
  bad "quotes and backslashes survive" "the line came back changed"
else
  ok "quotes, backslashes and newlines survive the emission"
fi

# --- no canon is not an error -----------------------------------------------
empty="$tmp/empty"; mkdir -p "$empty"
out="$(run "$empty")"; rc=$?
if [ -n "$out" ]; then
  bad "a root with no CANON.md stays quiet" "it printed: $out"
elif [ "$rc" -ne 0 ]; then
  bad "a root with no CANON.md stays quiet" "exit $rc"
else
  ok "a root with no CANON.md prints nothing and exits 0"
fi

# --- an unset root falls back to the hook's own directory -------------------
# That fallback is what makes this repository work at all: the plugin lives here
# as a checkout, so CLAUDE_PLUGIN_ROOT is not set and the loader has to find its
# own canon. It is one expansion, and nothing else would report its loss.
out="$(run "")"
if grep -qF "$(head -1 "$here/../CANON.md")" <<<"$(context "$out")"; then
  ok "an unset CLAUDE_PLUGIN_ROOT falls back to the checkout's own canon"
else
  bad "an unset CLAUDE_PLUGIN_ROOT falls back to the checkout's own canon" \
      "the repository's CANON.md did not come through"
fi

# --- without jq it says so, rather than exiting 127 into silence ------------
out="$(printf '' | PATH="$fakebin" "$fakebin/bash" "$hook" 2>/dev/null)"
if grep -q 'WARNING' <<<"$out" && jq -e . >/dev/null 2>&1 <<<"$out"; then
  ok "no jq is announced, in valid JSON, instead of failing silently"
else
  bad "no jq is announced" "expected a WARNING payload, got: $out"
fi

# --- this loader carries this plugin's canon and no other -------------------
# `orrery-method` is a declared dependency, not a vendored copy: its canon is a
# different document about a different thing, and its own plugin's hook loads
# it. A canon found under method/ here would mean a second copy of the corpus
# in this repository — the drift SHIPLIST exists to make impossible — so it is
# not read, and this case is what would notice if that changed.
foreign="$tmp/foreign"; mkdir -p "$foreign/method"
printf 'CONDUCT FIXTURE MARKER\n'   > "$foreign/CANON.md"
printf 'STRUCTURE FIXTURE MARKER\n' > "$foreign/method/CANON.md"
out="$(run "$foreign")"
if grep -qF 'STRUCTURE FIXTURE MARKER' <<<"$(context "$out")"; then
  bad "no second canon is read from this plugin's tree" \
      "a canon under method/ reached the session — the corpus is a dependency, not a copy"
elif grep -qF 'CONDUCT FIXTURE MARKER' <<<"$(context "$out")"; then
  ok "only this plugin's own canon is emitted"
else
  bad "only this plugin's own canon is emitted" "the conduct canon did not come through: $out"
fi

printf '\n%s cases, %s passing, %s failing\n' "$((pass + fail))" "$pass" "$fail"
[ "$fail" -eq 0 ]
