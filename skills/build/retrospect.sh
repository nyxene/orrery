#!/usr/bin/env bash
# Builds the resource half of a retrospective from the session's own transcripts.
#
#   skills/build/retrospect.sh [session-id]
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
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "retrospect.sh needs jq" >&2; exit 1; }

session="${1:-${CLAUDE_CODE_SESSION_ID:-}}"
proj="$HOME/.claude/projects/$(pwd -P | sed 's|/|-|g')"

if [ -z "$session" ]; then
  # No id given and none in the environment: take the most recently written one.
  session="$(ls -t "$proj" 2>/dev/null | grep -vE '^memory$|\.jsonl$' | head -1)" || true
fi

dir="$proj/$session/subagents"
if [ ! -d "$dir" ]; then
  echo "No subagent transcripts for session ${session:-<none>} under $proj." >&2
  echo "If agents ran, the numbers are lost; write \`not captured\` in the table" >&2
  echo "rather than an estimate — an invented number cannot be told from a real" >&2
  echo "one later, which is the whole reason the format exists." >&2
  exit 2
fi

shopt -s nullglob
files=("$dir"/agent-*.jsonl)
[ ${#files[@]} -eq 0 ] && { echo "No agents ran in session $session." >&2; exit 2; }

rows=""
for f in "${files[@]}"; do
  meta="${f%.jsonl}.meta.json"
  type="$(jq -r '.agentType // "unknown"' "$meta" 2>/dev/null || echo unknown)"
  desc="$(jq -r '.description // "—"' "$meta" 2>/dev/null || echo "—")"
  rows="$rows$(jq -sr --arg t "$type" --arg d "$desc" '
    # Timestamps carry milliseconds, which fromdateiso8601 will not parse.
    def secs: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
    ([.[].timestamp] | map(select(. != null))) as $ts
    | {
        out:   ([.[].message.usage.output_tokens // 0] | add),
        inp:   ([.[].message.usage.input_tokens // 0] | add),
        cache: ([.[].message.usage.cache_read_input_tokens // 0] | add),
        tools: ([.[].message.content[]? | select(.type == "tool_use")] | length),
        dur:   (if ($ts | length) > 1 then (($ts | max | secs) - ($ts | min | secs)) else 0 end)
      }
    | "| \($t) | \($d) | \(.out) | \(.inp) | \(.cache) | \(.tools) | \(.dur / 60 | floor)m\(.dur % 60)s |"
  ' "$f")"$'\n'
done

totals="$(printf '%s' "$rows" | awk -F'|' '
  NF > 1 { out += $4; inp += $5; cache += $6; tools += $7; n++ }
  END { printf "%d %d %d %d %d", n, out, inp, cache, tools }')"
read -r n_out t_out t_inp t_cache t_tools <<<"$totals"

cat <<EOF
<!-- retrospective
session: $session
agents: $n_out
output_tokens: $t_out
input_tokens: $t_inp
cache_read_tokens: $t_cache
tool_calls: $t_tools
source: summed from session transcripts
-->

| Stage | What it did | Output tok | Input tok | Cache read | Tool calls | Duration |
|---|---|---:|---:|---:|---:|---:|
${rows}| **Total** | $n_out agents | **$t_out** | **$t_inp** | **$t_cache** | **$t_tools** | — |

These are **cumulative agent compute**, summed from the session transcripts —
not wall-clock, which includes every interval nobody was computing. Durations are
per-agent spans and overlap when agents ran in parallel, so their sum is not
elapsed time. Transcript sums are also a different, smaller metric than a
harness-reported usage total; do not mix the two in one column without saying so.
EOF
