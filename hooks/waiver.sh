#!/usr/bin/env bash
# The record of a deliberate skip. One line per waived obligation.
#
#   hooks/waiver.sh <act> <reason> [command|stated]
#
# ## Why this exists rather than a rule saying "write it down"
#
# Measured across three host projects over one week: 179 issues closed, 218
# pull requests merged, 2 retrospectives. Nothing in the method had a refusal
# behind it, so compliance and non-compliance left identical traces — which is
# to say no trace at all, and the only reason anyone found out was the owner
# going and looking.
#
# A gate fixes half of that. This file fixes the other half: **the only way
# past a gate is a command that writes this line.** Skipping stays possible, on
# purpose — the same argument `--no-verify` earns in the pre-commit hook — but
# it stops being free and it stops being invisible. Either a row here carries a
# reason, or the gate was circumvented, and that is a violation with a name
# instead of a silence indistinguishable from obedience.
#
# ## Two sources, one file
#
# `command` is a waiver that rode on the command line and was recorded by
# `hooks/process-guard.sh`. `stated` is a session writing down an instruction
# that arrived as prose — "no retrospective, keep going". The second cannot be
# detected: matching free speech for permission-to-skip fails in both
# directions, so it is written by the session that heard it.
#
# The field says how the waiver arrived and nothing more. It deliberately does
# **not** claim who authorized it. The first draft called the hook path `typed`
# and glossed that as the owner spelling the token himself, which was false on
# every automated row — the token is spelled by whichever agent composed the
# Bash call. A provenance field that always reports the strongest class is
# worse than no field, because it launders a self-authorized skip as an
# approved one.
#
# ## Never trimmed
#
# `hooks/call-log.sh` caps itself at 256 KiB and drops its oldest rows. One
# host project's log was at 252 800 bytes on the day this was written, giving
# it a two-day window — so "what did we waive last month" is a question that
# log cannot answer and this one must. There is no cap here and no rotation.
# The file grows by a line per deliberate skip; a project where that is large
# has told you something.
set -euo pipefail

act="${1:-}"
reason="${2:-}"
source="${3:-stated}"

if [ -z "$act" ] || [ -z "$reason" ]; then
  printf 'usage: waiver.sh <act> <reason> [command|stated]\n' >&2
  printf 'A waiver with no reason is not a record — it is the silence this file exists to end.\n' >&2
  exit 1
fi

case "$source" in command|stated) ;; *)
  printf 'waiver.sh: source must be `command` or `stated`, not %s\n' "$source" >&2
  exit 1 ;;
esac

# `.orrery/local/waivers.tsv` in the main checkout, found by git from the
# directory this runs in — a person's project, or the session's tree when the
# process guard calls. Never a path relative to that directory: one host project
# collected twenty call logs as deep as six directories that way. Outside a
# repository it refuses, because a waiver written somewhere nobody will look is
# worse than the refusal — it reads as recorded. `ORRERY_WAIVER_LOG`, read for
# one release, names only the old file whose rows are carried over.
here="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=hooks/orrery-config.sh
. "$here/orrery-config.sh"
if ! log="$(orrery_local_file waivers.tsv "${ORRERY_WAIVER_LOG:-.claude/orrery-waivers.tsv}")"; then
  printf 'waiver.sh: not inside a git repository, so there is nowhere to record this.\n' >&2
  printf 'Run it from inside the project.\n' >&2
  exit 1
fi

session="${ORRERY_WAIVE_SESSION:-}"
if [ -z "$session" ]; then
  raw="${CLAUDE_CODE_SESSION_ID:-nosession}"
  if command -v shasum >/dev/null 2>&1; then
    session="$(printf '%s' "$raw" | shasum -a 256 2>/dev/null | cut -c1-8 || true)"
  elif command -v sha256sum >/dev/null 2>&1; then
    session="$(printf '%s' "$raw" | sha256sum 2>/dev/null | cut -c1-8 || true)"
  fi
  [ -n "$session" ] || session=nohash
fi

# One waiver is one line, and both of the fields below are free text the caller
# chose. A newline in a reason would end the record early and start a second
# one — a forged row with a chosen timestamp and a chosen act, in the one file
# whose whole value is that it cannot be quietly edited by the party it
# incriminates. Tabs do the same thing one field over.
clean() { LC_ALL=C tr -d '\000-\037\177' <<<"$1"; }

printf '%s\t%s\t%s\t%s\t%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$(clean "$session")" \
  "$source" \
  "$(clean "$act")" \
  "$(clean "$reason")" >> "$log"

printf 'waived: %s — %s\nrecorded in %s\n' "$act" "$reason" "$log" >&2
