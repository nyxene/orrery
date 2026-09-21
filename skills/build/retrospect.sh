#!/usr/bin/env bash
# Builds the resource half of a retrospective from the session's own transcripts.
#
#   skills/build/retrospect.sh [session-id] [--since <iso8601>]
#
# The rule this feeds — rules/process/retrospectives-always-use-the-table-format.md
# — used to say subagent token and tool-call data "does not persist anywhere once
# a conversation ends". That was wrong, and it was the reason the format demanded
# numbers nothing instructed anyone to capture. Every spawned agent leaves a
# transcript under ~/.claude/projects/<project>/<session>/subagents/ with its
# usage block, its tool calls and its timestamps, and a sibling .meta.json naming
# what it was. The data was on disk the whole time; nothing read it.
#
# So there is no bookkeeping in the hot path. Run this at step 9, after the work
# has landed, and it reconstructs what each stage cost.
#
# What it does NOT produce: the `gh`-queried wall-clock table and the numbered
# list of what happened. Those come from the tracker and from you.
#
# ## The main session is a row, and for months it was not one
#
# This read `<session>/subagents/` and nothing else, so a table headed "resources
# spent" was silent about the session doing the spending. Measured once: a phase
# whose agents cost 221 283 output tokens ran in a main session that cost
# 552 450 — the larger half, missing. Worse, an issue closed without spawning
# anything at all produced `exit 2` and no table, which is most issues in most
# projects, so the honest cell was unobtainable rather than merely empty.
#
# The primary transcript sits beside the directory at `<session>.jsonl` and has
# the same shape, so it is summed by the same jq and printed as its own row.
#
# **Every total has an `agent_` and a `main_` sibling**, not only the output
# tokens. The first draft split that one family and left `input_tokens`,
# `cache_read_tokens` and `tool_calls` silently changed from agents-only to
# agents-plus-main under their old names — which an audit caught before it
# shipped. The phase retrospective assembles itself by summing these header
# blocks across issues, so one key meaning two things across a version boundary
# is the whole failure that assembly exists to avoid.
#
# ## --since, because a session closes more than one issue
#
# The glob takes every agent transcript in the session, so a second run in the
# same session re-counted the first run's agents; the same defect summed two
# phases into one table and someone split it by hand. `--since` filters
# *events*, not files, which is what makes it work on the main transcript too:
# one continuous file that has to be attributed to whichever issue is closing
# now. Timestamps are ISO-8601 UTC in one format, so the comparison is
# lexicographic. An event carrying no timestamp cannot be placed and is dropped
# when --since is given, which is the conservative direction: it under-reports
# rather than crediting this issue with a neighbour's spend.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "retrospect.sh needs jq" >&2; exit 1; }

since="" sess_arg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --since)
      since="${2:-}"
      [ -n "$since" ] || { echo "--since needs an ISO-8601 timestamp" >&2; exit 1; }
      shift 2
      ;;
    --since=*) since="${1#--since=}"; shift ;;
    # Validated rather than trusted. The comparison below is lexicographic over
    # transcript timestamps, which are uniform UTC — so a local-offset value,
    # one carrying a `+02:00` tail rather than a `Z`, or a typo does not fail;
    # it silently
    # filters wrongly, and a wrong window is a wrong bill nobody can spot.
    -*) echo "retrospect.sh: unknown option $1" >&2; exit 1 ;;
    *) [ -n "$sess_arg" ] || sess_arg="$1"; shift ;;
  esac
done

case "$since" in
  '') ;;
  [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]Z) ;;
  *) printf '%s is not an ISO-8601 UTC timestamp (YYYY-MM-DDTHH:MM:SSZ).\n' "$since" >&2
     printf 'The window is compared as text against transcript timestamps, which are\n' >&2
     printf 'always UTC — an offset or a typo filters silently rather than failing.\n' >&2
     exit 1 ;;
esac

session="${sess_arg:-${CLAUDE_CODE_SESSION_ID:-}}"
proj="$HOME/.claude/projects/$(pwd -P | sed 's|/|-|g')"

if [ -z "$session" ]; then
  # No id given and none in the environment: take the most recently written one.
  session="$(ls -t "$proj" 2>/dev/null | grep -vE '^memory$|\.jsonl$' | head -1)" || true
fi

dir="$proj/$session/subagents"
main="$proj/$session.jsonl"

shopt -s nullglob
files=()
[ -d "$dir" ] && files=("$dir"/agent-*.jsonl)

# Nothing at all to read is the only case that refuses. An issue closed without
# spawning anything is the ordinary case, not a failure, and it still has the
# main session to report.
if [ ${#files[@]} -eq 0 ] && [ ! -f "$main" ]; then
  echo "No transcripts for session ${session:-<none>} under $proj." >&2
  echo "If work happened, the numbers are lost; write \`not captured\` in the table" >&2
  echo "rather than an estimate — an invented number cannot be told from a real" >&2
  echo "one later, which is the whole reason the format exists." >&2
  exit 2
fi

# One transcript in, one tab-separated record out: output, input, cache, tool
# calls, duration in whole seconds, and the number of events that were counted.
# The event count is what lets the caller drop a row that --since emptied.
sum_transcript() {
  jq -sr --arg since "$since" '
    # Timestamps carry milliseconds, which fromdateiso8601 will not parse.
    def secs: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
    [ .[] | select($since == "" or ((.timestamp // "") >= $since)) ] as $ev
    | ([$ev[].timestamp] | map(select(. != null))) as $ts
    | [
        ([$ev[].message.usage.output_tokens // 0] | add // 0),
        ([$ev[].message.usage.input_tokens // 0] | add // 0),
        ([$ev[].message.usage.cache_read_input_tokens // 0] | add // 0),
        ([$ev[].message.content[]? | select(.type == "tool_use")] | length),
        (if ($ts | length) > 1 then (($ts | max | secs) - ($ts | min | secs) | floor) else 0 end),
        ($ev | length)
      ] | @tsv
  ' "$1"
}

# A markdown cell whose content may contain the field separator is a cell, not a
# record. This used to render the table first and then recover its totals with
# `awk -F'|'`, so one pipe in an agent's description shifted every column: 140
# output tokens reported as 0, 210 input as 140, and the `<!-- retrospective -->`
# block — the half meant for a machine — carried the shifted numbers too. An
# agent description is free text a model writes at spawn time.
#
# So the totals come from the data and the rendering is a separate step. The
# cell is escaped as well: without that the arithmetic is right and the table
# still renders with an extra column.
rows=""
n_out=0 t_out=0 t_inp=0 t_cache=0 t_tools=0
for f in "${files[@]}"; do
  meta="${f%.jsonl}.meta.json"
  type="$(jq -r '.agentType // "unknown"' "$meta" 2>/dev/null || echo unknown)"
  desc="$(jq -r '.description // "—"' "$meta" 2>/dev/null || echo "—")"

  # Tab-separated numbers, never a rendered row. `dur` is floored in jq rather
  # than in the shell: jq yields a float and bash arithmetic cannot read one.
  IFS=$'\t' read -r out inp cache tools dur events < <(sum_transcript "$f")

  # --since can empty an agent entirely. A zero row would read as an agent that
  # ran and did nothing, which is a different fact.
  [ "$events" -eq 0 ] && continue

  rows="$rows$(printf '| %s | %s | %s | %s | %s | %s | %dm%ds |' \
    "${type//|/\\|}" "${desc//|/\\|}" "$out" "$inp" "$cache" "$tools" \
    "$((dur / 60))" "$((dur % 60))")"$'\n'

  n_out=$((n_out + 1))
  t_out=$((t_out + out))
  t_inp=$((t_inp + inp))
  t_cache=$((t_cache + cache))
  t_tools=$((t_tools + tools))
done

# The main session, last in the table and first in the spend. It is not an
# agent, so it is counted apart and labelled apart; the total below is the two.
m_out=0 m_inp=0 m_cache=0 m_tools=0 m_events=0 m_dur=0
if [ -f "$main" ]; then
  IFS=$'\t' read -r m_out m_inp m_cache m_tools m_dur m_events < <(sum_transcript "$main")
  if [ "$m_events" -gt 0 ]; then
    rows="$rows$(printf '| %s | %s | %s | %s | %s | %s | %dm%ds |' \
      "main session" "this session, not an agent" \
      "$m_out" "$m_inp" "$m_cache" "$m_tools" \
      "$((m_dur / 60))" "$((m_dur % 60))")"$'\n'
  fi
fi

cat <<EOF
<!-- retrospective
session: $session
since: ${since:-<whole session>}
agents: $n_out
agent_output_tokens: $t_out
agent_input_tokens: $t_inp
agent_cache_read_tokens: $t_cache
agent_tool_calls: $t_tools
main_output_tokens: $m_out
main_input_tokens: $m_inp
main_cache_read_tokens: $m_cache
main_tool_calls: $m_tools
output_tokens: $((t_out + m_out))
input_tokens: $((t_inp + m_inp))
cache_read_tokens: $((t_cache + m_cache))
tool_calls: $((t_tools + m_tools))
source: summed from session transcripts — the main session and $n_out agents together
-->

| Stage | What it did | Output tok | Input tok | Cache read | Tool calls | Duration |
|---|---|---:|---:|---:|---:|---:|
${rows}| **Total** | $n_out agents + main | **$((t_out + m_out))** | **$((t_inp + m_inp))** | **$((t_cache + m_cache))** | **$((t_tools + m_tools))** | — |

These are **cumulative compute**, summed from the session transcripts — the main
session and every agent it spawned — and not wall-clock, which includes every
interval nobody was computing. Durations are per-transcript spans and overlap
when agents ran in parallel, so their sum is not elapsed time. Transcript sums
are also a different, smaller metric than a harness-reported usage total; do not
mix the two in one column without saying so.
EOF
