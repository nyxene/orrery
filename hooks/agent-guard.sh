#!/usr/bin/env bash
# PreToolUse guard for the Agent tool. Denies a named spawn whose brief does not
# tell the agent to send its deliverable back.
#
# A named agent is created as an in-process teammate: it communicates only via
# SendMessage, and its final text is NOT returned as the tool result. The report
# is written, sent, and never arrives — indistinguishable from a hang. This cost
# four consecutive lost audit reports on 2026-07-29, and four more
# in the session that added this guard, to an author who had the rule open.
#
# That is the argument for a guard over a sixth copy of the rule: the instruction
# was present, correct and prominent, and was still not applied.
#
# A named teammate is legitimate when you want one. What is never legitimate is a
# named teammate with no instruction to send — so the guard tests for the send,
# not for the name.
#
# Exit contract: prints a permissionDecision JSON and exits 0 to deny;
# prints nothing and exits 0 to pass through.
set -euo pipefail

input="$(cat)"

# The same fail-open the Bash guard had: without jq this exits 127, the harness
# reads that as a non-blocking error, and the spawn it could not read proceeds.
# A guard that cannot check must not let through.
if ! command -v jq >/dev/null 2>&1; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"The Agent guard requires jq and cannot find it, so no spawn can be checked. Install jq before spawning agents."}}\n'
  exit 0
fi

name="$(jq -r '.tool_input.name // empty' <<<"$input")"
[ -z "$name" ] && exit 0

prompt="$(jq -r '.tool_input.prompt // empty' <<<"$input")"
# The brief must name both the tool and the one recipient that does not
# dead-letter. "team-lead" and any other name are silently dropped.
if grep -qi 'sendmessage' <<<"$prompt" \
  && grep -qiE '(to:?[[:space:]]*["'"'"']?main["'"'"']?)|(back to main)|(returns? .*to main)' <<<"$prompt"; then
  exit 0
fi

# The threat here is forgetting, not sabotage. A brief that mentions the call
# without meaning it slips through, and that is the accepted limit of a grep.

reason='Agent spawned with name="'"$name"'" and a brief that never tells it to send its deliverable back. A named agent is an in-process teammate: its final text is NOT returned as the tool result, so the report gets written, sent, and lost — which looks exactly like a hang. Either drop `name`, and the final text becomes the return value; or keep it and add to the brief: finish by calling SendMessage({to: "main", ...}) with the FULL deliverable as the body. Address "main" — "team-lead" and every other name dead-letter silently.'

jq -n --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'
