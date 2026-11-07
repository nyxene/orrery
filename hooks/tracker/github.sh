# The `github` adapter of hooks/tracker.sh: each op is one `gh` verb run in the
# target tree, so `gh` infers the repository from that tree's origin. Sourced by
# tracker.sh, which has already checked every argument.
#
# The labels are the method's GitHub binding, not a setting: `type/<v>`,
# `area/<v>`, `priority/<v>`, `flag/<v>`, one colour per axis. The one exception
# is legacy mode, where the chore type is the project's old debt label.
#
# Nothing `gh` says on failure is thrown away. A label nobody created makes a
# query answer an empty list, not an error, and an empty list reads exactly like
# a clean backlog — so `list` asks for the labels first and refuses on one the
# tracker lacks, and every failed call prints gh's own words, indented.

# gh in the target tree. Its stdout is the answer; on failure its stderr is
# printed and the script exits 1. Called in `$(…)`, the caller adds `|| exit 1`.
gh_() {
  local out err rc
  command -v gh >/dev/null 2>&1 || fail "the tracker is github and gh is not on PATH"
  err="$(mktemp "${TMPDIR:-/tmp}/tracker-gh.XXXXXX")" || fail "cannot make a temp file"
  out="$(cd "$TRACKER_DIR" && gh "$@" 2>"$err")"; rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'tracker.sh: gh %s %s failed (exit %s):\n' "$1" "$2" "$rc" >&2
    sed 's/^/    /' "$err" >&2
    rm -f "$err"; exit 1
  fi
  rm -f "$err"
  printf '%s' "$out"
}

label_of() { # <axis> <value>
  if [ "$1" = type ] && [ "$2" = chore ]; then printf '%s\n' "$TRACKER_CHORE"
  else printf '%s/%s\n' "$1" "$2"; fi
}

# The labels this call's own arguments name, one per line.
arg_labels() {
  local f
  [ -z "$T_TYPE" ] || label_of type "$T_TYPE"
  [ -z "$T_AREA" ] || label_of area "$T_AREA"
  [ -z "$T_PRIO" ] || label_of priority "$T_PRIO"
  for f in $T_FLAGS; do label_of flag "$f"; done
}

# Every label the binding and the declared areas need.
needed_labels() {
  local v
  for v in $TYPES; do label_of type "$v"; done
  for v in $PRIORITIES; do label_of priority "$v"; done
  for v in $FLAGS; do label_of flag "$v"; done
  for v in $TRACKER_AREAS; do label_of area "$v"; done
}

# The labels on stdin that the tracker does not have.
lacking() {
  local have
  have="$(gh_ label list --limit "$LIMIT" --json name --jq '.[].name')" || exit 1
  # Through the environment: BSD awk refuses a newline in a -v value.
  HAVE="$have" awk 'BEGIN { n = split(ENVIRON["HAVE"], h, "\n"); for (i = 1; i <= n; i++) H[h[i]] = 1 }
    NF && !($0 in H)'
}

issue_number() {
  local n="${T_ID#\#}"
  case "$n" in ''|*[!0-9]*) usage "an issue id is #N or N, not $T_ID" ;; esac
  printf '%s' "$n"
}

tracker_file() {
  local args=(--title "$T_TITLE" --body-file "$T_BODY") l url
  while IFS= read -r l; do [ -z "$l" ] || args+=(--label "$l"); done <<<"$(arg_labels)"
  url="$(gh_ issue create "${args[@]}")" || exit 1
  printf '#%s\n' "${url##*/}"
}

tracker_list() {
  local labels l args=() json n
  labels="$(arg_labels)"
  if [ -n "$labels" ]; then
    l="$(printf '%s\n' "$labels" | lacking)" || exit 1
    [ -z "$l" ] || fail "the tracker has no label $(printf '%s' "$l" | tr '\n' ' ')— a query on it answers empty whatever is filed"
    while IFS= read -r l; do args+=(--label "$l"); done <<<"$labels"
  fi
  [ -z "$T_SEARCH" ] || args+=(--search "$T_SEARCH")
  json="$(gh_ issue list --state open --limit "$LIMIT" --json number,createdAt,title,body,labels ${args[@]+"${args[@]}"})" || exit 1
  n="$(jq length <<<"$json")" || fail "gh issue list answered something that is not JSON"
  [ "$n" -lt "$LIMIT" ] || printf 'tracker.sh: warning: %s items, the limit — the list may be cut short\n' "$n" >&2
  jq -r --arg re "$ORIGIN_RE" --arg o "$T_ORIGIN" '.[]
    | ["#\(.number)", .createdAt[0:10], .title]
      + (if $o == "" then [] elif ((.body // "") | split("\n") | any(test($re; "i"))) then ["origin"] else ["no-origin"] end)
    | join("\t")' <<<"$json"
}

tracker_note() {
  local n; n="$(issue_number)" || exit 2
  gh_ issue comment "$n" --body-file "$T_BODY" >/dev/null
}

tracker_closer() { local n; n="$(issue_number)" || exit 2; printf 'Closes #%s\n' "$n"; }

tracker_labels() {
  local m
  m="$(needed_labels | lacking)" || exit 1
  [ -n "$m" ] || return 0
  printf '%s\n' "$m"
  printf 'tracker.sh: the tracker lacks the labels above; `tracker.sh labels-create` makes them\n' >&2
  exit 1
}

colour_of() {
  case "$1" in
    area/*) printf 0e8a16 ;; priority/*) printf d93f0b ;; flag/*) printf 5319e7 ;;
    *) printf 1d76db ;;  # type/*, and legacy mode's unprefixed chore label
  esac
}

tracker_labels_create() {
  local m l
  m="$(needed_labels | lacking)" || exit 1
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    gh_ label create "$l" --color "$(colour_of "$l")" >/dev/null
    printf '%s\n' "$l"
  done <<<"$m"
}
