#!/usr/bin/env bash
# Closes an issue the only way `hooks/process-guard.sh` permits: by posting its
# retrospective first.
#
#   skills/build/close-issue.sh <issue> --what "<one line>" [--since <iso8601>]
#                               [--repo <owner/name>] [--dry-run]
#                               [--no-close] [--not-captured]
#   skills/build/close-issue.sh <issue> --waive "<reason>"
#
# `--no-close` posts and leaves the issue open, for the order `build` uses: the
# retrospective goes up **before** the merge, so the pull request's `Closes #N`
# never closes a bare issue. Posted after, it loses a race with
# `install/ci/retrospective-on-close.yml`, which reopens a completed close that
# carries no retrospective — every compliant session would be reopened and
# nagged, on exactly the issues that did it right.
#
# `--not-captured` is for closing an issue from a session that did not do the
# work — the usual case after that workflow reopens one. Measuring this
# session's transcripts there posts the closer's spend as the work's: a real-
# looking number that is the wrong one, which is worse than no number.
#
# `--waive` is the server-side half of `ORRERY_WAIVE`. The local waiver writes a
# row nobody else can see, so the workflow would reopen the close it excused.
# This posts a marker the workflow reads — `<!-- orrery-waiver`, deliberately
# not sharing a prefix with `<!-- retrospective`, which is what keeps a skip
# from being counted as a retrospective — records the row, and closes.
#
# ## Why the two acts are one command
#
# The guard could have checked that a retrospective comment exists and allowed
# `gh issue close` when it did. That costs a network call inside a hook running
# before every Bash command, and it is satisfied by any comment at all. Doing
# both here instead means there is nothing to verify: the only close that
# happens is one that posted.
#
# ## The minimum form, and why it is smaller than the phase one
#
# A phase retrospective has four parts, per
# `rules/git/closing-an-umbrella-posts-the-phase-retrospective.md`: the
# machine-readable header, the spend table, a `gh`-queried wall-clock table and
# a numbered list of what happened. All four are right for a phase
# closing over sixteen pull requests. Demanding all four on a one-line fix is
# how a rule gets routed around — and a rule nobody follows measured 2
# retrospectives against 179 closed issues.
#
# So an ordinary issue carries the header, the spend table and one line. Both
# generated parts cost nothing to produce, which is the point: the half that
# actually answers "what did this cost" is the half no human has to write.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"

issue="" what="" since="" repo="" dry=0 bodyfile="" noclose=0 notcaptured=0 waive=""
while [ $# -gt 0 ]; do
  case "$1" in
    --body-file) bodyfile="${2:-}"; shift 2 ;;
    --what)  what="${2:-}"; shift 2 ;;
    --since) since="${2:-}"; shift 2 ;;
    --repo)  repo="${2:-}"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    --no-close) noclose=1; shift ;;
    --not-captured) notcaptured=1; shift ;;
    --waive) waive="${2:-}"; [ -n "$waive" ] || { printf 'close-issue.sh: --waive needs a reason\n' >&2; exit 1; }; shift 2 ;;
    -*) printf 'close-issue.sh: unknown option %s\n' "$1" >&2; exit 1 ;;
    *)  [ -n "$issue" ] || issue="$1"; shift ;;
  esac
done

if [ -n "$waive" ] && { [ -n "$what" ] || [ -n "$bodyfile" ] || [ "$noclose" -eq 1 ]; }; then
  printf 'close-issue.sh: --waive is a close without a retrospective; it takes no --what, --body-file or --no-close\n' >&2
  exit 1
fi

if [ -z "$issue" ] || { [ -z "$what" ] && [ -z "$bodyfile" ] && [ -z "$waive" ]; }; then
  printf 'usage: close-issue.sh <issue> --what "<one line>" [--since <iso8601>]\n' >&2
  printf '       close-issue.sh <issue> --body-file <path>\n' >&2
  printf '\n--what is the numbered list, compressed to the one line an ordinary\n' >&2
  printf 'issue earns. Numbers with no story are a bill with no invoice.\n' >&2
  printf '\n--body-file posts a retrospective you assembled yourself, which is what\n' >&2
  printf 'closing an umbrella needs: the phase form is summed from the children\n' >&2
  printf 'rather than measured from this session, whose transcripts are the\n' >&2
  printf 'closer'"'"'s and not the work'"'"'s.\n' >&2
  exit 1
fi

if [ -n "$bodyfile" ] && [ ! -f "$bodyfile" ]; then
  printf 'close-issue.sh: no such body file: %s\n' "$bodyfile" >&2
  exit 1
fi

case "$issue" in
  ''|*[!0-9]*) printf 'close-issue.sh: %s is not an issue number\n' "$issue" >&2; exit 1 ;;
esac

# The spend half. `retrospect.sh` exits 2 when there is nothing on disk to read,
# and the honest answer there is `not captured` rather than a plausible number —
# an invented figure cannot be told from a real one later, which is the only
# reason the table exists at all.
# Its stderr reaches the caller rather than `/dev/null`. A wrong working
# directory builds the wrong transcript path, and swallowing the message posts a
# permanent `not captured` table indistinguishable from a genuine one — the
# exact substitution of a plausible answer for an honest one that the table
# exists to prevent.
spend=""
if [ -n "$bodyfile" ] || [ -n "$waive" ]; then
  :
elif [ "$notcaptured" -eq 1 ]; then
  spend='<!-- retrospective
spend: not captured
-->

| Stage | Output tok | Input tok | Tool calls |
|---|---:|---:|---:|
| — | not captured | not captured | not captured |

Closed from a session other than the one that did the work, so this session'"'"'s
transcripts are not the work'"'"'s and every cell above is `not captured` rather
than the closer'"'"'s spend.'
elif [ -n "$since" ]; then
  spend="$("$here/retrospect.sh" --since "$since" || true)"
else
  spend="$("$here/retrospect.sh" || true)"
fi
if [ -z "$bodyfile" ] && [ -z "$waive" ] && [ -z "$spend" ]; then
  spend='<!-- retrospective
spend: not captured
-->

| Stage | Output tok | Input tok | Tool calls |
|---|---:|---:|---:|
| — | not captured | not captured | not captured |

No transcripts were readable for this session, so every cell above is
`not captured` rather than an estimate.'
fi

gh_args=()
[ -n "$repo" ] && gh_args=(--repo "$repo")

# One `gh` field, because "how long was this open" is the other half of "what
# did it cost" and it is a single lookup. The full wall-clock table stays with
# the phase retrospective, where there are pull requests to tabulate.
opened="$(gh issue view "$issue" "${gh_args[@]+"${gh_args[@]}"}" --json createdAt --jq '.createdAt' 2>/dev/null || true)"

body="$(mktemp "${TMPDIR:-/tmp}/orrery-retro.XXXXXX")"
trap 'rm -f "$body"' EXIT
if [ -n "$waive" ]; then
  printf '<!-- orrery-waiver\nreason: %s\n-->\n\nClosed without a retrospective, on purpose: %s\n' "$waive" "$waive" > "$body"
elif [ -n "$bodyfile" ]; then
  # Posted verbatim. An assembled phase retrospective is the caller's work and
  # nothing here is entitled to append this session's numbers to it — those are
  # the closer's spend, not the phase's, and the two under one heading is
  # exactly the misreading the format exists to prevent.
  cat "$bodyfile" > "$body"
else
  {
    printf '## Retrospective — #%s\n\n' "$issue"
    printf '%s\n\n' "$spend"
    printf '### What happened\n\n%s\n' "$what"
    if [ -n "$opened" ]; then
      if [ "$noclose" -eq 1 ]; then printf '\nOpened %s, posted before the merge %s.\n' "$opened" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      else printf '\nOpened %s, closed %s.\n' "$opened" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; fi
    fi
  } > "$body"
fi

if [ "$dry" -eq 1 ]; then
  cat "$body"
  printf '\n--dry-run: nothing was posted and #%s is still open.\n' "$issue" >&2
  exit 0
fi

gh issue comment "$issue" "${gh_args[@]+"${gh_args[@]}"}" --body-file "$body" >&2
if [ "$noclose" -eq 1 ]; then
  printf 'retrospective posted; #%s left open for the merge to close\n' "$issue" >&2
  exit 0
fi
if [ -n "$waive" ]; then
  bash "$here/../../hooks/waiver.sh" "gh issue close #$issue" "$waive" command >&2 || true
fi
gh issue close "$issue" "${gh_args[@]+"${gh_args[@]}"}" --reason completed >&2
if [ -n "$waive" ]; then printf 'closed #%s, waiver posted and recorded\n' "$issue" >&2
else printf 'closed #%s, retrospective posted\n' "$issue" >&2; fi
