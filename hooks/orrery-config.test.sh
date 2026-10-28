#!/usr/bin/env bash
# Tests hooks/orrery-config.sh — where Orrery's state lives and what the project
# declared. Every hook that moves its files into `.orrery/` asks these functions,
# so a wrong answer here is the same wrong path in every one of them, silently.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=hooks/orrery-config.sh
. "$here/orrery-config.sh"

pass=0 fail=0
ok()  { pass=$((pass + 1)); printf '\033[32m✓\033[0m %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '\033[31m✗\033[0m %s — %s\n' "$1" "$2"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2], got [$3]"; fi; }

while IFS='=' read -r _var _; do unset "$_var"; done < <(env | grep '^GIT_')
tmp="$(mktemp -d "${TMPDIR:-/tmp}/orrery-config-test.XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT
tmp="$(cd "$tmp" && pwd -P)"

main="$tmp/main"; mkdir -p "$main"
git -C "$main" init -q -b main
git -C "$main" config user.email t@example.invalid; git -C "$main" config user.name t
git -C "$main" commit -q --allow-empty -m init
git -C "$main" worktree add -q -b feat/x "$main/.claude/worktrees/feat-x" 2>/dev/null
wt="$main/.claude/worktrees/feat-x"

# --- roots ---------------------------------------------------------------------
eq "1 the main checkout, from the main checkout" "$main" "$(orrery_main "$main")"
eq "2 the main checkout, from inside a worktree" "$main" "$(orrery_main "$wt")"
eq "3 the toplevel of a worktree is the worktree" "$wt" "$(orrery_toplevel "$wt")"
eq "4 outside a repository there is no main checkout" "" "$(orrery_main "$tmp")"

# --- defaults, values, and a file that cannot be read --------------------------
eq "5 no config: the default" "none" "$(orrery_tracker "$main")"
eq "6 no config: an absent key's default" "true" "$(orrery_config callLog true "$main")"
mkdir -p "$main/.orrery"
printf '{"tracker":"github","callLog":false,"debtLabels":{"type":"t"}}' > "$main/.orrery/config.json"
eq "7 a declared tracker" "github" "$(orrery_tracker "$main")"
eq "8 a boolean prints as JSON, not as its default" "false" "$(orrery_config callLog true "$main")"
eq "9 an object prints as compact JSON" '{"type":"t"}' "$(orrery_config debtLabels "" "$main")"
printf '{"tracker":"gitlab"}' > "$main/.orrery/config.json"
eq "10 an unknown tracker is none, not passed through" "none" "$(orrery_tracker "$main")"
printf 'not json' > "$main/.orrery/config.json"
eq "11 a malformed file is the defaults" "none" "$(orrery_tracker "$main")"
eq "12 and is reported as malformed" "malformed" "$(orrery_config_problem "$main")"
eq "13 the worktree reads its own tree's config, not the main checkout's" "none" "$(orrery_tracker "$wt")"

# --- a missing config is a problem only on GitHub ------------------------------
rm -f "$main/.orrery/config.json"
eq "14 no config and no GitHub remote is not a problem" "" "$(orrery_config_problem "$main")"
git -C "$main" remote add origin https://github.com/example/example.git
eq "15 no config beside a GitHub remote is reported" "missing" "$(orrery_config_problem "$main")"

# --- a machine-local config: the main checkout's, read from every worktree ----
loc="$main/.orrery/local/config.json"; mkdir -p "$main/.orrery/local"
printf '{"outputLanguage":"Russian"}' > "$loc"
eq "15a a local file with no tracker does not hide that it is missing" "missing" "$(orrery_config_problem "$wt")"
printf '{"tracker":"github","callLog":false}' > "$loc"
eq "15b a worktree reads the main checkout's local file" "github" "$(orrery_tracker "$wt")"
eq "15c and the tracker is no longer missing" "" "$(orrery_config_problem "$wt")"
eq "15d its source is named as local" "local" "$(orrery_config_source tracker "$wt")"
mkdir -p "$wt/.orrery"; printf '{"callLog":true}' > "$wt/.orrery/config.json"
eq "15e a key both declare: the committed file wins" "true" "$(orrery_config callLog x "$wt")"
eq "15f a key only the local file declares still fills in" "github" "$(orrery_tracker "$wt")"
eq "15g and the winning key's source is the committed file" "committed" "$(orrery_config_source callLog "$wt")"
printf '{}' > "$loc"
eq "15h a committed file that leaves the tracker out has decided" "" "$(orrery_config_problem "$wt")"
printf 'nope' > "$loc"
eq "15i a malformed local file is reported as such" "malformed-local" "$(orrery_config_problem "$wt")"
eq "15j and the committed file is still read" "true" "$(orrery_config callLog x "$wt")"
printf 'nope' > "$wt/.orrery/config.json"
eq "15k both malformed is said of both" "malformed-both" "$(orrery_config_problem "$wt")"
printf '[1]' > "$loc"; printf '{"tracker":"github"}' > "$wt/.orrery/config.json"
eq "15l a local file that is not an object is reported, and ignored" "malformed-local/github" \
  "$(orrery_config_problem "$wt")/$(orrery_tracker "$wt")"
printf '{"tracker":"github"} {}' > "$wt/.orrery/config.json"; rm -f "$loc"
eq "15n two documents in one file are malformed, not one setting each" "malformed/none" \
  "$(orrery_config_problem "$wt")/$(orrery_tracker "$wt")"
rm -rf "$wt/.orrery" "$loc"
eq "15m with neither file a key's source is the default" "default" "$(orrery_config_source tracker "$wt")"

# --- the work's name -----------------------------------------------------------
eq "16 a worktree's work is its directory name" "feat-x" "$(orrery_work "$wt")"
git -C "$main" checkout -q -b team/fix 2>/dev/null
eq "17 on the main checkout: the branch, slashes replaced, no date" \
  "team-fix" "$(orrery_work "$main")"
born="$(orrery_born team/fix "$main")"
eq "17a a branch began at its first reflog entry, in the call log's spelling" ok \
  "$([[ $born =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] && [[ ! $born > $(date -u +%Y-%m-%dT%H:%M:%SZ) ]] && echo ok)"
eq "17b a branch with no reflog began at no known time" "" "$(orrery_born no-such-branch "$main")"

# --- the per-machine directory -------------------------------------------------
d="$(orrery_local_ensure "$wt")"
eq "18 local/ belongs to the main checkout, even from a worktree" "$main/.orrery/local" "$d"
eq "19 it ignores itself, so nothing in it can be committed" '*' "$(cat "$d/.gitignore" 2>/dev/null)"
touch "$d/calls.tsv"
eq "20 git add -A stages nothing under it" "" "$(git -C "$main" add -A --dry-run -- .orrery/local 2>/dev/null)"

# --- a file that moved: copied once, the old one kept --------------------------
mkdir -p "$main/.claude"; printf 'old row\n' > "$main/.claude/orrery-waivers.tsv"
eq "21 before the move a reader finds the old file" "$main/.claude/orrery-waivers.tsv" \
  "$(orrery_local_read waivers.tsv .claude/orrery-waivers.tsv "$wt")"
f="$(orrery_local_file waivers.tsv .claude/orrery-waivers.tsv "$wt")"
eq "22 the new path is under local/" "$main/.orrery/local/waivers.tsv" "$f"
eq "23 the old rows came with it" "old row" "$(cat "$f" 2>/dev/null)"
eq "24 the old file is left for a rollback" "old row" "$(cat "$main/.claude/orrery-waivers.tsv")"
printf 'new row\n' >> "$f"; printf 'later old row\n' >> "$main/.claude/orrery-waivers.tsv"
orrery_local_file waivers.tsv .claude/orrery-waivers.tsv "$wt" >/dev/null
eq "25 the copy happens once, never over newer rows" "old row
new row" "$(cat "$f")"
eq "26 after the move a reader finds the new file" "$f" \
  "$(orrery_local_read waivers.tsv .claude/orrery-waivers.tsv "$wt")"
mkdir -p "$tmp/olddir"; printf 'x\n' > "$tmp/olddir/a.md"
eq "27 an absolute old directory is copied whole" "x" \
  "$(cat "$(orrery_local_file doctor "$tmp/olddir" "$main")/a.md" 2>/dev/null)"
if orrery_local_file x "" "$tmp" >/dev/null; then bad "28 outside a repository there is no file" "returned 0"
else ok "28 outside a repository there is no file"; fi

printf '\n%s checks, %s failing\n' "$((pass + fail))" "$fail"
[ "$fail" -eq 0 ]
