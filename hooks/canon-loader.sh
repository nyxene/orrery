#!/usr/bin/env bash
# SessionStart and SubagentStart hook. Puts CANON.md, and the settings the
# project declared in `.orrery/config.json`, into every session's context and
# every subagent's.
#
# SubagentStart because SessionStart context does not reach a subagent: probed,
# a spawned agent saw `.claude/CLAUDE.md` and another plugin's SubagentStart
# text, and not this canon — so before this, no auditor, critic or architect
# worked under it. The event name is echoed from the payload, never
# hardcoded — an output labelled with the wrong event is the silent drop this
# file exists to prevent.
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

root="${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}"
canon="$root/CANON.md"
input=""; [ -t 0 ] || input="$(cat)"
# Without jq the payload cannot be parsed, so the event is read by its name in
# the raw text — the one field this branch needs.
case "$input" in *'"SubagentStart"'*) event=SubagentStart ;; *) event=SessionStart ;; esac

# One canon, and only this plugin's. The written method is text for people to
# read, not something loaded into a session: what an agent must do in it is
# carried by the skills and enforced by the guards. A second canon here would
# be a copy of that text, which is the drift SHIPLIST exists to make impossible.

# A loader cannot deny, so it says so instead. Without jq this used to exit 127
# and the session simply started without the file that claims to bind every
# session — silently, which is the worst of the three outcomes. The message is a
# fixed string, so it needs no escaping and no jq to emit.
if ! command -v jq >/dev/null 2>&1; then
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"WARNING: the canon could not be loaded — this project ships CANON.md as the non-negotiable core of how work is done, and the loader needs jq to inject it. Install jq, then restart the session. Until then you are working without it, and should say so rather than guess at its contents."}}\n' "$event"
  exit 0
fi

# A missing file is the same silent start by another cause, and it was let through
# here before. CANON.md ships with the plugin, so its absence is a broken
# install or a wrong root — named with the path, which jq quotes.
if [ ! -f "$canon" ]; then
  jq -n --arg e "$event" --arg p "$canon" '{hookSpecificOutput: {hookEventName: $e,
    additionalContext: ("WARNING: the canon could not be loaded — this project ships CANON.md as the non-negotiable core of how work is done, and the loader found no file at " + $p + ". The install is broken or its root is wrong; reinstall, then restart the session. Until then you are working without it, and should say so rather than guess at its contents.")}}'
  exit 0
fi

# The project's declarations follow the canon. Read from the tree the session
# stands in (the payload's cwd), so a worktree reads its own branch's config.
# shellcheck source=hooks/orrery-config.sh
. "$(dirname "$0")/orrery-config.sh"
cwd="$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null || true)"
[ -n "$cwd" ] || cwd="${CLAUDE_PROJECT_DIR:-.}"
decl=""
cfg="$(orrery_config_file "$cwd")"
if [ -n "$cfg" ] && [ -r "$cfg" ]; then
  decl="$(jq -r 'if type == "object" then to_entries[] | "- \(.key): \(if (.value | type) == "string" then .value else (.value | tojson) end)" else empty end' "$cfg" 2>/dev/null || true)"
fi
[ -z "$decl" ] || decl="

Settings this project declared for Orrery, from .orrery/config.json:
$decl"
# Said once per session, not once per spawn: a pool spawns dozens of agents.
problem=""
[ "$event" = SessionStart ] && problem="$(orrery_config_problem "$cwd")"
case "$problem" in
  missing)   decl="$decl

WARNING: this project is on GitHub and has no .orrery/config.json, so Orrery runs as if no tracker were configured. Tell the owner; only they write that file." ;;
  malformed) decl="$decl

WARNING: .orrery/config.json is not a valid JSON object, so every setting falls back to its default. Tell the owner; only they write that file." ;;
esac

jq -n --arg e "$event" --arg c "$(cat "$canon")" --arg d "$decl" '{
  hookSpecificOutput: {
    hookEventName: $e,
    additionalContext: ("The following is the non-negotiable core of how work is done in this project. It binds in every session and overrides convenience.\n\n" + $c + $d)
  }
}'
