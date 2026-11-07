# The `none` adapter of hooks/tracker.sh: a project with no tracker keeps its
# register as files, `.orrery/work/debt/<slug>.md`, one per item, committed with
# the work that found it. Sourced by tracker.sh, which has already checked every
# argument; these functions only read and write the files.
#
# A file opens with header lines, bare values, then the title and the body:
#
#   type: chore
#   area: hooks
#   priority: low              omitted when normal
#   flags: security,triage     omitted when none
#   filed: YYYY-MM-DD
#
#   # <title>
#
# The header written before the classification is still read: `area: area/hooks`
# and `priority: priority/low` lose their prefix, `medium` answers no
# `--priority` (it is normal now), and a file with no `type:` is a chore — every
# item filed that way was debt.
#
# The id is the file's path from the tree's top. Closing an item is deleting its
# file in the change that pays it, so there are no labels here to check or make.

REG_REL=.orrery/work/debt
REG="$TRACKER_TOP/$REG_REL"

# The file an id names: its path, absolute or from the top, or its bare slug.
none_path() {
  local p
  case "$1" in /*) p="$1" ;; */*) p="$TRACKER_TOP/$1" ;; *) p="$REG/${1%.md}.md" ;; esac
  [ -f "$p" ] || fail "no item $1 in $REG_REL"
  printf '%s' "$p"
}

tracker_file() {
  local slug f
  slug="$(printf '%s' "$T_TITLE" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//' | cut -c1-60 | sed -E 's/-+$//')"
  [ -n "$slug" ] || usage "the title has no letter or digit to name its file by"
  f="$REG/$slug.md"
  [ ! -e "$f" ] || fail "$REG_REL/$slug.md already exists — a second sighting is a note on it, not a second file"
  mkdir -p "$REG" || fail "cannot create $REG_REL"
  { printf 'type: %s\n' "$T_TYPE"
    [ -z "$T_AREA" ] || printf 'area: %s\n' "$T_AREA"
    [ -z "$T_PRIO" ] || printf 'priority: %s\n' "$T_PRIO"
    [ -z "$T_FLAGS" ] || printf 'flags: %s\n' "${T_FLAGS// /,}"
    printf 'filed: %s\n\n# %s\n\n' "$(date +%Y-%m-%d)" "$T_TITLE"
    cat "$T_BODY"
  } > "$f" || fail "cannot write $REG_REL/$slug.md"
  printf '%s\n' "$REG_REL/$slug.md"
}

# Newest first by `filed:`, as the tracker lists newest first.
tracker_list() {
  set -- "$REG"/*.md
  [ -e "$1" ] || return 0
  # The search text through the environment: -v would read its backslashes.
  SEARCH="$T_SEARCH" awk -v type="$T_TYPE" -v area="$T_AREA" -v prio="$T_PRIO" -v flags="$T_FLAGS" \
      -v origin="$T_ORIGIN" -v re="$ORIGIN_RE" -v top="$TRACKER_TOP/" '
    BEGIN { search = ENVIRON["SEARCH"] }
    function flush(  n, i, F, id, line) {
      if (t == "") t = "chore"
      if ((type != "" && t != type) || (area != "" && a != area) || (prio != "" && p != prio)) return
      n = split(flags, F, " ")
      for (i = 1; i <= n; i++) if (index(fl, "," F[i] ",") == 0) return
      if (search != "" && index(tolower(title "\n" text), tolower(search)) == 0) return
      id = file; if (index(id, top) == 1) id = substr(id, length(top) + 1)
      line = id "\t" d "\t" title
      if (origin != "") line = line "\t" (has ? "origin" : "no-origin")
      print line
    }
    FNR == 1 { if (NR > 1) flush(); file = FILENAME; hdr = 1; t = a = p = d = title = text = ""; fl = ","; has = 0 }
    { sub(/\r$/, "") }
    hdr && /^[a-z]+:/ {
      k = $0; sub(/:.*/, "", k); v = $0; sub(/^[^:]*:[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v)
      if (k == "type") t = v
      else if (k == "area") { sub(/^area\//, "", v); a = v }
      else if (k == "priority") { sub(/^priority\//, "", v); p = v }
      else if (k == "flags") { gsub(/[[:space:]]/, "", v); fl = "," v "," }
      else if (k == "filed") d = v
      next
    }
    hdr && /^# / { title = substr($0, 3); hdr = 0; next }
    hdr && /^[[:space:]]*$/ { next }
    { hdr = 0; text = text "\n" $0; if (tolower($0) ~ re) has = 1 }
    END { if (NR > 0) flush() }
  ' "$@" | sort -t "$(printf '\t')" -k2,2r
}

# The body goes at the end of *What surfaced it*, where a second sighting
# belongs; a file without that heading gets it.
tracker_note() {
  local p
  p="$(none_path "$T_ID")" || exit 1
  awk -v bodyf="$T_BODY" '
    function emit(  l) { while ((getline l < bodyf) > 0) print l; close(bodyf); done = 1 }
    insec && /^## / { emit(); insec = 0 }
    { print }
    !done && tolower($0) ~ /^##[[:space:]]+what surfaced it[[:space:]]*$/ { insec = 1 }
    END { if (!done) { if (!insec) print "\n## What surfaced it"; emit() } }
  ' "$p" > "$p.tmp.$$" && mv "$p.tmp.$$" "$p" || { rm -f "$p.tmp.$$"; fail "cannot write $p"; }
}

tracker_closer() {
  local p
  p="$(none_path "$T_ID")" || exit 1
  printf 'delete %s in this change\n' "${p#"$TRACKER_TOP"/}"
}

tracker_labels()        { unsupported "no tracker"; }
tracker_labels_create() { unsupported "no tracker"; }
