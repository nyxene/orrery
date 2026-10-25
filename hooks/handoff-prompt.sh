#!/usr/bin/env bash
# PreCompact hook. Stops the first compaction of a session to ask whether there
# is residue worth carrying, because compaction *is* the context reset the
# `handoff` skill exists for.
#
# Nothing triggered `handoff`. The skill was well-specified and its trigger lived
# only in its own `description` — read when someone is already looking for it,
# and the session that most needs a handoff is the one with no room left to
# notice it needs one. Adding a step to every skill would not have worked either:
# the skills that would carry the step are not running when the context runs out.
#
# `trigger` distinguishes `manual` from `auto`, and both qualify. Auto is the
# more important of the two — it arrives unannounced, which is exactly how
# residue gets lost.
#
# **Once per session, and the marker is written before the block**, so a
# compaction is delayed at most once no matter what happens next. That ordering
# is the safety property: an auto-compaction fires because the context is nearly
# full, and a hook that could block it repeatedly would strand the session it was
# trying to help.
#
# The cost, read off the hook contract rather than guessed at. A blocked
# compaction is cancelled, never deferred — nothing retries it. Blocking a
# proactive auto-compact skips it and the conversation runs on uncompacted to the
# next threshold; blocking an auto-compact that is already recovering from a
# context-limit error surfaces that error and fails the request, so Claude never
# reads the reason below and no handoff gets written. `trigger` separates only
# `manual` from `auto`, so the hook cannot dodge the second case and keep the
# first.
#
# And there is no quieter way to ask. PreCompact returns the universal fields
# plus top-level `decision`/`reason`; `additionalContext` is not among its
# fields, so the request cannot ride along with a compaction that proceeds.
# Blocking is the only channel this event has, and the marker bounds it to once.
# See https://code.claude.com/docs/en/hooks — "PreCompact", "Decision control".
set -euo pipefail

input="$(cat)"

# This hook blocks. Blocking on input it cannot read is worse than not firing —
# unlike a guard, refusing here protects nothing and can strand a full session.
# So it declines to act, and says so rather than failing silently.
if ! command -v jq >/dev/null 2>&1; then
  printf '{"systemMessage":"orrery: the handoff reminder needs jq and could not run. Compaction proceeded; if work is unfinished, run orrery:handoff by hand."}\n'
  exit 0
fi

session="$(jq -r '.session_id // "nosession"' <<<"$input")"
# shellcheck source=hooks/orrery-config.sh
. "$(dirname "$0")/orrery-config.sh"
cwd="$(jq -r '.cwd // empty' <<<"$input")"
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="${CLAUDE_PROJECT_DIR:-$PWD}"
marker="$(orrery_marker "handoff-$session" "$cwd")"

[ -e "$marker" ] && exit 0
: > "$marker"

reason='The context is about to be compacted, which is the reset `orrery:handoff` exists for — this fires once per session and will not fire again.

Decide, then act:

- **Is there unfinished work in this tree?** Run `orrery:handoff`. The dead ends matter most: what was already tried and does not work is the part a fresh session cannot reconstruct and will otherwise repeat.
- **Cannot name what would finish the work?** Then there was none to hand off. Say so in one line and continue — a session that leaves no residue should leave none, and a tracker that collects diary entries stops being read.

The handoff is `.orrery/work/<work>/handoff.md` in the work'"'"'s own tree, committed with it; closing the work deletes it.

When you are done, say you are ready to compact.'

jq -n --arg r "$reason" '{decision: "block", reason: $r}'
