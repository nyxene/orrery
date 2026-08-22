#!/usr/bin/env bash
# Tests hooks/permissions-check.sh against its contract.
#
# This hook fires at session start and its failure mode is silence — the same
# silence a fully merged project produces. Nothing downstream would notice, so
# the cases below assert on **what reaches the harness** rather than on an exit
# code: malformed JSON is dropped by the platform without a message, so "printed
# something" is not the property (`canon-loader.test.sh:4-11`).
#
# Fixture rules are named `orrery-fixture-*` on purpose. The script reads five
# settings scopes, two of which are machine-wide managed paths this suite cannot
# control; a rule string no real settings file could contain is what keeps a
# green case green for the right reason.
#
# 36 cases, numbered as the plan's list numbers them after the duplicate labels
# were resolved.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
hook="$here/permissions-check.sh"

pass=0 fail=0
ok()  { pass=$((pass + 1)); printf '\033[32m✓\033[0m %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '\033[31m✗\033[0m %s — %s\n' "$1" "$2"; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/permissions-check-test.XXXXXX")"
# Canonicalised, because the script under test resolves paths itself and prints
# them, and this suite asserts on that text. On macOS $TMPDIR lives under
# /var/folders, a symlink into /private/var, so an unresolved fixture path and a
# resolved one differ by a prefix and four cases fail against correct code. It
# passes on Linux and under a sandbox handing out a /tmp path — which is how it
# survived review: green everywhere anyone had run it.
tmp="$(cd "$tmp" && pwd -P)"
# u+rwX first: several cases plant unwritable directories and unreadable files.
trap 'chmod -R u+rwX "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT

r1='Bash(orrery-fixture-one:*)'
r2='Bash(orrery-fixture-two:*)'
r3='Bash(orrery-fixture-three:*)'
r4='Bash(orrery-fixture-four:*)'
mine='Bash(orrery-fixture-theirs-only:*)'

# A PATH carrying no jq, mirrored rather than hand-written: a shadow missing
# `dirname` or `sed` kills the script one line earlier and the case then passes
# for the wrong reason (`canon-loader.test.sh:22-29`).
nojq="$tmp/nojq"; mkdir -p "$nojq"
IFS=: read -ra pathdirs <<<"$PATH"
for dir in "${pathdirs[@]}"; do
  [ -d "$dir" ] || continue
  for f in "$dir"/*; do
    [ -e "$f" ] || continue
    b="${f##*/}"
    case "$b" in jq) continue ;; esac
    [ -e "$nojq/$b" ] || ln -sf "$f" "$nojq/$b"
  done
done

rules() { if [ $# -eq 0 ]; then printf '[]\n'; else printf '%s\n' "$@" | jq -R . | jq -s .; fi; }

mkroot() { # $1 = dir, $2 = version, rest = shipped deny rules
  local dir="$1" ver="$2"; shift 2
  mkdir -p "$dir/hooks" "$dir/.claude-plugin"
  jq -n --argjson deny "$(rules "$@")" \
    '{permissions:{allow:["Bash(orrery-allow-one:*)","Bash(orrery-allow-two:*)"],deny:$deny}}' \
    > "$dir/hooks/permissions.json"
  jq -n --arg v "$ver" '{version:$v}' > "$dir/.claude-plugin/plugin.json"
}

settings() { # $1 = file, rest = deny rules
  local f="$1"; shift
  mkdir -p "$(dirname "$f")"
  jq -n --argjson deny "$(rules "$@")" '{permissions:{deny:$deny}}' > "$f"
}

n=0
root='' home='' proj=''
scenario() { # rest = shipped deny rules; sets $root $home $proj
  n=$((n + 1))
  root="$tmp/s$n/root"; home="$tmp/s$n/home"; proj="$tmp/s$n/project"
  mkdir -p "$home" "$proj/.claude"
  mkroot "$root" "1.2.3" "$@"
}

run() { # $1 = root ('' = unset), $2 = home, $3 = project, rest = flags
  local rt="$1" hm="$2" pj="$3"; shift 3
  if [ -n "$rt" ]; then env HOME="$hm" CLAUDE_PLUGIN_ROOT="$rt" bash "$hook" "$@" "$pj" 2>/dev/null
  else env -u CLAUDE_PLUGIN_ROOT HOME="$hm" bash "$hook" "$@" "$pj" 2>/dev/null; fi
}

msg() { jq -r '.systemMessage // empty' 2>/dev/null <<<"$1"; }

statepath() { # $1 = home, $2 = project
  printf '%s/.claude/orrery/permissions/%s.json' "$1" \
    "$(cd "$2" && pwd -P | sed 's#^/##; s#[/ ]#-#g')"
}

has()  { grep -qF "$2" <<<"$1"; }

# --- the comparison ---------------------------------------------------------

# 1
scenario "$r1" "$r2" "$r3"
settings "$proj/.claude/settings.json" "$r1"
out="$(run "$root" "$home" "$proj")"
rep="$(run "$root" "$home" "$proj" --report)"; rrc=$?
if ! has "$(msg "$out")" '2 deny rules'; then
  bad "1 a subset gap is named with its count" "got: $out"
elif [ "$rrc" -ne 1 ] || ! has "$rep" "$r2" || ! has "$rep" "$r3"; then
  bad "1 --report names every absent rule verbatim" "rc=$rrc, got: $rep"
else
  ok "1 rules we ship and they do not have are counted, and named verbatim by --report"
fi

# 2
scenario "$r1" "$r2" "$r3"
settings "$proj/.claude/settings.json" "$r1" "$r2" "$r3"
out="$(run "$root" "$home" "$proj")"; rc=$?
if [ -n "$out" ] || [ "$rc" -ne 0 ]; then
  bad "2 a merged project says nothing" "rc=$rc, printed: $out"
else
  ok "2 a project holding every shipped rule prints nothing and exits 0"
fi

# 3 — a subset check and not an equality check, which is a decision rather than
# an implementation detail: rules a project holds that we do not ship are theirs.
scenario "$r1" "$r2"
settings "$proj/.claude/settings.json" "$r1" "$r2" "$mine"
out="$(run "$root" "$home" "$proj")"
rep="$(run "$root" "$home" "$proj" --report)"
if [ -n "$out" ]; then
  bad "3 rules they have and we do not ship are ignored" "hook spoke: $out"
elif has "$rep" "$mine"; then
  bad "3 rules they have and we do not ship are ignored" "--report mentioned it: $rep"
else
  ok "3 a rule the project has and this plugin does not ship is never mentioned"
fi

# 4 — the allow block names our own gate scripts by path; it is not theirs.
scenario "$r1" "$r2"
settings "$proj/.claude/settings.json" "$r1" "$r2"
out="$(run "$root" "$home" "$proj")"
rep="$(run "$root" "$home" "$proj" --report)"
if [ -n "$out" ] || has "$rep" 'orrery-allow-one'; then
  bad "4 the allow block is never compared" "hook: $out / report: $rep"
else
  ok "4 a project carrying none of the allow rules is silent"
fi

# --- the scopes -------------------------------------------------------------

# 5
scenario "$r1" "$r2"
settings "$proj/.claude/settings.json" "$r1"
settings "$proj/.claude/settings.local.json" "$r2"
out="$(run "$root" "$home" "$proj")"
if [ -n "$out" ]; then bad "5 settings.local.json counts" "spoke: $out"
else ok "5 a rule present only in settings.local.json is not reported"; fi

# 6
scenario "$r1" "$r2"
settings "$proj/.claude/settings.json" "$r1"
settings "$home/.claude/settings.json" "$r2"
out="$(run "$root" "$home" "$proj")"
if [ -n "$out" ]; then bad "6 user scope counts" "spoke: $out"
else ok "6 a rule present only in \$HOME/.claude/settings.json is not reported"; fi

# 7
scenario "$r1" "$r2" "$r3"
out="$(run "$root" "$home" "$proj")"
if has "$(msg "$out")" '3 deny rules'; then
  ok "7 no project settings file at all reports every shipped rule"
else
  bad "7 no project settings file at all reports every shipped rule" "got: $out"
fi

# 8 — the fresh-install shape, and the read that dies at jq exit 5 without // [].
#     Zero merged has to be distinguishable from fully merged.
scenario "$r1" "$r2" "$r3"
printf '{"enabledPlugins":{"orrery@orrery":true}}\n' > "$proj/.claude/settings.json"
out="$(run "$root" "$home" "$proj")"
if has "$(msg "$out")" '3 deny rules'; then
  ok "8 a settings file with no permissions key reports every shipped rule"
else
  bad "8 a settings file with no permissions key reports every shipped rule" "got: $out"
fi

# --- the two records --------------------------------------------------------

# 9
scenario "$r1" "$r2" "$r3"
settings "$proj/.claude/settings.json" "$r1"
first="$(run "$root" "$home" "$proj")"
second="$(run "$root" "$home" "$proj")"
if [ -z "$first" ] || [ -n "$second" ]; then
  bad "9 an unchanged finding is said once" "first: $first / second: $second"
else
  ok "9 the same finding is not repeated on the next session start"
fi

# 10 — what version-keying could not do: the version never moves here.
settings "$proj/.claude/settings.json"
third="$(run "$root" "$home" "$proj")"
if ! has "$(msg "$third")" '3 deny rules'; then
  bad "10 a changed finding speaks again" "got: $third"
elif ! has "$(msg "$first")" 'orrery 1.2.3:' || ! has "$(msg "$third")" 'orrery 1.2.3:'; then
  bad "10 a changed finding speaks again with no version change" "versions differ"
else
  ok "10 one more absent rule makes it speak again, with the version unchanged"
fi

# 11
scenario "$r1" "$r2"
settings "$proj/.claude/settings.json" "$r1"
jq -n --argjson d "$(rules "$r2")" '{reconciled_deny:$d,reconciled_version:"1.2.3"}' \
  > "$proj/.claude/orrery-deny.json"
out="$(run "$root" "$home" "$proj")"
if [ -n "$out" ]; then bad "11 a declined rule is silent" "spoke: $out"
else ok "11 a rule recorded as declined and absent from settings is not reported"; fi

# 12
scenario "$r1" "$r2" "$r3" "$r4"
settings "$proj/.claude/settings.json" "$r1"
before="$(run "$root" "$home" "$proj")"
jq -n --argjson d "$(rules "$r2")" '{reconciled_deny:$d,reconciled_version:"1.2.3"}' \
  > "$proj/.claude/orrery-deny.json"
after="$(run "$root" "$home" "$proj")"
rep="$(run "$root" "$home" "$proj" --report)"
if ! has "$(msg "$before")" '3 deny rules'; then
  bad "12 a mixed finding names only the un-declined rules" "before: $before"
elif ! has "$(msg "$after")" '2 deny rules'; then
  bad "12 declining a rule changes the finding, so it speaks once more" "after: $after"
elif has "$rep" "$r2" || ! has "$rep" "$r3" || ! has "$rep" "$r4"; then
  bad "12 --report lists the un-declined rules only" "got: $rep"
else
  ok "12 only un-declined rules are named, and declining one changes the finding"
fi

# 13 — pre-mortem 3: reporting must never be a reconciliation.
scenario "$r1" "$r2" "$r3"
settings "$proj/.claude/settings.json" "$r1"
run "$root" "$home" "$proj" >/dev/null
settings "$proj/.claude/settings.json" "$r1" "$r2"
again="$(run "$root" "$home" "$proj")"
if [ -e "$proj/.claude/orrery-deny.json" ]; then
  bad "13 reporting does not reconcile" "the hook wrote a decline record"
elif ! has "$(msg "$again")" "$r3"; then
  # the message carries the count, not the rules — so ask --report instead
  rep="$(run "$root" "$home" "$proj" --report)"
  if has "$rep" "$r3"; then
    ok "13 a reported rule is still reported after the finding changes"
  else
    bad "13 a reported rule is still reported after the finding changes" "got: $rep"
  fi
else
  ok "13 a reported rule is still reported after the finding changes"
fi

# 14
scenario "$r1" "$r2"
settings "$proj/.claude/settings.json"
out="$(run "$root" "$home" "$proj")"
if [ -z "$out" ]; then
  bad "14 no trust-on-first-use" "the first ever run said nothing"
elif [ -e "$proj/.claude/orrery-deny.json" ]; then
  bad "14 no trust-on-first-use" "the first ever run recorded a baseline"
else
  ok "14 a first-ever run reports, and records nothing as declined"
fi

# 15
scenario "$r1" "$r2" "$r3"
settings "$proj/.claude/settings.json" "$r1"
out="$(run "$root" "$home" "$proj" --reconcile)"; rc=$?
after="$(run "$root" "$home" "$proj")"
if [ "$rc" -ne 0 ] || [ ! -f "$proj/.claude/orrery-deny.json" ]; then
  bad "15 --reconcile writes the record" "rc=$rc, out=$out"
elif [ -n "$after" ]; then
  bad "15 the hook goes quiet after --reconcile" "spoke: $after"
else
  ok "15 --reconcile writes the project record and the hook then goes quiet"
fi

# 16
scenario "$r1" "$r2"
settings "$proj/.claude/settings.json" "$r1" "$r2"
out="$(run "$root" "$home" "$proj" --reconcile)"; rc=$?
if [ "$rc" -ne 3 ] || [ -e "$proj/.claude/orrery-deny.json" ]; then
  bad "16 --reconcile refuses when there is nothing to decline" "rc=$rc, out=$out"
else
  ok "16 --reconcile with nothing absent writes no file and exits 3"
fi

# 17 — a union could only ever grow, so un-declining would need a file edit.
scenario "$r1" "$r2" "$r3" "$r4"
settings "$proj/.claude/settings.json" "$r1" "$r4"
run "$root" "$home" "$proj" --reconcile >/dev/null
settings "$proj/.claude/settings.json" "$r1" "$r2" "$r3"
run "$root" "$home" "$proj" --reconcile >/dev/null
kept="$(jq -r '.reconciled_deny | sort | join(",")' "$proj/.claude/orrery-deny.json")"
if [ "$kept" = "$r4" ]; then
  ok "17 --reconcile replaces the record rather than merging into it"
else
  bad "17 --reconcile replaces the record rather than merging into it" "recorded: $kept"
fi

# 18 — the fresh clone: the project record travels, the rate limiter does not.
scenario "$r1" "$r2" "$r3"
settings "$proj/.claude/settings.json" "$r1"
jq -n --argjson d "$(rules "$r2")" '{reconciled_deny:$d,reconciled_version:"1.2.3"}' \
  > "$proj/.claude/orrery-deny.json"
one="$(run "$root" "$home" "$proj")"
two="$(run "$root" "$home" "$proj")"
if ! has "$(msg "$one")" '1 deny rule '; then
  bad "18 a fresh clone filters declines and speaks once" "first run: $one"
elif [ -n "$two" ]; then
  bad "18 a fresh clone filters declines and speaks once" "second run: $two"
else
  ok "18 with no machine state but a decline record, the filter holds and it speaks once"
fi

# --- fail-safe --------------------------------------------------------------

# 19
scenario "$r1" "$r2"
out="$(env HOME="$home" CLAUDE_PLUGIN_ROOT="$root" PATH="$nojq" "$nojq/bash" "$hook" "$proj" 2>/dev/null)"; rc=$?
rep="$(env HOME="$home" CLAUDE_PLUGIN_ROOT="$root" PATH="$nojq" "$nojq/bash" "$hook" --report "$proj" 2>/dev/null)"; rrc=$?
if [ "$rc" -ne 0 ] || ! jq -e . >/dev/null 2>&1 <<<"$out" || ! has "$(msg "$out")" 'needs jq'; then
  bad "19 no jq is announced in valid JSON" "rc=$rc, got: $out"
elif [ "$rrc" -ne 2 ]; then
  bad "19 no jq is a --report exit 2" "rc=$rrc, got: $rep"
else
  ok "19 without jq it says so in valid JSON and exits 0; --report exits 2"
fi

# 20
scenario "$r1" "$r2"
printf '{"permissions":{"deny":["%s",]}}\n' "$r1" > "$proj/.claude/settings.json"
out="$(run "$root" "$home" "$proj")"; rc=$?
rep="$(run "$root" "$home" "$proj" --report)"; rrc=$?
if [ "$rc" -ne 0 ] || ! has "$(msg "$out")" "$proj/.claude/settings.json"; then
  bad "20 an unparseable settings file names the file" "rc=$rc, got: $out"
elif has "$(msg "$out")" 'not present'; then
  bad "20 an unparseable settings file claims no drift" "got: $out"
elif [ "$rrc" -ne 2 ]; then
  bad "20 an unparseable settings file is --report exit 2" "rc=$rrc, got: $rep"
else
  ok "20 a settings file that will not parse is named, claims nothing, and is exit 2 on --report"
fi

# 21 — silence here would read as all-clear, which is the fail-open direction.
scenario "$r1" "$r2"
printf '{"permissions":{"deny":[]}}\n' > "$root/hooks/permissions.json"
empty="$(run "$root" "$home" "$proj")"
printf 'not json at all\n' > "$root/hooks/permissions.json"
broken="$(run "$root" "$home" "$proj")"
mkroot "$root" "1.2.3" "$r1" "$r2"; chmod 000 "$root/hooks/permissions.json"
unread="$(run "$root" "$home" "$proj")"; urc=$?
chmod 644 "$root/hooks/permissions.json"
if ! has "$(msg "$empty")" 'is empty'; then
  bad "21 an empty shipped deny-list refuses to compare" "got: $empty"
elif ! has "$(msg "$broken")" 'could not be read'; then
  bad "21 an unparseable shipped deny-list refuses to compare" "got: $broken"
elif ! has "$(msg "$unread")" 'could not be read' || [ "$urc" -ne 0 ]; then
  bad "21 an unreadable shipped deny-list refuses to compare" "rc=$urc, got: $unread"
else
  ok "21 a shipped deny-list that is empty, unparseable or unreadable refuses to compare"
fi

# 22
scenario "$r1" "$r2"
printf '{"version":""}\n' > "$root/.claude-plugin/plugin.json"
out="$(run "$root" "$home" "$proj")"
if has "$(msg "$out")" 'install looks wrong'; then
  ok "22 an empty version says the install looks wrong rather than naming no version"
else
  bad "22 an empty version says the install looks wrong" "got: $out"
fi

# 23
scenario "$r1" "$r2"
mkdir -p "$home/.claude/orrery/permissions"
chmod 500 "$home/.claude/orrery/permissions"
out="$(run "$root" "$home" "$proj")"
chmod 700 "$home/.claude/orrery/permissions"
if ! has "$(msg "$out")" '2 deny rules'; then
  bad "23 an unwritable state directory still reports" "got: $out"
elif ! has "$(msg "$out")" 'could not record this'; then
  bad "23 an unwritable state directory says it could not record" "got: $out"
else
  ok "23 an unrecordable finding is reported anyway, and says it will be seen again"
fi

# 24
scenario "$r1" "$r2"
chmod 500 "$proj/.claude"
out="$(run "$root" "$home" "$proj" --reconcile)"; rc=$?
chmod 700 "$proj/.claude"
if [ "$rc" -ne 2 ] || ! has "$out" "$proj/.claude"; then
  bad "24 --reconcile refuses an unwritable .claude" "rc=$rc, got: $out"
else
  ok "24 --reconcile on an unwritable .claude exits 2 and names the path"
fi

# 25 — the N1 case, reachable through this tool's own documented undo procedure.
scenario "$r1" "$r2"
settings "$proj/.claude/settings.json" "$r1"
printf '{"reconciled_deny":["%s",]}\n' "$r2" > "$proj/.claude/orrery-deny.json"
comma="$(run "$root" "$home" "$proj")"
scenario "$r1" "$r2"
settings "$proj/.claude/settings.json" "$r1"
jq -n --argjson d "$(rules "$r2")" '{reconciled_deny:$d}' > "$proj/.claude/orrery-deny.json"
chmod 000 "$proj/.claude/orrery-deny.json"
locked="$(run "$root" "$home" "$proj")"
chmod 600 "$proj/.claude/orrery-deny.json"
if ! has "$(msg "$comma")" '1 deny rule ' || ! has "$(msg "$comma")" 'orrery-deny.json'; then
  bad "25 a trailing comma in the decline record reports everything" "got: $comma"
elif ! has "$(msg "$locked")" '1 deny rule ' || ! has "$(msg "$locked")" 'orrery-deny.json'; then
  bad "25 an unreadable decline record reports everything" "got: $locked"
else
  ok "25 a decline record that will not parse or will not open reports everything, and is named"
fi

# 26
scenario "$r1" "$r2" "$r3"
settings "$proj/.claude/settings.json" "$r1"
run "$root" "$home" "$proj" --reconcile >/dev/null
printf '%s,\n' "$(cat "$proj/.claude/orrery-deny.json")" > "$proj/.claude/orrery-deny.json"
rep="$(run "$root" "$home" "$proj" --report)"; rc=$?
if [ "$rc" -ne 1 ] || ! has "$rep" "$r2" || ! has "$rep" "$r3"; then
  bad "26 a broken decline record un-declines nothing quietly" "rc=$rc, got: $rep"
else
  ok "26 rules declined in an earlier run are reported again once the record breaks"
fi

# 27 — a rate limiter nobody can read must not be able to suppress a message.
scenario "$r1" "$r2"
settings "$proj/.claude/settings.json" "$r1"
sp="$(statepath "$home" "$proj")"
mkdir -p "$(dirname "$sp")"
printf 'not json\n' > "$sp"
out="$(run "$root" "$home" "$proj")"
if ! has "$(msg "$out")" '1 deny rule '; then
  bad "27 an unparseable machine state speaks" "got: $out"
elif ! jq -e '.reported_missing_sha | length > 0' >/dev/null 2>&1 < "$sp"; then
  bad "27 an unparseable machine state is rewritten" "still: $(cat "$sp")"
else
  ok "27 an unreadable rate limiter speaks and repairs itself"
fi

# 28 — deliberate, not the empty-set rule catching a failed comparison.
scenario "$r1" "$r2"
printf '{"permissions":{"deny":["%s",]}}\n' "$r1" > "$proj/.claude/settings.json"
out="$(run "$root" "$home" "$proj" --reconcile)"; rc=$?
if [ "$rc" -ne 2 ] || [ -e "$proj/.claude/orrery-deny.json" ]; then
  bad "28 --reconcile refuses a comparison it could not make" "rc=$rc, out=$out"
else
  ok "28 --reconcile against an unparseable settings file exits 2 and writes nothing"
fi

# 29 — 3 and 2 are different answers; one number for both is a bug with no caller yet.
scenario "$r1"
settings "$proj/.claude/settings.json" "$r1"
run "$root" "$home" "$proj" --reconcile >/dev/null; rc=$?
if [ "$rc" -eq 3 ]; then
  ok "29 nothing to decline is exit 3, distinct from the exit 2 that means could-not-compare"
else
  bad "29 nothing to decline is exit 3" "got rc=$rc"
fi

# 30 — the lab's own case: installed as a checkout, there is no plugin root.
scenario "$r1"
rep="$(run "" "$home" "$proj" --report)"; rc=$?
real="$(jq -r '.permissions.deny[0]' "$here/permissions.json")"
if [ "$rc" -ne 1 ] || ! has "$rep" "$real"; then
  bad "30 an unset CLAUDE_PLUGIN_ROOT falls back to the script's own tree" "rc=$rc, got: $rep"
else
  ok "30 an unset CLAUDE_PLUGIN_ROOT compares against this checkout's own deny-list"
fi

# 31 — emit first, record second. Closing stdout makes the printf fail, and under
#      `set -euo pipefail` that takes the script with it before the state write.
scenario "$r1" "$r2"
env HOME="$home" CLAUDE_PLUGIN_ROOT="$root" bash "$hook" "$proj" >&- 2>/dev/null
sp="$(statepath "$home" "$proj")"
# Read before the next run: that one speaks, and writing state is what it is
# supposed to do — checking afterwards would find the second run's file.
dropped=absent; if [ -e "$sp" ]; then dropped="$(cat "$sp")"; fi
after="$(run "$root" "$home" "$proj")"
if [ "$dropped" != absent ]; then
  bad "31 a dropped message does not advance the state" "state written anyway: $dropped"
elif ! has "$(msg "$after")" '2 deny rules'; then
  bad "31 a dropped message is said again next time" "got: $after"
else
  ok "31 a message that never reached the harness is not recorded as said"
fi

# --- the shape of the output ------------------------------------------------

# 32
scenario "$r1" "$r2"
out="$(run "$root" "$home" "$proj")"
if jq -e . >/dev/null 2>&1 <<<"$out"; then
  ok "32 hook mode emits valid JSON"
else
  bad "32 hook mode emits valid JSON" "got: $out"
fi

# 33 — principle 2, pinned in a test rather than in a comment: a systemMessage
#      reaches the user and not the model, so the model cannot "fix" this by
#      editing the settings file the finding is about.
if [ "$(jq -r 'keys | join(",")' <<<"$out" 2>/dev/null)" = "systemMessage" ]; then
  ok "33 hook mode emits systemMessage and nothing else"
else
  bad "33 hook mode emits systemMessage and nothing else" \
      "keys: $(jq -r 'keys | join(",")' <<<"$out" 2>/dev/null)"
fi

# 34
scenario "$r1" "$r2"
settings "$proj/.claude/settings.json" "$r1" "$r2"
run "$root" "$home" "$proj" --report >/dev/null; clean=$?
settings "$proj/.claude/settings.json" "$r1"
run "$root" "$home" "$proj" --report >/dev/null; behind=$?
printf 'not json\n' > "$proj/.claude/settings.json"
cannot="$(run "$root" "$home" "$proj" --report)"; crc=$?
if [ "$clean" -ne 0 ] || [ "$behind" -ne 1 ] || [ "$crc" -ne 2 ]; then
  bad "34 --report exits 0 / 1 / 2" "clean=$clean behind=$behind cannot=$crc"
elif grep -qi 'missing' <<<"$cannot"; then
  bad "34 the exit-2 wording never says missing" "got: $cannot"
else
  ok "34 --report exits 0 clean, 1 behind, 2 could-not-compare, and never calls the third the second"
fi

# 35 — the anti-hiding property: a wrong --reconcile must not be able to leave a
#      green run that looks like a project with nothing declined.
scenario "$r1" "$r2"
settings "$proj/.claude/settings.json" "$r1"
run "$root" "$home" "$proj" --reconcile >/dev/null
rep="$(run "$root" "$home" "$proj" --report)"; rc=$?
if [ "$rc" -ne 0 ]; then
  bad "35 a fully declined project reports clean" "rc=$rc, got: $rep"
elif ! has "$rep" 'or recorded below as declined'; then
  bad "35 a declined-clean project does not read as a merged one" "got: $rep"
elif ! has "$rep" '1 rules recorded as declined' || ! has "$rep" "$proj/.claude/orrery-deny.json"; then
  bad "35 a clean --report still prints the declined count and path" "got: $rep"
else
  ok "35 --report prints the declined count and the record's path on a clean run too"
fi

# 36
printf '%s,\n' "$(cat "$proj/.claude/orrery-deny.json")" > "$proj/.claude/orrery-deny.json"
rep="$(run "$root" "$home" "$proj" --report)"
if has "$rep" 'recorded as declined'; then
  bad "36 an unreadable decline record is not printed as a count" "got: $rep"
elif ! has "$rep" 'could not be read' || ! has "$rep" "$proj/.claude/orrery-deny.json"; then
  bad "36 an unreadable decline record says so, and names itself" "got: $rep"
else
  ok "36 an unreadable decline record is reported as unreadable, never as zero declined"
fi

# --- ranking ----------------------------------------------------------------
# The classes live in the shipped file, so a fixture root has none until this
# plants them — which is itself case 39: a checker meeting a file without
# `_classes` must say exactly what it said before ranking existed.
withclasses() { # $1 = root
  jq '._classes = [
        {name:"credentials", line:"expose a credential", match:["Bash(orrery-cred"]},
        {name:"data loss",   line:"discard work with no way back", match:["Bash(orrery-loss"]}
      ]' "$1/hooks/permissions.json" > "$1/hooks/p.x" \
    && mv "$1/hooks/p.x" "$1/hooks/permissions.json"
}
cred='Bash(orrery-cred-one:*)'; loss='Bash(orrery-loss-one:*)'; plain='Bash(orrery-plain-one:*)'

# 37 — planted in the order plain, loss, cred so that lexical order and class
#      order disagree; a report that merely sorted would fail this.
scenario "$plain" "$loss" "$cred"
withclasses "$root"
rep="$(run "$root" "$home" "$proj" --report)"
order="$(grep -E '^  [A-Z]' <<<"$rep" | tr -d ' ' | tr '\n' ' ')"
if [ "$order" != "CREDENTIALS DATALOSS OTHER " ]; then
  bad "37 groups run worst first" "got: $order"
elif ! has "$rep" "$plain"; then
  bad "37 a rule matching no class is still printed" "got: $rep"
else
  ok "37 the report groups by class, worst first, and hides nothing"
fi

# 38 — the count alone cannot say which of the missing rules matter.
out="$(run "$root" "$home" "$proj")"
if ! has "$(msg "$out")" 'including 1 that expose a credential'; then
  bad "38 the hook line names the worst class and its count" "got: $(msg "$out")"
else
  ok "38 the hook line names the worst class present and how many are in it"
fi

# 39 — no classes: every rule still reported, and no class clause invented.
scenario "$plain" "$loss" "$cred"
out="$(run "$root" "$home" "$proj")"
rep="$(run "$root" "$home" "$proj" --report)"
if has "$(msg "$out")" 'including'; then
  bad "39 a shipped file with no classes names no class" "got: $(msg "$out")"
elif ! has "$rep" "$cred" || ! has "$rep" "$loss" || ! has "$rep" "$plain"; then
  bad "39 every rule is reported when there are no classes" "got: $rep"
else
  ok "39 a shipped file without _classes reports every rule and names no class"
fi

printf '\n%s cases, %s passing, %s failing\n' "$((pass + fail))" "$pass" "$fail"
[ "$fail" -eq 0 ]
