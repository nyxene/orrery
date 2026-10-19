#!/usr/bin/env bash
# SessionStart hook. Puts CANON.md into every session's context.
#
# CANON.md opens with "Loaded every session, in every project." Nothing loaded
# it: the plugin manifest declares skills and hooks, and a markdown file at the
# repository root is neither. Skills load on invocation and rules surface when
# something reads them, so the one file claiming to be unconditional was the one
# file with no path into a session at all.
#
# This is why the file has to stay short. Every line here is paid in every
# session of every project — which is the tax `sharpen` weighs before allowing
# anything to be added to it.
set -euo pipefail

canon="${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/CANON.md"

# One canon, and only this plugin's. The written method is text for people to
# read, not something loaded into a session: what an agent must do in it is
# carried by the skills and enforced by the guards. A second canon here would
# be a copy of that text, which is the drift SHIPLIST exists to make impossible.

# A loader cannot deny, so it says so instead. Without jq this used to exit 127
# and the session simply started without the file that claims to bind every
# session — silently, which is the worst of the three outcomes. The message is a
# fixed string, so it needs no escaping and no jq to emit.
if ! command -v jq >/dev/null 2>&1; then
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"WARNING: the canon could not be loaded — this project ships CANON.md as the non-negotiable core of how work is done, and the loader needs jq to inject it. Install jq, then restart the session. Until then you are working without it, and should say so rather than guess at its contents."}}\n'
  exit 0
fi

# A missing file is the same silent start by another cause, and it was let through
# here before. CANON.md ships with the plugin, so its absence is a broken
# install or a wrong root — named with the path, which jq quotes.
if [ ! -f "$canon" ]; then
  jq -n --arg p "$canon" '{hookSpecificOutput: {hookEventName: "SessionStart",
    additionalContext: ("WARNING: the canon could not be loaded — this project ships CANON.md as the non-negotiable core of how work is done, and the loader found no file at " + $p + ". The install is broken or its root is wrong; reinstall, then restart the session. Until then you are working without it, and should say so rather than guess at its contents.")}}'
  exit 0
fi

jq -n --arg c "$(cat "$canon")" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: ("The following is the non-negotiable core of how work is done in this project. It binds in every session and overrides convenience.\n\n" + $c)
  }
}'
