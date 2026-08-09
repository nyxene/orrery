#!/usr/bin/env bash
# PreToolUse hook. Puts the rules of a scope into context the first time a
# session touches that scope.
#
# Twenty-four of thirty rules had no reader at the moment they applied. `rules/`
# never self-loaded; only `learn` and `sharpen` opened the directory, and both do
# so to *write*. Five more were cited by path from a skill. So a rule filed after
# a real incident sat in a directory nobody read while the incident repeated —
# which is what happened with the rule about named agents losing their reports:
# cited by four skills, and still broken twice by an author who had it open. That
# rule no longer exists — a guard enforces it now, which is the better ending.
#
# What loads is the rule sentence and what it cost, not the file. A whole scope
# is 2-4x the size of CANON.md and would be paid on every session that edits a
# file; the frontmatter is a few hundred words and carries the part that makes a
# rule evidence rather than preference. The full text is one Read away, and the
# path is given so that Read is obvious.
#
# Once per scope per session. This fires before every tool call, so re-emitting
# would bury the session in its own rules within a dozen calls.
#
# There is deliberately no `domain` scope. A rule about a host project's subject
# matter is that project's, not this library's — `rules/` holds only what is true
# of any project it installs into.
set -euo pipefail

input="$(cat)"

root="${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}"
state="${TMPDIR:-/tmp}/orrery-rules"

# A loader cannot deny. Without jq it says so once, then stays quiet rather than
# repeating itself before every tool call for the rest of the session.
if ! command -v jq >/dev/null 2>&1; then
  marker="$state-nojq"
  [ -e "$marker" ] && exit 0
  mkdir -p "$(dirname "$marker")" && : > "$marker"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"WARNING: the rules loader needs jq and cannot find it, so the rules earned in this project will not reach you as you work. Read rules/ directly before relying on convention, and install jq."}}\n'
  exit 0
fi

tool="$(jq -r '.tool_name // empty' <<<"$input")"
session="$(jq -r '.session_id // "nosession"' <<<"$input")"

# Which scope this tool call is about to enter. A tool with no scope is most
# tool calls, and they cost nothing here.
case "$tool" in
  Agent|Task) scope=agents ;;
  Edit|Write|NotebookEdit) scope=craft ;;
  Bash)
    cmd="$(jq -r '.tool_input.command // empty' <<<"$input")"
    case " $cmd " in
      *" git "*|" git "*|"git "*) scope=git ;;
      *" gh "*|"gh "*) scope=process ;;
      *) exit 0 ;;
    esac
    ;;
  *) exit 0 ;;
esac

# Two layers, same weight: the rules the plugin ships, then the host project's
# own local rules — the lessons `learn` filed in this repository. A shipped law
# and a local one differ only in where they were earned.
plugin_dir="$root/rules/$scope"
local_dir="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/rules/$scope"
[ -d "$plugin_dir" ] || [ -d "$local_dir" ] || exit 0

marker="$state-$session-$scope"
[ -e "$marker" ] && exit 0
mkdir -p "$(dirname "$marker")" && : > "$marker"

# `rule:` is the one-sentence form of the rule; `evidence:` (or a local rule's
# `cost:`) is what filing it was paid for. Single-line frontmatter values;
# anything else in the file is left where it is.
body="$(
  for dir in "$plugin_dir" "$local_dir"; do
    [ -d "$dir" ] || continue
    if [ "$dir" = "$plugin_dir" ]; then label="rules/$scope"; else label=".claude/rules/$scope (this project)"; fi
    for f in "$dir"/*.md; do
      [ -e "$f" ] || continue
      awk -v path="$label/$(basename "$f")" '
        /^---$/ { fm++; if (fm == 2) exit; next }
        fm == 1 && /^rule:/     { sub(/^rule:[[:space:]]*/, ""); gsub(/^"|"$/, ""); r = $0 }
        fm == 1 && /^evidence:/ { sub(/^evidence:[[:space:]]*/, ""); gsub(/^"|"$/, ""); e = $0 }
        fm == 1 && /^cost:/     { sub(/^cost:[[:space:]]*/, ""); gsub(/^"|"$/, ""); c = $0 }
        END {
          if (r == "") next
          ev = (e != "" ? e : (c != "" ? c : "not recorded"))
          printf "- %s\n  evidence: %s · %s\n", r, ev, path
        }
      ' "$f"
    done
  done
)"

[ -z "$body" ] && exit 0

# A rule layer only ever grows: every incident files one and nothing retires
# one. Past a certain size the layer stops being read, which costs more than any
# single rule in it was worth — and nobody notices, because the failure is that
# a wall of text gets skimmed rather than that anything errors.
#
# The count is the trigger because a calendar is not one: "run a prune pass
# quarterly" is a reminder somebody has to hold, and this is the same failure
# the gates in this library exist to end. Ten is a threshold rather than a
# measurement; move it when a pass says the layer was fine at eleven.
#
# It warns and never blocks. A crowded scope is a maintenance signal, not a
# reason to refuse the call somebody is making right now.
crowded=""
n=$(printf '%s\n' "$body" | grep -c '^- ')
[ "$n" -le 10 ] || crowded="

**This scope is crowded — $n rules, and a layer nobody finishes reading is worse than no layer.** Run \`sharpen\`'s prune pass on \`rules/$scope/\`: each rule is kept, merged into a neighbour, absorbed into a gate that can enforce it, or retired because its incident cannot recur. Retirement is deletion, not an archive."

jq -n --arg s "$scope" --arg b "$body" --arg c "$crowded" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: (
      "Rules earned in this project for `" + $s + "`, loaded because this call enters that scope.\n\n"
      + "Each was filed after it cost something real, and the cost is what makes it evidence rather than preference — a rule you disagree with is a rule whose incident you have not read. The full text of any of them, including what happened and how to apply it, is in the file named.\n\n"
      + $b + $c
    )
  }
}'
