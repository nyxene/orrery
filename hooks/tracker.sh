#!/usr/bin/env bash
# The one door to the tracker. Every tracker act the core needs — file an item,
# list them, add a note, say what closes one, check and create the labels — goes
# through here, so a skill names one script instead of spelling `gh issue` in
# prose that only works on GitHub, and the guards learn one name.
#
#   hooks/tracker.sh [-C <dir>] <op> [args]
#
#   file    --type T [--area A] [--priority P] [--flag F]… --title S --body-file F
#   list    [--type T] [--area A] [--priority P] [--flag F]… [--search S] [--origin]
#   note    <id> --body-file F
#   closer  <id>
#   labels
#   labels-create
#
# The adapter is whatever `orrery_tracker` resolves for the target tree — the
# working directory's, or `-C <dir>`'s, because `onboard` acts on a draft tree
# whose config is not this session's — and is `hooks/tracker/<adapter>.sh`, one
# function per op. Two exist: `none`, the file register, and `github`.
#
# Output is tab-separated. Exit 0 success; 1 a failure, its cause on stderr —
# never thrown away, because an empty list and a failed one must not read alike;
# 2 a usage error naming the values that are declared; 3 `unsupported: <reason>`
# on stdout, for an op the adapter has no answer to.
#
# The values are the method's classification and are fixed here, not configured:
# six types, three priorities (absence is normal), four flags. Only the areas
# are the project's, from `areas` in its config. While a project still declares
# the retired `debtLabels` and no `areas` it runs in legacy mode: the areas are
# its pool with `area/` stripped, the chore type answers to its old debt label,
# and `--origin` does nothing, since that label already means debt.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=hooks/orrery-config.sh
. "$here/orrery-config.sh"

TYPES="feature task bug chore research docs"
PRIORITIES="critical high low"
FLAGS="security unread-exempt needs-owner triage"
OPS="file list note closer labels labels-create"
LIMIT=200
# A line that is the heading *Where it came from*, whatever markup or case it
# wears: `## Where it came from`, `**Where it came from**:`, `where it came from`.
# Matched per line, by awk in `none` and by jq in `github`.
ORIGIN_RE='^[[:space:]>#*_]*where it came from[[:space:]*_]*(:|$)'

usage() { printf 'tracker.sh: %s\n' "$1" >&2; exit 2; }
fail()  { printf 'tracker.sh: %s\n' "$1" >&2; exit 1; }
unsupported() { printf 'unsupported: %s\n' "$1"; exit 3; }
in_list() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }

TRACKER_DIR=.
if [ "${1:-}" = -C ]; then
  [ -d "${2:-}" ] || usage "-C needs a directory"
  TRACKER_DIR="$2"; shift 2
fi
op="${1:-}"; [ $# -eq 0 ] || shift
in_list "$op" "$OPS" || usage "the op is one of: $OPS"

# The project's areas, and what the chore type is called — one jq over the
# settings in force. A key of the wrong shape reads as absent, as every other
# setting does.
{ read -r TRACKER_MODE; read -r TRACKER_CHORE; TRACKER_AREAS="$(tr '\n' ' ')"; } < <(
  jq -r 'if has("debtLabels") and (has("areas") | not) then
           "legacy", ((.debtLabels.type | strings) // "type/chore"),
           (.debtLabels.pool // [] | arrays | .[] | strings | sub("^area/"; ""))
         else "current", "type/chore", (.areas // [] | arrays | .[] | strings) end' \
    <<<"$(orrery_config_json "$TRACKER_DIR")")
TRACKER_AREAS="${TRACKER_AREAS% }"

T_TYPE="" T_AREA="" T_PRIO="" T_FLAGS="" T_TITLE="" T_BODY="" T_SEARCH="" T_ORIGIN="" T_ID="" given=""
case "$op" in
  note|closer) [ $# -gt 0 ] && [ "${1#-}" = "$1" ] || usage "$op needs an id first"
               T_ID="$1"; shift ;;
esac
while [ $# -gt 0 ]; do
  case "$1" in
    --origin) T_ORIGIN=1; given="$given origin"; shift; continue ;;
    --type|--area|--priority|--flag|--title|--body-file|--search) [ $# -ge 2 ] || usage "$1 needs a value" ;;
    *) usage "unknown argument: $1" ;;
  esac
  given="$given ${1#--}"
  case "$1" in
    --type) in_list "$2" "$TYPES" || usage "--type is one of: $TYPES"; T_TYPE="$2" ;;
    --area) [ -n "$TRACKER_AREAS" ] || usage "--area $2, but the project declares no areas (\"areas\" in .orrery/config.json)"
            in_list "$2" "$TRACKER_AREAS" || usage "--area is one of the declared areas: $TRACKER_AREAS"
            T_AREA="$2" ;;
    --priority) in_list "$2" "$PRIORITIES" || usage "--priority is one of: $PRIORITIES (absent is normal)"; T_PRIO="$2" ;;
    --flag) in_list "$2" "$FLAGS" || usage "--flag is one of: $FLAGS"; T_FLAGS="${T_FLAGS:+$T_FLAGS }$2" ;;
    --title) T_TITLE="$2" ;;
    --body-file) [ -f "$2" ] && [ -r "$2" ] || usage "--body-file $2 is not a readable file"
                 case "$2" in /*) T_BODY="$2" ;; *) T_BODY="$PWD/$2" ;; esac ;;
    --search) T_SEARCH="$2" ;;
  esac
  shift 2
done

case "$op" in
  file) allowed="type area priority flag title body-file"
        [ -n "$T_TYPE" ] && [ -n "$T_TITLE" ] && [ -n "$T_BODY" ] || usage "file needs --type, --title and --body-file" ;;
  list) allowed="type area priority flag search origin" ;;
  note) allowed="body-file"; [ -n "$T_BODY" ] || usage "note needs --body-file" ;;
  *)    allowed="" ;;
esac
for g in $given; do in_list "$g" "$allowed" || usage "$op takes no --$g"; done
[ "$TRACKER_MODE" = current ] || T_ORIGIN=""

TRACKER_TOP="$(orrery_toplevel "$TRACKER_DIR")"; TRACKER_TOP="${TRACKER_TOP:-$(cd "$TRACKER_DIR" && pwd -P)}"
adapter="$(orrery_tracker "$TRACKER_DIR")"
# shellcheck source=/dev/null
. "$here/tracker/$adapter.sh"
"tracker_${op//-/_}"
