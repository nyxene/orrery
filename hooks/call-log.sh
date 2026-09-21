#!/usr/bin/env bash
# Tool-call recorder, on PreToolUse and PostToolUse. Appends a line per event to
# a local file so that a change to how the library works can be observed instead
# of assumed.
#
#   ORRERY_CALL_LOG=<path>   enables it. Unset, this exits before doing anything.
#   ORRERY_CALL_LOG_MAX=<n>  bytes to keep, default 262144. Trimmed oldest-first.
#   hooks/call-log.sh --purge   empties the log and says how much it removed.
#
# ## Why a hook rather than a line inside each skill
#
# A skill that logs its own behaviour cannot record the run where it ignored its
# own instructions — the same omission removes the behaviour and the evidence of
# it. The case this exists to catch is exactly that: a plan that spiked and then
# skipped its checkers, which `skills/plan/SKILL.md` argues against and cannot
# enforce. From here it is a session with a planner spawn, some Bash, and no
# critic — visible without the skill cooperating and without reading anything it
# produced.
#
# ## What is recorded, and what is deliberately next to it and not recorded
#
# Seven fields, tab separated: an ISO-8601 UTC timestamp, a session fingerprint,
# the tool name, the kind where the tool has one — a subagent type for `Agent`,
# a skill name for `Skill` — whether the spawn was named, the event — `call` or
# `ran` — and the harness's id for this tool call.
#
# `Skill` was added to the matcher after the fact. Until then no skill invocation
# was recorded anywhere, so which of this library's own skills had ever run was
# unknowable — and the gap was invisible, because the log looked complete. It
# had already produced a false statement in a report.
#
# ## Why two lines, and what the pair means
#
# For months this recorded intent and never outcome. A call refused by either
# guard, by the permission classifier, or by the person at the keyboard was
# written exactly like one that ran. Two adjacent lines in this repository's own
# log said `Agent critic` twice: the first returned "agent type not found", the
# second returned a working agent. Byte-identical record, opposite outcomes.
#
# `PostToolUse` fires only when a tool **succeeds**, and both events carry the
# same `tool_use_id`. That is the whole mechanism: a `call` line with no matching
# `ran` line did not run. It needs no list of the ways a call can be stopped, so
# there is no list to leave something off — guard, classifier, person and
# interrupt are all covered by the same absence.
#
# The two registrations in `hooks/hooks.json` carry the **same matcher**, on
# purpose: a pair can only form if both halves watch the same tools. Narrow the
# `PostToolUse` one — drop `Skill`, say — and every Skill call reads as "did not
# run", which is the false statement paragraph three above was written to end.
# The suite pins the two matchers equal, so that edit goes red instead of
# shipping. This sentence used to live beside the registration itself, as a
# `_comment` key the CLI now rejects at load; it moved here so the file that
# holds every hook carries only the keys the format defines.
#
# `PermissionDenied` exists as an event and is deliberately not used. It reports
# *why* rather than *whether*, and its coverage of the three denial paths is not
# documented — a mechanism whose completeness rests on an undocumented event is
# the same failure this pairing was written to end.
#
# **What the absence does not tell you**: refused, errored and interrupted look
# alike. An unpaired line means "did not complete", never "was refused", and a
# reader who counts them as refusals will overstate. Stated here because that
# reader is the one this field was added for.
#
# Lines written before the event field existed carry five and no event. Read an
# empty sixth field as `call`; every one of them is a call that was never paired.
#
# Two more ways an unpaired line means nothing. Updating leaves a window: the new
# format starts being written as soon as the plugin updates, but the
# `PostToolUse` registration only takes effect in the next session, and the calls
# in between can never pair. And reading a *live* log always finds one extra —
# the call doing the reading, whose `ran` is written after the read. The first
# time this number was read it was 27, and all 27 were these two things. None was
# a refusal.
#
# Not the prompt. Not the command. Not the file path, the branch, the cwd, or
# the name given to a named agent. `agent-guard.sh` reads `.tool_input.prompt`
# two files away, to make a decision and never to keep one — and this paragraph
# exists because the field sits right next to the ones below, so the first person
# who wants it "just for debugging" finds a sentence here instead of a silence.
#
# The session id is hashed rather than stored. It correlates calls within one
# session, which is the whole purpose, and identifies nothing outside the machine
# that wrote it. That matters because these lines are meant to be attachable to a
# feedback report by hand.
#
# ## It fails open, unlike every other hook here
#
# The guards deny when they cannot run, because a guard that cannot check must
# not let a command through. This is not a guard. A recorder that blocks work
# when its disk is full has done more damage than the missing line was worth, so
# every failure path here exits 0 silently.
set -euo pipefail

log="${ORRERY_CALL_LOG:-}"

# ## A relative path is resolved against the project, never against the cwd
#
# This is the fix for the worst defect this file has had. `ORRERY_CALL_LOG` is a
# relative path in every install, because the install guide recommends one — and
# this hook used to `mkdir -p` and append relative to whatever directory the tool
# call happened to be running in. Every `cd` into a subdirectory therefore
# started a **new** log there.
#
# In one host project that produced twenty of them, as deep as
# `packages/orbis/src/features/birthDataForm/components/.claude/`, and the
# project's `.gitignore` line — the one this guide tells people to add — is
# anchored to the repository root, so the strays were not ignored and one of them
# was committed. In this repository it produced seven. Every step of that was
# ours: the recommendation, the resolution, and the ignore rule that covered only
# the path we told them to expect.
#
# **Not written at all rather than written somewhere else.** This hook fails open
# everywhere else, because a recorder that blocks work costs more than the line
# it lost. That reasoning does not reach here: a missing line costs a line, and a
# file created in a stranger's source tree is damage they have to find. So a
# relative path with no project root to resolve against records nothing.
unresolved=""
if [ -n "$log" ]; then
  case "$log" in
    /*) ;;
    *)  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then log="$CLAUDE_PROJECT_DIR/$log"
        else unresolved="$log"; log=""; fi ;;
  esac
fi

if [ "${1:-}" = --purge ]; then
  # `--purge` is typed by a person standing in their project, and a terminal has
  # no CLAUDE_PROJECT_DIR. Falling back to the working directory is safe here in
  # a way it is not above: this prints the path it acted on, so the ambiguity is
  # in front of the person rather than behind them.
  if [ -n "$unresolved" ]; then log="$PWD/$unresolved"; fi
  [ -n "$log" ] || { printf 'ORRERY_CALL_LOG is not set, so there is no log to purge.\n' >&2; exit 1; }
  if [ -f "$log" ]; then
    lines="$(wc -l < "$log" | tr -d ' ')"
    : > "$log"
    printf 'purged %s lines from %s\n' "$lines" "$log"
  else
    printf 'nothing to purge: %s does not exist\n' "$log"
  fi
  exit 0
fi

# Not configured is the normal case for anyone who did not ask for this, and it
# costs one variable test per tool call.
[ -n "$log" ] || exit 0

input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

tool="$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null || true)"
[ -n "$tool" ] || exit 0

# The event decides the marker, read from the harness rather than inferred from
# which fields happen to be present.
#
# Three branches, and the split between the last two is the whole decision. An
# *absent* field records a call: this hook fails open by design, the field is
# newer than the log it writes to, and a recorder that goes silent because one
# key moved is worse than one that mislabels. A field that is *present and
# unrecognised* records nothing: that can only happen if someone registers a
# third event and does not teach this file, and an unlabelled row would then be
# counted as a call by everything that reads the log.
case "$(jq -r '.hook_event_name // empty' <<<"$input" 2>/dev/null || true)" in
  PostToolUse) event=ran ;;
  PreToolUse|"") event=call ;;
  *)           exit 0 ;;
esac
# Harness-supplied, unlike the two fields below it, but cleaned with them all the
# same — the one-line-per-event property is worth more than the assumption.
use_id="$(jq -r '.tool_use_id // "-"' <<<"$input" 2>/dev/null || true)"

session="$(jq -r '.session_id // "nosession"' <<<"$input" 2>/dev/null || true)"
# Whichever of the two is present. Neither is a personal identifier, and both are
# **caller-supplied free text** — `subagent_type` is whatever string the model
# passes on a spawn, not a value from a fixed list. The comment here claimed the
# opposite for as long as it existed, and that claim is why nothing sanitized the
# field; see the `clean` call below.
# `.skill` shares this column with the two agent-type keys because they answer
# the same question — which *kind* of thing this call was, for the tools that
# have a kind. The tool name in field three says which reading applies, so a
# skill named `critic` and an agent typed `critic` are never confused. An eighth
# field instead would have changed the record format for every reader of a log
# already holding thousands of lines, to carry a value that is never present at
# the same time as its neighbour.
agent="$(jq -r '.tool_input.subagent_type // .tool_input.agentType // .tool_input.skill // "-"' <<<"$input" 2>/dev/null || true)"
# Whether a name was given, never the name itself.
named=no
[ -z "$(jq -r '.tool_input.name // empty' <<<"$input" 2>/dev/null || true)" ] || named=yes

# `|| true` on both, because the claim above is that every failure path here
# exits 0 and these were the two that did not: under `set -e` a hashing tool
# that fails takes the hook down with it. Nothing blocks either way — the
# harness treats a non-zero hook as a non-blocking error — but a recorder that
# exits non-zero is a recorder that shows up in logs as broken.
if command -v shasum >/dev/null 2>&1; then
  fp="$(printf '%s' "$session" | shasum -a 256 2>/dev/null | cut -c1-8 || true)"
elif command -v sha256sum >/dev/null 2>&1; then
  fp="$(printf '%s' "$session" | sha256sum 2>/dev/null | cut -c1-8 || true)"
fi
[ -n "${fp:-}" ] || fp=nohash

# One call must be one line, and two of these fields are supplied by the caller
# rather than by the harness. A newline inside `subagent_type` used to end the
# record early and start a second one: a single Agent spawn wrote two lines, the
# second a complete forgery with a chosen timestamp, a chosen fingerprint and a
# chosen tool name. This log exists because a session that ignores its own
# instructions cannot be trusted to report that it did — so a session that can
# also write whatever it likes into the record leaves nothing behind worth
# reading.
#
# Tabs matter for the same reason, one field over instead of one line down, and
# control characters because the text form of `tools/report.sh` prints tool names
# straight to a terminal.
clean() { LC_ALL=C tr -d '\000-\037\177' <<<"$1"; }
tool="$(clean "$tool")"
agent="$(clean "$agent")"
fp="$(clean "$fp")"
use_id="$(clean "$use_id")"

mkdir -p "$(dirname "$log")" 2>/dev/null || exit 0
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$fp" "$tool" "${agent:--}" "$named" \
  "$event" "${use_id:--}" >> "$log" 2>/dev/null || exit 0

# Trimming is checked by size rather than by counting lines: this runs on every
# tool call, and `wc -l` on a file that only grows is the kind of cost that is
# invisible until the file is large. `stat` is one syscall.
max="${ORRERY_CALL_LOG_MAX:-262144}"
size="$(stat -f%z "$log" 2>/dev/null || stat -c%s "$log" 2>/dev/null || echo 0)"
if [ "$size" -gt "$max" ] 2>/dev/null; then
  # By bytes, not by a line count. Keeping "the last N lines" does not shrink a
  # file whose lines are long — the first version kept 2000 of them and left a
  # file of 401 unchanged, which the test caught. Halving is what makes the trim
  # amortised: it happens once every max/2 bytes rather than on every call from
  # the moment the cap is first crossed.
  tmp="$log.trim.$$"
  # `tail -c` can land mid-line, so the first (partial) one is dropped.
  if tail -c "$((max / 2))" "$log" 2>/dev/null | tail -n +2 > "$tmp" 2>/dev/null; then
    mv "$tmp" "$log" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
  else
    rm -f "$tmp" 2>/dev/null || true
  fi
fi

exit 0
