#!/usr/bin/env bash
# Tests hooks/work-archive.sh — records in a project that ignores `.orrery/work/`
# are copied into the main checkout, so `git worktree remove` does not take them.
# Every case runs against a real repository with a real worktree: the hook's whole
# question is which tree a payload touched, and a fixture where the main checkout
# and the worktree are one directory cannot ask it.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
hook="$here/work-archive.sh"

pass=0 fail=0
ok()  { pass=$((pass + 1)); printf '\033[32m✓\033[0m %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '\033[31m✗\033[0m %s — %s\n' "$1" "$2"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2], got [$3]"; fi; }

while IFS='=' read -r _var _; do unset "$_var"; done < <(env | grep '^GIT_')
tmp="$(mktemp -d "${TMPDIR:-/tmp}/work-archive-test.XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT
tmp="$(cd "$tmp" && pwd -P)"

main="$tmp/main"; mkdir -p "$main"
git -C "$main" init -q -b main
git -C "$main" config user.email t@example.invalid; git -C "$main" config user.name t
printf '.orrery/work/\n' > "$main/.gitignore"
git -C "$main" add .gitignore; git -C "$main" commit -q -m init
# Two branch starts a month apart, given to git as epoch seconds and named the
# way the archive names them, so no date is written here as text.
t1=$(( $(date -u +%s) + 86400 )); t2=$(( t1 + 2678400 ))
stamp() { date -u -r "$1" +%Y%m%dT%H%M%SZ 2>/dev/null || date -u -d "@$1" +%Y%m%dT%H%M%SZ; }
k1="$(stamp "$t1")"; k2="$(stamp "$t2")"
GIT_COMMITTER_DATE="$t1 +0000" git -C "$main" worktree add -q -b b1 "$main/wt/w" 2>/dev/null
wt="$main/wt/w"
arch="$main/.orrery/local/work"

write() { # $1 = cwd, $2 = file path — a Write payload as the harness sends it
  printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2" | bash "$hook"
}
bash_() { # $1 = cwd, $2 = command
  jq -cn --arg c "$1" --arg k "$2" '{tool_name:"Bash",cwd:$c,tool_input:{command:$k}}' | bash "$hook"
}

# --- a record written in an ignored tree is copied out ------------------------
mkdir -p "$wt/.orrery/work/w"; printf 'one\n' > "$wt/.orrery/work/w/retrospective.md"
write "$wt" "$wt/.orrery/work/w/retrospective.md"
eq "1 a Write into an ignored work is archived under its branch's start" "one" \
  "$(cat "$arch/w@$k1/retrospective.md" 2>/dev/null)"
eq "2 and the archive ignores itself" '*' "$(cat "$main/.orrery/local/.gitignore" 2>/dev/null)"

printf 'two\n' > "$wt/.orrery/work/w/retrospective.md"
write "$wt" "$wt/.orrery/work/w/retrospective.md"
eq "3 written again: one copy, the newest" "two|1" \
  "$(cat "$arch/w@$k1/retrospective.md")|$(ls "$arch" | wc -l | tr -d ' ')"

# --- the tree is the file's, not the session's --------------------------------
printf 'h\n' > "$wt/.orrery/work/w/handoff.md"
write "$main" "$wt/.orrery/work/w/handoff.md"
eq "4 a session in the main checkout writing into a worktree archives it" "h" \
  "$(cat "$arch/w@$k1/handoff.md" 2>/dev/null)"

# --- a Bash command archives every worktree -----------------------------------
printf 'p\n' > "$wt/.orrery/work/w/plan.md"
bash_ "$main" "cd $wt && skills/build/record.sh write --what x"
eq "5 record.sh run from anywhere archives the worktrees" "p" \
  "$(cat "$arch/w@$k1/plan.md" 2>/dev/null)"

# --- a deletion in the tree takes nothing from the copy -----------------------
# A record removed while the work's directory remains, so the copy runs over a
# partial source: copying over keeps it, replacing the copy would not.
rm "$wt/.orrery/work/w/retrospective.md"
bash_ "$main" "rm $wt/.orrery/work/w/retrospective.md"
eq "6 a record removed in the tree is still in the archive" "two|h" \
  "$(cat "$arch/w@$k1/retrospective.md" 2>/dev/null)|$(cat "$arch/w@$k1/handoff.md" 2>/dev/null)"
rm -rf "$wt/.orrery/work/w"
bash_ "$main" "rm -rf $wt/.orrery/work/w"
eq "6b and so is a whole work removed in the tree" "two" \
  "$(cat "$arch/w@$k1/retrospective.md" 2>/dev/null)"

# --- debt merges per file -----------------------------------------------------
mkdir -p "$wt/.orrery/work/debt"; printf 'a\n' > "$wt/.orrery/work/debt/a.md"
write "$wt" "$wt/.orrery/work/debt/a.md"
rm "$wt/.orrery/work/debt/a.md"; printf 'b\n' > "$wt/.orrery/work/debt/b.md"
write "$wt" "$wt/.orrery/work/debt/b.md"
eq "7 debt is one register, merged per file" "a.md b.md" "$(ls "$arch/debt" | tr '\n' ' ' | sed 's/ $//')"

# --- a reused name is a new copy ----------------------------------------------
git -C "$main" worktree remove --force "$wt"
GIT_COMMITTER_DATE="$t2 +0000" git -C "$main" worktree add -q -b b2 "$main/wt/w" 2>/dev/null
mkdir -p "$wt/.orrery/work/w"; printf 'later\n' > "$wt/.orrery/work/w/retrospective.md"
write "$wt" "$wt/.orrery/work/w/retrospective.md"
eq "8 a later work of the same name is a second copy, the first intact" "later|two" \
  "$(cat "$arch/w@$k2/retrospective.md" 2>/dev/null)|$(cat "$arch/w@$k1/retrospective.md")"

# --- no reflog: the branch's first own commit names it ------------------------
git -C "$main" worktree remove --force "$wt"
git -C "$main" -c core.logAllRefUpdates=false worktree add -q -b b3 "$main/wt/w" 2>/dev/null
rm -f "$main/.git/logs/refs/heads/b3"
git -C "$wt" commit -q --allow-empty -m own
own="$(git -C "$wt" rev-parse HEAD | cut -c1-12)"
rm -f "$main/.git/logs/refs/heads/b3"
mkdir -p "$wt/.orrery/work/w"; printf 'r\n' > "$wt/.orrery/work/w/retrospective.md"
write "$wt" "$wt/.orrery/work/w/retrospective.md"
eq "9 with no reflog the copy is named by the branch's first own commit" "r" \
  "$(cat "$arch/w@$own/retrospective.md" 2>/dev/null)"

# --- where nothing is to be done, nothing is ----------------------------------
before="$(find "$arch" -type f | wc -l | tr -d ' ')"
mkdir -p "$main/.orrery/work/m"; printf 'm\n' > "$main/.orrery/work/m/retrospective.md"
write "$main" "$main/.orrery/work/m/retrospective.md"
eq "10 the main checkout's own records are not copied" "$before" "$(find "$arch" -type f | wc -l | tr -d ' ')"
printf '' > "$wt/.gitignore"
printf 'c\n' > "$wt/.orrery/work/w/retrospective.md"
write "$wt" "$wt/.orrery/work/w/retrospective.md"
eq "11 a project that commits its records gets no copy" "r" \
  "$(cat "$arch/w@$own/retrospective.md")"

# --- cheap first --------------------------------------------------------------
fake="$tmp/bin"; mkdir -p "$fake"
printf '#!/bin/sh\ntouch "%s/git-ran"\nexit 1\n' "$tmp" > "$fake/git"; chmod +x "$fake/git"
printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"ls -la"}}' "$main" \
  | PATH="$fake:$PATH" bash "$hook"
if [ -e "$tmp/git-ran" ]; then bad "12 a command that names no record runs no git" "git ran"
else ok "12 a command that names no record runs no git"; fi
printf 'not json at all .orrery/work' | bash "$hook"; eq "13 an unreadable payload exits 0" "0" "$?"

printf '\n%s checks, %s failing\n' "$((pass + fail))" "$fail"
[ "$fail" -eq 0 ]
