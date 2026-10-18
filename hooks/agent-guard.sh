#!/usr/bin/env bash
# PreToolUse guard for the Agent tool. Denies a named spawn whose brief does not
# tell the agent to send its deliverable back.
#
# A named agent is created as an in-process teammate: it communicates only via
# SendMessage, and its final text is NOT returned as the tool result. The report
# is written, sent, and never arrives — indistinguishable from a hang. This cost
# four consecutive lost audit reports in one session, and four more in the
# session that added this guard, to an author who had the rule open.
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

# An error anywhere below must refuse, not let the spawn through. The harness
# reads a non-zero hook exit as a non-blocking error and proceeds, so any
# failure this script did not anticipate was an open door. EXIT rather than ERR,
# because ERR does not fire on a `set -u` violation; `printf` rather than `jq`,
# because jq may be what is broken.
on_exit() {
  local rc=$?
  # An explicit `if`, not `[ ... ] && exit 0`: that form returns non-zero on a
  # non-zero rc, and `set -e` then kills the trap before it can refuse — which
  # is how the first version of this trap silently did nothing at all.
  if [ "$rc" -eq 0 ]; then exit 0; fi
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"The Agent guard failed while checking this spawn (exit %s), so it cannot say the spawn is safe. Refusing rather than passing it through. This is a defect in the guard — report it."}}\n' "$rc"
  exit 0
}
trap on_exit EXIT

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

# The rule that governs every refusal, carried in it; see `bash-guard.sh`.
note="A refusal is the person's to rule on, not yours. If you think this one is wrong, stop, quote it to them and say why. Do not reach the same outcome another way — another tool, a script file, a respelling, a split command — unless this message names that way."

jq -n --arg r "$reason" --arg note "$note" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ($r + "\n\n" + $note)
  }
}'
