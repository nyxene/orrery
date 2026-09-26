#!/usr/bin/env bash
# Tests install/ci/retrospective-on-close.sh, and the one property of the
# workflow that calls it which a suite can reach without GitHub.
#
#   install/ci/retrospective-on-close.test.sh
#
# The matcher decides whether a host's issue is reopened, so both directions
# are failures with a cost: a false "owed" reopens finished work on someone
# else's tracker, a false "fine" is the silence the gate exists to end.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
m="$here/retrospective-on-close.sh"
yml="$here/retrospective-on-close.yml"

pass=0 fail=0
ok()  { pass=$((pass + 1)); printf '\033[32m✓\033[0m %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '\033[31m✗\033[0m %s — %s\n' "$1" "$2"; }

case_() { # $1 = name, $2 = expected exit, $3 = state_reason, $4 = comments JSON
  local rc
  printf '%s' "$4" | bash "$m" "$3" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq "$2" ]; then ok "$1"; else bad "$1" "exit $rc, expected $2"; fi
}

retro='## Retrospective — ISSUE\n\n<!-- retrospective\nspend: not captured\n-->\n'
waiver='<!-- orrery-waiver\nreason: duplicate of an earlier issue\n-->\n\nClosed without a retrospective, on purpose.'

printf 'install/ci/retrospective-on-close.sh\n\n'

# --- owed -------------------------------------------------------------------
case_ "a completed close with no comments owes one"               1 completed '[]'
case_ "and with comments that are not a retrospective"           1 completed '["LGTM","looks good, merging"]'
# The loose test is the wrong one: a comment that talks about retrospectives
# is not one. Only the header `close-issue.sh` writes counts.
case_ "prose mentioning a retrospective is not one"              1 completed '["retrospective to follow","## Retrospective (later)"]'
# An older event, or a host's API, may carry no reason at all. Checked rather
# than exempted: the exemption is for what is known not to be finished work.
case_ "no state_reason at all is checked, not exempted"          1 ''        '[]'

# --- not owed ---------------------------------------------------------------
case_ "the retrospective header satisfies it"                    0 completed "[\"$retro\"]"
case_ "anywhere among other comments"                            0 completed "[\"LGTM\",\"$retro\",\"thanks\"]"
case_ "a recorded waiver satisfies it"                           0 completed "[\"$waiver\"]"
case_ "not_planned is not finished work"                         0 not_planned '[]'
case_ "duplicate is not finished work"                           0 duplicate   '[]'

# --- unreadable is not clean ------------------------------------------------
# Exit 2 fails the run and reopens nothing. A bookkeeping gate that acted on
# input it could not read would reopen every issue on a transient API error.
case_ "input that is not JSON cannot be read"                    2 completed 'not json'
case_ "an object instead of an array cannot be read"             2 completed '{"body":"x"}'
case_ "an array of non-strings cannot be read"                   2 completed '[{"body":"x"}]'
case_ "empty input cannot be read"                               2 completed ''

# An exempt reason must still drain its input. Exiting before reading left the
# writer to die on SIGPIPE once the payload outgrew the pipe buffer: under
# pipefail that was a red run on every not-planned close of a long thread.
big="[$(printf '"%s",' $(seq 1 60000) | sed 's/,$//')]"
rc=0; printf '%s' "$big" | bash "$m" not_planned >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then ok "an exempt reason drains a large payload and exits clean"
else bad "an exempt reason drains a large payload and exits clean" "pipeline exit $rc"; fi

# --- the two markers do not overlap -----------------------------------------
# The doctor counts retrospectives with `contains("<!-- retrospective")`. If the
# waiver marker shared that prefix, every waiver would be counted as a
# retrospective and the two numbers the doctor keeps apart would merge.
if printf '%b' "$waiver" | grep -qF '<!-- retrospective'; then
  bad "the waiver marker is not a retrospective to the doctor" "it contains the retrospective prefix"
else
  ok "the waiver marker is not a retrospective to the doctor"
fi

# --- the workflow's own words -----------------------------------------------
# The reopen comment is posted on the issue it reopens. If it contained either
# marker it would satisfy the next check itself, and the doctor would count the
# nag as a retrospective. The whole file is refused, header included, so the
# header cannot quote them either.
for mk in '<!-- retrospective' '<!-- orrery-waiver'; do
  if grep -qF -- "$mk" "$yml"; then
    bad "the workflow never writes a marker it checks for" "$yml contains $mk"
  else
    ok "the workflow never writes $mk"
  fi
done

# And the reopen comment names the command that closes it properly — the
# comment's whole job — with the escape for a session that did not do the work.
for want in 'close-issue.sh ISSUE_N --what' '--not-captured' '--waive' '--no-close'; do
  if grep -qF -- "$want" "$yml"; then ok "the reopen comment names $want"
  else bad "the reopen comment names $want" "not in $yml"; fi
done

# This repository runs the workflow from its own `.github/workflows/`, and
# GitHub reads nothing else. A copy is a copy: the day one is edited and the
# other is not, the lab runs a gate the product does not ship, or the reverse.
lab_copy="$here/../../.github/workflows/retrospective-on-close.yml"
if [ ! -f "$lab_copy" ]; then
  ok "no lab copy to compare (running outside the workshop)"
elif cmp -s "$yml" "$lab_copy"; then
  ok "this repository runs the same workflow it ships"
else
  bad "this repository runs the same workflow it ships" "$lab_copy differs from $yml"
fi

printf '\n%s cases, %s failing\n' "$((pass + fail))" "$fail"
[ "$fail" -eq 0 ]
