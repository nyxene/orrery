#!/usr/bin/env bash
# Does an issue that just closed owe a retrospective?
#
#   install/ci/retrospective-on-close.sh <state_reason> < comments.json
#
# comments.json is a JSON array of comment bodies, as strings. Exit 0 when
# nothing is owed, 1 when the issue closed as finished work and carries no
# retrospective, 2 when the input cannot be read. The reason is printed either
# way, because a gate that says only yes or no gets deleted the first time it
# is wrong and nobody can tell why.
#
# Called from `install/ci/retrospective-on-close.yml` on `issues: closed`.
#
# ## Why this exists
#
# `hooks/process-guard.sh` refuses a bare `gh issue close` typed in a session
# and routes it through `skills/build/close-issue.sh`, which posts the
# retrospective first. A merge never passes through it: GitHub closes an issue
# named by `Closes #N` server-side, after the button, from an event no local
# hook sees. Measured on one host over a week: more than a hundred issues
# closed as finished work, one carrying a retrospective — while every merged
# pull request named an issue, because a gate enforced that half.
#
# ## The predicate, and why it is borrowed
#
# A comment containing `<!-- retrospective` — the machine-readable header
# `close-issue.sh` writes, and the exact test the doctor counts with. One
# definition, two readers, so the number the doctor reports and the issues this
# reopens can never disagree about what a retrospective is.
#
# `<!-- orrery-waiver` also satisfies it: that is `close-issue.sh --waive`, a
# close without a retrospective that somebody decided on and gave a reason for.
# It shares no prefix with the retrospective marker on purpose — the doctor must
# not count a skip as a retrospective.
#
# ## What is exempt
#
# A `state_reason` of `not_planned` or `duplicate`: those are not finished work,
# and a retrospective of work that did not happen is a form filled in for its
# own sake. Anything else — `completed`, or no reason at all from an older
# event — is checked.
#
# ## An unreadable answer is not a clean one
#
# Input that is not a JSON array of strings exits 2. The workflow fails the run
# and reopens nothing: a bookkeeping gate that acts on what it could not read is
# worse than one that stops and says so.
set -uo pipefail

reason="${1-}"

# Read everything first, whatever the reason. Exiting before stdin is consumed
# leaves the writer to die on SIGPIPE once the payload outgrows the pipe
# buffer — a red run on every exempt close of a long thread, the noise that
# gets a gate removed.
comments="$(cat)"

case "$reason" in
  not_planned|duplicate)
    printf 'closed as %s, which is not finished work — nothing owed\n' "$reason"
    exit 0 ;;
esac

command -v jq >/dev/null 2>&1 || { printf 'jq is missing — cannot read the comments\n'; exit 2; }

if ! printf '%s' "$comments" | jq -e 'type == "array" and all(.[]; type == "string")' >/dev/null 2>&1; then
  printf 'the comments are not a JSON array of strings — cannot tell, so nothing is done\n'
  exit 2
fi

if printf '%s' "$comments" | jq -e 'any(.[]; contains("<!-- retrospective"))' >/dev/null; then
  printf 'a retrospective is on the issue — nothing owed\n'
  exit 0
fi

if printf '%s' "$comments" | jq -e 'any(.[]; contains("<!-- orrery-waiver"))' >/dev/null; then
  printf 'closed with a recorded waiver — nothing owed\n'
  exit 0
fi

printf 'closed as finished work with no retrospective on it\n'
exit 1
