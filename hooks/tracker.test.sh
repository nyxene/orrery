#!/usr/bin/env bash
# Tests hooks/tracker.sh — the one door to the tracker. `none` runs on real files
# in a temp repository; `github` runs against a stub `gh` first on PATH that
# records its argv and its directory, so no case reaches a network. What would
# fail silently is what is pinned: a label that maps to the wrong name, a query on
# a label the tracker lacks answering empty, a legacy config emptying the pool,
# and a gh failure whose words are thrown away.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
t="$here/tracker.sh"

pass=0 fail=0
ok()  { pass=$((pass + 1)); printf '\033[32m✓\033[0m %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '\033[31m✗\033[0m %s — %s\n' "$1" "$2"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2], got [$3]"; fi; }
has() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "[$2] not in [$3]" ;; esac; }

while IFS='=' read -r _var _; do unset "$_var"; done < <(env | grep '^GIT_')
tmp="$(mktemp -d "${TMPDIR:-/tmp}/tracker-test.XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT
tmp="$(cd "$tmp" && pwd -P)"
TAB=$'\t' today="$(date +%Y-%m-%d)"
# Fixture dates are made with `date`, never written: this file ships, and a
# literal date in shipped content is residue to tools/sanitize-scan.sh. Issue
# numbers are five digits, the scan's sanctioned fixture ids, which name nothing.
day() { date -u -r "$1" +%Y-%m-%d 2>/dev/null || date -u -d "@$1" +%Y-%m-%d; }
now="$(date -u +%s)"
old="$(day $((now - 300 * 86400)))" d1="$(day $((now - 30 * 86400)))" d2="$(day $((now - 60 * 86400)))"

# The stub: argv to $GH_DIR/log, one call per line, `|` after each argument.
export GH_DIR="$tmp/gh"; mkdir -p "$GH_DIR" "$tmp/bin"
cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
{ printf '%s|' "$@"; printf '\n'; } >> "$GH_DIR/log"; pwd -P > "$GH_DIR/cwd"
[ ! -e "$GH_DIR/fail" ] || { printf 'HTTP 401: Bad credentials\nrun gh auth login\n' >&2; exit 1; }
case "$1 $2" in
  "label list")   cat "$GH_DIR/labels" ;;
  "issue list")   cat "$GH_DIR/issues.json" ;;
  "issue create") printf 'https://github.com/o/r/issues/99042\n' ;;
esac
EOF
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH"
log() { cat "$GH_DIR/log" 2>/dev/null; }

repo() { mkdir -p "$1/.orrery"; git -C "$1" init -q -b main; git -C "$1" config user.email t@example.invalid; git -C "$1" config user.name t; printf '%s' "$2" > "$1/.orrery/config.json"; }
run() { # <dir> <args…> — tracker.sh from <dir>; sets out, err, rc
  local d="$1"; shift; : > "$GH_DIR/log"
  out="$(cd "$d" && "$t" "$@" 2>"$tmp/err")"; rc=$?; err="$(cat "$tmp/err")"
}
printf 'Some body.\n' > "$tmp/body"

# --- none: the file register ----------------------------------------------------
n="$tmp/none"; repo "$n" '{"areas":["hooks","skills"]}'
run "$n" file --type bug --area hooks --priority low --flag security --flag triage --title "Each key: its own jq!" --body-file "$tmp/body"
eq "1 none file prints the register path" "0|.orrery/work/debt/each-key-its-own-jq.md" "$rc|$out"
eq "2 and writes the D9 header, title and body" \
  "type: bug|area: hooks|priority: low|flags: security,triage|filed: $today||# Each key: its own jq!||Some body." \
  "$(paste -sd'|' "$n/.orrery/work/debt/each-key-its-own-jq.md")"
run "$n" file --type chore --title "Plain one" --body-file "$tmp/body"
eq "3 normal priority and no flags are omitted" "type: chore|filed: $today|" \
  "$(head -3 "$n/.orrery/work/debt/plain-one.md" | paste -sd'|' -)"
run "$n" file --type chore --title "Plain one" --body-file "$tmp/body"
eq "4 a second file of one slug is refused, not overwritten" "1" "$rc"
run "$n" file --type bug --area nowhere --title x --body-file "$tmp/body"
eq "5 an undeclared area is a usage error naming the declared ones" "2|tracker.sh: --area is one of the declared areas: hooks skills" "$rc|$err"
run "$n" file --type debt --title x --body-file "$tmp/body"
has "6 an unknown type names the six" "feature task bug chore research docs" "$rc|$err"
run "$n" list --priority medium
eq "7 medium is no priority: exit 2" "2" "$rc"
run "$n" bogus
eq "8 an unknown op names the ops" "2|tracker.sh: the op is one of: file list note closer labels labels-create" "$rc|$err"
run "$n" list --title x
eq "8b an option the op does not take is a usage error" "2|tracker.sh: list takes no --title" "$rc|$err"
run "$n" file --type bug --title x
eq "8c file without a body is a usage error" "2" "$rc"

printf 'priority: priority/low\narea: area/hooks\nfiled: %s\n\n# Old one\n\n**Origin**: #99012\n## What surfaced it\nNoticed in passing.\n## Where it lives\nhooks/x.sh\n' "$old" \
  > "$n/.orrery/work/debt/old-one.md"
run "$n" list --type chore --area hooks --priority low
eq "9 the old header is read: no type is chore, prefixes stripped" ".orrery/work/debt/old-one.md${TAB}$old${TAB}Old one" "$out"
printf '\n## Where It Came From\n#99003, the work that left it.\n' >> "$n/.orrery/work/debt/plain-one.md"
run "$n" list --type chore --origin
eq "10 --origin marks by the heading and drops nothing, newest first" \
  ".orrery/work/debt/plain-one.md${TAB}$today${TAB}Plain one${TAB}origin|.orrery/work/debt/old-one.md${TAB}$old${TAB}Old one${TAB}no-origin" \
  "$(paste -sd'|' - <<<"$out")"
run "$n" list --flag triage
eq "10b --flag keeps only the items carrying it" ".orrery/work/debt/each-key-its-own-jq.md" "$(cut -f1 <<<"$out")"
run "$n" list --search "NOTICED in"
eq "11 --search greps the body, regardless of case" ".orrery/work/debt/old-one.md" "$(cut -f1 <<<"$out")"
printf 'Seen again.\n' > "$tmp/note"
run "$n" note old-one --body-file "$tmp/note"
eq "12 note appends under What surfaced it" "## What surfaced it|Noticed in passing.|Seen again.|## Where it lives" \
  "$(sed -n '8,11p' "$n/.orrery/work/debt/old-one.md" | paste -sd'|' -)"
run "$n" closer .orrery/work/debt/old-one.md
eq "13 closer is the deletion line" "delete .orrery/work/debt/old-one.md in this change" "$out"
run "$n" closer gone
eq "14 closer on no such item fails" "1" "$rc"
run "$n" labels
eq "15 labels on none: exit 3, unsupported" "3|unsupported: no tracker" "$rc|$out"
run "$n" labels-create
eq "16 labels-create on none: exit 3" "3|unsupported: no tracker" "$rc|$out"
z="$tmp/noareas"; repo "$z" '{}'
run "$z" file --type task --area hooks --title x --body-file "$tmp/body"
has "17 with no areas declared --area is refused" "2|tracker.sh: --area hooks, but the project declares no areas" "$rc|$err"
run "$z" file --type task --title "No area" --body-file "$tmp/body"
eq "18 and file proceeds without one" "0" "$rc"

# --- github: a stub gh ----------------------------------------------------------
g="$tmp/gh-tree"; repo "$g" '{"tracker":"github","areas":["hooks"]}'
all="type/feature type/task type/bug type/chore type/research type/docs priority/critical priority/high priority/low flag/security flag/unread-exempt flag/needs-owner flag/triage area/hooks"
tr ' ' '\n' <<<"$all" > "$GH_DIR/labels"
got=""
for a in "type feature" "type task" "type bug" "type chore" "type research" "type docs" \
         "priority critical" "priority high" "priority low" \
         "flag security" "flag unread-exempt" "flag needs-owner" "flag triage" "area hooks"; do
  set -- $a
  if [ "$1" = type ]; then run "$g" file --type "$2" --title x --body-file "$tmp/body"
  else run "$g" file --type bug --"$1" "$2" --title x --body-file "$tmp/body"; fi
  case "$(log)" in *"--label|$1/$2|"*) got="$got $1/$2" ;; esac
done
eq "19 every value files with its binding label" "$all" "${got# }"
eq "20 file prints the issue number" "#99042|issue|create|--title|x|--body-file|$tmp/body|--label|type/bug|--label|area/hooks|" "$out|$(log)"

jq -n --arg d1 "$d1" --arg d2 "$d2" \
  '[{number:99007,createdAt:"\($d1)T10:00:00Z",title:"A",body:"**Origin**: #99001",labels:[]},
    {number:99005,createdAt:"\($d2)T10:00:00Z",title:"B",body:"x\r\n### where it came from\r\n#99002",labels:[]}]' > "$GH_DIR/issues.json"
run "$g" list --type chore --area hooks --origin
eq "21 list: one labelled query, the origin marked, nothing dropped" \
  "#99007${TAB}$d1${TAB}A${TAB}no-origin|#99005${TAB}$d2${TAB}B${TAB}origin" "$(paste -sd'|' - <<<"$out")"
has "22 with the repeated --label AND and the limit" \
  "issue|list|--state|open|--limit|200|--json|number,createdAt,title,body,labels|--label|type/chore|--label|area/hooks|" "$(log)"
run "$g" list --search "is:open jq"
has "22b --search is passed to gh" "|--search|is:open jq|" "$(log)"
tr ' ' '\n' <<<"$all" | grep -vxF -e flag/triage -e area/hooks > "$GH_DIR/labels"
run "$g" list --flag triage
eq "23 a queried label the tracker lacks: exit 1, named, no query made" "1|yes|" \
  "$rc|$(case "$err" in *flag/triage*) echo yes ;; esac)|$(log | grep '^issue|' || true)"
run "$g" labels
eq "24 labels prints what is lacking, a declared area's included, exit 1" "1|flag/triage|area/hooks" \
  "$rc|$(paste -sd'|' - <<<"$out")"
run "$g" labels-create
eq "25 labels-create makes each with its axis colour" \
  "flag/triage|area/hooks|label|create|flag/triage|--color|5319e7| label|create|area/hooks|--color|0e8a16|" \
  "$(paste -sd'|' - <<<"$out")|$(log | grep '^label|create' | paste -sd' ' -)"
jq -n --arg d "$d1" '[range(200) | {number:., createdAt:"\($d)T00:00:00Z", title:"t", body:"", labels:[]}]' > "$GH_DIR/issues.json"
run "$g" list
has "26 a result at the limit warns on stderr" "warning: 200 items, the limit" "$err"
run "$g" note '#99009' --body-file "$tmp/note"
eq "27 note is a comment" "0|issue|comment|99009|--body-file|$tmp/note|" "$rc|$(log)"
run "$g" closer '#99009'
eq "28 closer is Closes #N" "Closes #99009" "$out"
run "$g" closer x9
eq "29 closer on a non-number is a usage error" "2|" "$rc|$out"
touch "$GH_DIR/fail"
run "$g" list
eq "30 a gh failure exits 1 with gh's own words, indented" "1|    HTTP 401: Bad credentials|    run gh auth login" \
  "$rc|$(sed -n '2,3p' <<<"$err" | paste -sd'|' -)"
rm "$GH_DIR/fail"

# --- legacy mode, and -C --------------------------------------------------------
l="$tmp/legacy"; repo "$l" '{"tracker":"github","debtLabels":{"type":"tech-debt","pool":["area/x"]}}'
printf 'tech-debt\narea/x\n' > "$GH_DIR/labels"
jq -n --arg d "$d2" '[{number:99003,createdAt:"\($d)T00:00:00Z",title:"Old debt",body:"no heading",labels:[{name:"tech-debt"}]}]' > "$GH_DIR/issues.json"
run "$l" list --type chore --area x --origin
eq "31 legacy: chore is the old debt label, the pool's areas answer, --origin is a no-op" \
  "#99003${TAB}$d2${TAB}Old debt|--label|tech-debt|--label|area/x|" "$out|$(log | grep -o -- '--label.*')"
run "$l" labels
has "32 legacy: labels asks for the alias, not type/chore" "type/feature" "$out"
eq "33 and never for type/chore" "" "$(grep -xF type/chore <<<"$out")"
run "$n" -C "$g" closer 99004
eq "34 -C reads the other tree's config" "Closes #99004" "$out"
: > "$GH_DIR/cwd"; printf '%s\n' $all > "$GH_DIR/labels"; printf '[]' > "$GH_DIR/issues.json"
run "$n" -C "$g" list
eq "35 and runs gh in that tree" "$g" "$(cat "$GH_DIR/cwd")"
run "$g" -C "$n" labels
eq "36 and the other way: a none tree from a github one" "3" "$rc"

# --- end to end: no config, and a gh that is not there (127, every call logged) ---
e="$tmp/bare"; mkdir -p "$e" "$tmp/nogh"; git -C "$e" init -q -b main; P0="$PATH"; PATH="$tmp/nogh:$PATH"
printf '#!/bin/sh\necho "$*" >> "%s/nogh/log"; exit 127\n' "$tmp" > "$tmp/nogh/gh"; chmod +x "$tmp/nogh/gh"
printf 'Left untidy.\n\n## Where it came from\nThe work that left it.\n' > "$tmp/e2e"
run "$e" file --type chore --title "Tidy the seam" --body-file "$tmp/e2e"; f="$out"
run "$e" list --type chore --origin; l="$out"; run "$e" closer "$f"; PATH="$P0"
eq "37 no config, no gh: file, list --origin, closer, and gh never called" \
  ".orrery/work/debt/tidy-the-seam.md|$f${TAB}$today${TAB}Tidy the seam${TAB}origin|delete $f in this change|" \
  "$f|$l|$out|$(cat "$tmp/nogh/log" 2>/dev/null)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
