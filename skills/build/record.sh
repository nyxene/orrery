#!/usr/bin/env bash
# The record of a piece of work, written as a file in the work's own tree.
#
#   skills/build/record.sh write --what "<one line>" [--since <iso8601>]
#                                [--retries <n>] [--not-captured] [--final]
#   skills/build/record.sh write --body-file <path> [--work <name>] [--final]
#   skills/build/record.sh close refused|withdrawn|answered|enacted --why "<one line>"
#
# It lands at `.orrery/work/<work>/retrospective.md`, where `<work>` is the
# worktree's name, or the branch on the main checkout, and is committed with the work, so it travels in the pull
# request and reaches the default branch with it. Nothing here talks to a
# tracker: the record is in the repository whether the project has one or not.
#
# ## Two acts, and why merged work needs no third
#
# `write` is re-runnable: run it before every push and it refreshes the spend and
# the retries. It names no outcome, because arriving on the default branch
# through the merge **is** the closing act — a line written after the merge would
# need a pull request of its own under a protected branch.
#
# `close` is for work that ends without merging — refused, withdrawn, a question
# answered, a decision enacted. It writes the outcome once, on the branch, and
# refuses to overwrite one: an outcome that can be rewritten is not a record.
# The branch keeps it.
#
# `--final` on `write`, and every `close`, delete the work's `handoff.md`: a
# handoff is residue for the next session, and closed work has no next session.
#
# ## The spend half, and the honest blank
#
# `retrospect.sh` builds the table from this session's transcripts, from the
# branch's first reflog entry unless `--since` says otherwise — so a session
# that worked on three branches bills each its own window. Where nothing is
# readable, or the session writing this did not do the work (`--not-captured`),
# the cells say `not captured`: an invented number cannot be told from a real
# one later, which is the only reason the table exists. Its stderr reaches the
# caller, because a wrong directory reads the wrong transcripts and a swallowed
# message turns that into a permanent blank that looks genuine.
#
# A phase or an umbrella is summed from its children's records rather than
# measured here — the closer's spend is not the phase's — so `--body-file`
# writes an assembled record verbatim, and `--work` files it under the phase's
# own name rather than the name of the work that happened to empty it.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=hooks/orrery-config.sh
. "$here/../../hooks/orrery-config.sh"

die() { printf 'record.sh: %s\n' "$1" >&2; exit 1; }
usage() {
  sed -n '4,7p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 1
}

act="${1:-}"; [ $# -gt 0 ] && shift
outcome=""
case "$act" in
  write) ;;
  close) outcome="${1:-}"; [ $# -gt 0 ] && shift
         case "$outcome" in refused|withdrawn|answered|enacted) ;;
           *) die "close takes refused, withdrawn, answered or enacted — merged work is closed by its merge" ;; esac ;;
  *) usage ;;
esac

what="" since="" retries="" notcaptured=0 final=0 bodyfile="" work_arg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --what|--why) what="${2:-}"; shift 2 ;;
    --since)      since="${2:-}"; shift 2 ;;
    --retries)    retries="${2:-}"; shift 2 ;;
    --body-file)  bodyfile="${2:-}"; shift 2 ;;
    --work)       work_arg="${2:-}"; shift 2 ;;
    --not-captured) notcaptured=1; shift ;;
    --final)      final=1; shift ;;
    *) die "unknown argument $1" ;;
  esac
done
[ -n "$what" ] || [ -n "$bodyfile" ] || die "--what (or --why) is the one line of what happened; numbers with no story are a bill with no invoice"
[ -z "$bodyfile" ] || [ -f "$bodyfile" ] || die "no such body file: $bodyfile"
[ -z "$bodyfile" ] || [ -z "$outcome" ] || die "close measures and writes its own record; --body-file is for an assembled one"

top="$(orrery_toplevel .)"; [ -n "$top" ] || die "not inside a git repository, so there is no work to record"
work="${work_arg:-$(orrery_work .)}"
case "$work" in ''|*/*|.*) die "--work takes a plain name: $work" ;; esac
dir="$top/.orrery/work/$work"
rec="$dir/retrospective.md"

if [ -f "$rec" ] && grep -q '^outcome: ' "$rec"; then
  die "$rec already carries its outcome ($(sed -n 's/^outcome: //p' "$rec" | head -1)); a closed record is not rewritten"
fi

# The window: the branch's first reflog entry, which is when this work began.
if [ -z "$since" ] && branch="$(git -C "$top" symbolic-ref --short -q HEAD)"; then
  since="$(orrery_born "$branch" "$top")"
fi

blank() { # $1 = why the cells are blank
  printf '<!-- retrospective\nspend: not captured\nretries: %s\n-->\n\n' "${retries:-not recorded}"
  printf '| Stage | Model | Output tok | Input tok | Cache read | Cache write | Tool calls |\n'
  printf '|---|---|---:|---:|---:|---:|---:|\n'
  printf '| — | not captured | not captured | not captured | not captured | not captured | not captured |\n\n%s\n' "$1"
}

if [ -n "$bodyfile" ]; then
  body="$(cat "$bodyfile")"
else
  args=(); [ -n "$since" ] && args+=(--since "$since"); [ -n "$retries" ] && args+=(--retries "$retries")
  if [ "$notcaptured" -eq 1 ]; then
    spend="$(blank "Written from a session other than the one that did the work, so every cell is \`not captured\` rather than the writer's own spend.")"
  else
    spend="$("$here/retrospect.sh" "${args[@]+"${args[@]}"}" || true)"
    [ -n "$spend" ] || spend="$(blank "No transcripts were readable for this session, so every cell is \`not captured\` rather than an estimate.")"
  fi
  # The outcome rides in the machine block too, where a later reader sums it.
  [ -z "$outcome" ] || spend="$(awk -v o="$outcome" 'NR == 1 && /^<!-- retrospective$/ { print; print "outcome: " o; next } { print }' <<<"$spend")"
  body="# Retrospective — $work

${outcome:+**Outcome: $outcome.** }$what

$spend"
fi

mkdir -p "$dir"
printf '%s\n' "$body" > "$rec"
if [ "$final" -eq 1 ] || [ -n "$outcome" ]; then rm -f "$dir/handoff.md"; fi
printf '%s %s — commit it with the work\n' "$( [ -n "$outcome" ] && echo "closed as $outcome:" || echo written:)" "${rec#"$top"/}" >&2
