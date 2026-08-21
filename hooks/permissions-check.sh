#!/usr/bin/env bash
# SessionStart hook (matcher: "startup") and hand-run reporter: says when a host
# project's copy of this plugin's deny-list has fallen behind the list the
# plugin ships.
#
#   permissions-check.sh <project>              hook mode: emit JSON or nothing
#   permissions-check.sh --report    <project>  0 clean · 1 behind · 2 could not compare
#   permissions-check.sh --reconcile <project>  record the declined set, in the project
#
# `hooks/permissions.json` is merged into a host project's own
# `.claude/settings.json` **by hand**. The plugin updates itself; that copy does
# not; and nothing noticed — one install was short by 28 of them for a month,
# with a green doctor. This is the thing that notices.
#
# Three properties are load-bearing, and each is here because its absence was a
# defect in a draft of the plan:
#
# 1. **`systemMessage` only** — never `additionalContext`, never
#    `hookSpecificOutput`. A `systemMessage` reaches the user and not the model
#    (`hook_system_message:()=>[]` in the harness's attachment table), and a
#    model that cannot see this finding cannot "fix" it by editing the user's
#    settings. This is a reporter; it never becomes an actor, and it never
#    writes any `settings.json` at any scope.
# 2. **Every jq read is `(… // [])` *and* has its exit status checked.** The
#    operator rescues a missing key in a document that parsed, and nothing else:
#    a trailing comma is jq exit 5, an unreadable file is exit 2. Under
#    `set -euo pipefail` an unchecked non-zero jq kills this script — printing
#    nothing, which is byte-identical to what a fully merged project prints.
# 3. **A comparison that could not be made is said out loud**, never rendered as
#    silence, because silence here reads as all-clear.
#
# The comparison is a SUBSET check on exact rule text. Rules a project holds
# that this plugin does not ship are never mentioned and never counted, and the
# `allow` block is never compared — those rules name our own gate scripts by
# path and are not the consumer's. Exact text means a consumer who narrowed
# `Read(**/*.key)` to `Read(/Users/someone/**/*.key)` is told the shipped rule
# is not present: true as written, and nothing short of re-implementing the
# platform's own matcher could say otherwise.
#
# Run from a checkout against some other project, this compares the *running
# copy's* rules — not the rules of whatever version that project has cached.
# Installed as the plugin, which is the normal case, the two are the same thing.
set -euo pipefail

mode=hook
case "${1:-}" in
  --report)    mode=report;    shift ;;
  --reconcile) mode=reconcile; shift ;;
  --*) printf 'usage: permissions-check.sh [--report|--reconcile] [project-dir]\n' >&2; exit 2 ;;
esac

# Defaulted rather than required, so the path printed in the message below is
# pasteable from inside the project. The hook always passes it explicitly.
PROJECT="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"
PROJECT="$(cd "$PROJECT" 2>/dev/null && pwd -P || echo "$PROJECT")"
root="${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}"
self="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P || dirname "$0")/$(basename "$0")"
record="$PROJECT/.claude/orrery-deny.json"

# A loader cannot deny, so it says so instead — the shape `canon-loader.sh:17-24`
# and `rules-loader.sh:32-40` already use. Fixed strings: without jq there is
# nothing to escape JSON with.
if ! command -v jq >/dev/null 2>&1; then
  if [ "$mode" = hook ]; then
    printf '%s\n' '{"systemMessage":"orrery: the deny-list check needs jq and could not run. Nothing was compared, and nothing is claimed either way. Install jq to get this check back."}'
    exit 0
  fi
  printf '%s\n' "orrery: the deny-list check needs jq and could not run. Nothing was compared, and nothing is claimed either way."
  exit 2
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/orrery-permcheck.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

emit() { # $1 = message. Hook mode speaks JSON; the other two speak plainly.
  local out
  if [ "$mode" = hook ]; then out="$(jq -n --arg m "$1" '{systemMessage:$m}')"
  else out="$1"; fi
  printf '%s\n' "$out"
}

# Never carries the word "missing": this is the third exit code, and rendering
# it as the second is the lesson `wire-settings.sh:60-71` carries in code.
refuse() { # $1 = why
  emit "orrery: $1 Nothing was compared, and nothing is claimed about this project's deny rules."
  if [ "$mode" = hook ]; then exit 0; fi
  exit 2
}

# --- what we ship -----------------------------------------------------------
# Refusing on an empty array matters as much as refusing on a parse error: an
# empty `ours` makes every project clean, and silence would read as all-clear.
shipped="$root/hooks/permissions.json"
manifest="$root/.claude-plugin/plugin.json"
jq -c '(.permissions.deny // [])' "$shipped" > "$tmp/ours.json" 2>/dev/null \
  || refuse "this plugin's own deny-list at $shipped could not be read as JSON."
ours_n="$(jq -r 'length' "$tmp/ours.json" 2>/dev/null)" \
  || refuse "this plugin's own deny-list at $shipped could not be counted."
[ "$ours_n" -gt 0 ] \
  || refuse "this plugin's own deny-list at $shipped is empty, so this install looks wrong."
version="$(jq -r '.version // ""' "$manifest" 2>/dev/null)" \
  || refuse "this plugin's version could not be read from $manifest."
[ -n "$version" ] \
  || refuse "this plugin's version is empty in $manifest, so this install looks wrong."

# --- what they have, across every scope the platform merges -----------------
# A checker that reports a rule present at another scope as absent is a checker
# people learn to ignore. Unmatched globs stay literal and fail `-f`; a path we
# cannot reach contributes nothing, so the error direction is a false "not
# present", never a false "clean".
: > "$tmp/theirs.json"
for f in \
  "$PROJECT/.claude/settings.json" \
  "$PROJECT/.claude/settings.local.json" \
  "${HOME:-}/.claude/settings.json" \
  "/Library/Application Support/ClaudeCode/managed-settings.json" \
  "/Library/Application Support/ClaudeCode/managed-settings.d"/*.json \
  "/etc/claude-code/managed-settings.json" \
  "/etc/claude-code/managed-settings.d"/*.json
do
  [ -f "$f" ] || continue
  jq -c '(.permissions.deny // [])' "$f" >> "$tmp/theirs.json" 2>/dev/null \
    || refuse "$f exists but could not be read as JSON."
done

# --- what they have declined ------------------------------------------------
# An unreadable decline record fails toward reporting everything. The opposite
# reading is reachable through this tool's own undo procedure — edit the file,
# leave a trailing comma, commit — and it would silence the project in a way
# indistinguishable from all-clear. Noise costs one command; silence cost a month.
record_state=absent
declined_version=""
printf '[]\n' > "$tmp/declined.json"
if [ -e "$record" ]; then
  if jq -c '(.reconciled_deny // [])' "$record" > "$tmp/declined.json" 2>/dev/null; then
    record_state=read
    declined_version="$(jq -r '.reconciled_version // ""' "$record" 2>/dev/null || echo "")"
  else
    printf '[]\n' > "$tmp/declined.json"
    record_state=broken
  fi
fi

# --- the subtraction --------------------------------------------------------
# `absent` is what this project does not have; `reported` is that minus what it
# has declined. `--reconcile` records `absent`, so re-declining an already
# declined rule keeps it declined; the hook and `--report` speak about `reported`.
jq -c --slurpfile t "$tmp/theirs.json" '. - ($t | add // []) | unique' "$tmp/ours.json" \
  > "$tmp/absent.json" 2>/dev/null \
  || refuse "the shipped deny-list and this project's settings could not be compared."
jq -c --slurpfile d "$tmp/declined.json" '. - ($d[0] // []) | unique' "$tmp/absent.json" \
  > "$tmp/reported.json" 2>/dev/null \
  || refuse "the decline record could not be subtracted from the comparison."
absent_n="$(jq -r 'length' "$tmp/absent.json")"
reported_n="$(jq -r 'length' "$tmp/reported.json")"
declined_n="$(jq -r 'length' "$tmp/declined.json")"

case "$mode" in
report)
  if [ "$reported_n" -eq 0 ] && [ "$absent_n" -eq 0 ]; then
    emit "all $ours_n deny rules this plugin ships ($version) are present in this project's settings."
  elif [ "$reported_n" -eq 0 ]; then
    # Clean because they were declined, not because they were merged. Saying
    # "all present" here would be a false statement in the one place built to
    # stop false statements.
    emit "every one of the $ours_n deny rules this plugin ships ($version) is either present in this project's settings or recorded below as declined."
  else
    emit "$reported_n of the $ours_n deny rules this plugin ships ($version) are not present, by exact text, in this project's settings:"
    jq -r '.[]' "$tmp/reported.json" | sed 's/^/  /'
  fi
  # Printed on a clean run too. A wrong `--reconcile` records the whole absent
  # set as deliberate and the hook then goes quiet — this number and this path
  # are what stop that from being invisible.
  printf '\n'
  case "$record_state" in
    read)   emit "$declined_n rules recorded as declined, against ${declined_version:-an unrecorded version}"
            emit "recorded in: $record" ;;
    absent) emit "nothing recorded as declined — no record at: $record" ;;
    broken) emit "the decline record could not be read, so this project is treated as having declined nothing: $record" ;;
  esac
  if [ "$reported_n" -eq 0 ]; then exit 0; fi
  exit 1
  ;;
reconcile)
  # The refusals above already left with exit 2. This one is deliberate rather
  # than an accident of the empty-set rule catching a failed comparison.
  if [ "$absent_n" -eq 0 ]; then
    emit "orrery: nothing to decline — every deny rule this plugin ships is already present in this project. Nothing was written."
    exit 3
  fi
  dir="$PROJECT/.claude"
  if ! mkdir -p "$dir" 2>/dev/null || [ ! -w "$dir" ]; then
    emit "orrery: $dir is not writable, so no decline record was written."
    exit 2
  fi
  # Replaces rather than merges: a union could only ever grow, and un-declining
  # would then be impossible except by editing the file — which is the operation
  # this record being committed text exists to make possible.
  if ! jq -n --slurpfile a "$tmp/absent.json" --arg v "$version" \
       '{reconciled_deny: $a[0], reconciled_version: $v}' > "$record" 2>/dev/null; then
    emit "orrery: $record could not be written, so nothing was recorded."
    exit 2
  fi
  emit "orrery: recorded $absent_n deny rules as declined by this project, against $version."
  emit "written to: $record — commit it. The decision belongs to the project, not to this machine."
  exit 0
  ;;
esac

# --- hook mode --------------------------------------------------------------
# The rate limiter keys on the finding, not on the plugin version: a branch
# switch, a bad merge or a hand-deleted block changes what is true without
# changing the version. It does not travel between machines, and that is
# correct — a machine that has never spoken has not repeated anything.
slug=$(echo "$PROJECT" | sed 's#^/##; s#[/ ]#-#g')
state_dir="${HOME:-$tmp}/.claude/orrery/permissions"
state="$state_dir/$slug.json"

if [ "$reported_n" -eq 0 ]; then
  # A project that has caught up starts over. Without this, the same set going
  # absent again — a bad merge, a branch switch to a pre-merge settings file —
  # matches the digest of what we said last time and stays silent, which is the
  # incident this whole check exists to end. Nothing is written when the file
  # was never there, so the common case still costs no write at all.
  if [ -f "$state" ]; then rm -f "$state" 2>/dev/null || true; fi
  exit 0
fi

sha=""
if command -v shasum >/dev/null 2>&1; then
  sha="$(shasum -a 256 < "$tmp/reported.json" | cut -d' ' -f1)"
elif command -v sha256sum >/dev/null 2>&1; then
  sha="$(sha256sum < "$tmp/reported.json" | cut -d' ' -f1)"
fi
was=""
if [ -f "$state" ]; then
  # Unreadable is treated as never-reported: a rate limiter nobody can read must
  # not be able to suppress a message. The write below then repairs the file.
  was="$(jq -r '.reported_missing_sha // ""' "$state" 2>/dev/null || echo "")"
fi
if [ -n "$sha" ] && [ "$sha" = "$was" ]; then exit 0; fi

can_record=1
if [ -z "$sha" ] || ! mkdir -p "$state_dir" 2>/dev/null || [ ! -w "$state_dir" ]; then
  can_record=0
fi

if [ "$reported_n" -eq 1 ]; then noun="deny rule"; verb="is"; else noun="deny rules"; verb="are"; fi
msg="orrery $version: $reported_n $noun this plugin ships $verb not present, by exact text, in this project's settings. \`orrery:doctor\` lists them. If you declined them on purpose, record that once — it commits to the project and we stop asking: $self --reconcile"
if [ "$record_state" = broken ]; then
  msg="$msg
The decline record could not be read, so this project is treated as having declined nothing: $record"
fi
if [ "$can_record" -eq 0 ]; then
  msg="$msg
(could not record this — you will see it again)"
fi

# Emit first, record second — deliberately the opposite of
# `handoff-prompt.sh:51-52`, where writing the marker first is the safety
# property because that hook can block a compaction. Nothing here blocks, and
# the only hazard runs the other way: if the emit is dropped, a state written
# first says "reported" for a message nobody saw and the digest suppresses it
# forever. Under `set -euo pipefail` a failed emit takes the script with it,
# which is what keeps the ordering true rather than merely written down.
emit "$msg"
if [ "$can_record" -eq 1 ]; then
  jq -n --arg s "$sha" '{reported_missing_sha: $s}' > "$state" 2>/dev/null || true
fi
exit 0
