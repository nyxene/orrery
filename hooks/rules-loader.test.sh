#!/usr/bin/env bash
# Tests hooks/rules-loader.sh against its contract.
#
# This hook fires before every tool call and emits nothing on most of them, so
# "emitted nothing" is both its normal state and its total failure. A scope that
# stopped loading would look like a scope with no rules, in a session nobody was
# watching, for as long as it took someone to notice their own conventions
# drifting.
#
# Two of the cases below are about the second layer: the rules a host project
# filed for itself, under `.claude/rules/`. A shipped rule and a local one carry
# the same weight and differ only in where they were earned, so a loader that
# reads one and quietly drops the other is the failure worth pinning.
#
# The crowding warning gets its own boundary cases because it is the only thing
# that triggers a prune pass: if it stops firing, the rule layer grows until it
# is skimmed rather than read, which is the failure it was written to prevent.
#
# State — the once-per-scope-per-session markers — lives in a repository's
# `.orrery/local/sessions/`, and in $TMPDIR outside one. The fixture projects
# below are not repositories and $TMPDIR is pointed here, so every run gets its
# own and the live session's markers are neither read nor written; the last
# case stands in a repository on purpose.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
hook="$here/rules-loader.sh"

pass=0 fail=0
ok()  { pass=$((pass + 1)); printf '\033[32m✓\033[0m %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '\033[31m✗\033[0m %s — %s\n' "$1" "$2"; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/rules-loader-test.XXXXXX")"
state="$tmp/state"; mkdir -p "$state"
project="$tmp/project"; mkdir -p "$project"
fakebin="$tmp/nojq"; mkdir -p "$fakebin"
for c in cat bash dirname mkdir; do ln -s "$(command -v "$c")" "$fakebin/$c"; done
trap 'rm -rf "$tmp"' EXIT

mkrule() { # $1 = scope dir, $2 = file, $3 = rule sentence, $4 = field, $5 = value
  mkdir -p "$1"
  {
    echo '---'
    [ -n "$3" ] && echo "rule: $3"
    [ -n "$5" ] && echo "$4: $5"
    echo '---'
    echo 'The body, which must not be loaded.'
  } > "$1/$2"
}

run() { # $1 = plugin root (empty for unset), $2 = payload JSON
  if [ -n "$1" ]; then
    TMPDIR="$state" CLAUDE_PROJECT_DIR="$project" CLAUDE_PLUGIN_ROOT="$1" \
      bash "$hook" <<<"$2" 2>/dev/null
  else
    TMPDIR="$state" CLAUDE_PROJECT_DIR="$project" env -u CLAUDE_PLUGIN_ROOT \
      bash "$hook" <<<"$2" 2>/dev/null
  fi
}

edit_payload() { jq -n --arg s "$1" '{tool_name:"Edit",session_id:$s}'; }
bash_payload() { jq -n --arg s "$1" --arg c "$2" '{tool_name:"Bash",session_id:$s,tool_input:{command:$c}}'; }
context()      { jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null <<<"$1"; }

# --- a scope with rules emits them, once each -------------------------------
root="$tmp/root"
mkrule "$root/rules/craft" first.md  'the first rule sentence' evidence 'an afternoon'
mkrule "$root/rules/craft" second.md 'the second rule sentence' evidence 'a lost report'
out="$(run "$root" "$(edit_payload s1)")"
body="$(context "$out")"
n="$(grep -c '^- ' <<<"$body")"
if ! jq -e . >/dev/null 2>&1 <<<"$out"; then
  bad "a scope with rules emits them" "output is not valid JSON: $out"
elif [ "$n" -ne 2 ]; then
  bad "a scope with rules emits them" "expected 2 rule lines, got $n"
elif ! grep -q 'the first rule sentence' <<<"$body" || ! grep -q 'the second rule sentence' <<<"$body"; then
  bad "a scope with rules emits them" "a rule sentence is missing"
elif ! grep -q 'an afternoon' <<<"$body"; then
  bad "a scope with rules emits them" "the evidence is missing, and it is what makes the rule evidence"
elif ! grep -q 'rules/craft/first.md' <<<"$body"; then
  bad "a scope with rules emits them" "the path is missing, so the full text cannot be reached"
else
  ok "a scope with rules emits each one once, with its evidence and path"
fi

# --- and never the body -----------------------------------------------------
if grep -q 'must not be loaded' <<<"$body"; then
  bad "only the frontmatter is loaded" "the rule body came through too"
else
  ok "only the frontmatter is loaded, never the body"
fi

# --- the host project's own rules load beside the shipped ones --------------
mkrule "$project/.claude/rules/craft" local.md 'a rule this project earned' cost 'a broken deploy'
out="$(context "$(run "$root" "$(edit_payload s2)")")"
if ! grep -q 'a rule this project earned' <<<"$out"; then
  bad "local rules load beside shipped ones" "the project's own rule never arrived"
elif [ "$(grep -c '^- ' <<<"$out")" -ne 3 ]; then
  bad "local rules load beside shipped ones" "expected 3 rule lines, got $(grep -c '^- ' <<<"$out")"
elif ! grep -q 'this project' <<<"$out"; then
  bad "local rules load beside shipped ones" "nothing says which layer the rule came from"
else
  ok "a host project's own rules load beside the shipped ones, and are labelled"
fi

# --- a local rule keeps carrying cost: ---------------------------------------
# Shipped rules carry `evidence:`; a rule `learn` files locally carries `cost:`.
# Reading only one of the two silently drops half the layer.
if grep -q 'a broken deploy' <<<"$out"; then
  ok "a local rule's cost: is read, not only a shipped rule's evidence:"
else
  bad "a local rule's cost: is read" "the local rule arrived without what it cost"
fi

# --- once per scope per session ---------------------------------------------
out="$(run "$root" "$(edit_payload s2)")"
if [ -n "$out" ]; then
  bad "a scope loads once per session" "it emitted a second time"
else
  ok "a second call in the same scope and session emits nothing"
fi

# --- but a new session starts over ------------------------------------------
out="$(run "$root" "$(edit_payload s3)")"
if [ -z "$(context "$out")" ]; then
  bad "a new session loads the scope again" "the second session got nothing"
else
  ok "a new session loads the same scope again"
fi

# --- the tool decides the scope ---------------------------------------------
mkrule "$root/rules/git" g.md 'a rule about git' evidence 'a lost branch'
out="$(context "$(run "$root" "$(bash_payload s4 'git status')")")"
if grep -q 'a rule about git' <<<"$out"; then
  ok "a Bash call running git enters the git scope"
else
  bad "a Bash call running git enters the git scope" "nothing was emitted"
fi

out="$(run "$root" "$(bash_payload s5 'ls -la')")"
if [ -z "$out" ]; then
  ok "a Bash call with no scope costs nothing"
else
  bad "a Bash call with no scope costs nothing" "it emitted: $out"
fi

# --- neither directory present is not an error ------------------------------
bare="$tmp/bare"; mkdir -p "$bare"
empty_project="$tmp/empty-project"; mkdir -p "$empty_project"
out="$(TMPDIR="$state" CLAUDE_PROJECT_DIR="$empty_project" CLAUDE_PLUGIN_ROOT="$bare" \
        bash "$hook" <<<"$(edit_payload s6)" 2>/dev/null)"; rc=$?
if [ -z "$out" ] && [ "$rc" -eq 0 ]; then
  ok "no rules directory at all prints nothing and exits 0"
else
  bad "no rules directory at all prints nothing and exits 0" "exit $rc, output: $out"
fi

# --- a rule without the field the loader reads is skipped, not half-emitted --
partial="$tmp/partial"
mkrule "$partial/rules/craft" good.md 'a complete rule' evidence 'a real cost'
mkrule "$partial/rules/craft" nofield.md '' evidence 'evidence with no rule'
out="$(context "$(TMPDIR="$state" CLAUDE_PROJECT_DIR="$empty_project" CLAUDE_PLUGIN_ROOT="$partial" \
        bash "$hook" <<<"$(edit_payload s7)" 2>/dev/null)")"
n="$(grep -c '^- ' <<<"$out")"
if [ "$n" -eq 1 ] && grep -q 'a complete rule' <<<"$out"; then
  ok "a rule with no rule: line is skipped and its neighbour still loads"
else
  bad "a rule with no rule: line is skipped" "expected 1 rule line, got $n"
fi

# --- a rule with nothing recorded says so rather than emitting a blank ------
nocost="$tmp/nocost"
mkrule "$nocost/rules/craft" c.md 'a rule that cost nothing yet' evidence ''
out="$(context "$(TMPDIR="$state" CLAUDE_PROJECT_DIR="$empty_project" CLAUDE_PLUGIN_ROOT="$nocost" \
        bash "$hook" <<<"$(edit_payload s8)" 2>/dev/null)")"
if grep -q 'not recorded' <<<"$out"; then
  ok "a rule with nothing recorded is emitted as 'not recorded'"
else
  bad "a rule with nothing recorded is emitted as 'not recorded'" "got: $out"
fi

# --- the crowding warning, at both sides of its threshold -------------------
ten="$tmp/ten"
for i in 1 2 3 4 5 6 7 8 9 10; do mkrule "$ten/rules/craft" "r$i.md" "rule number $i" evidence 'a cost'; done
out="$(context "$(TMPDIR="$state" CLAUDE_PROJECT_DIR="$empty_project" CLAUDE_PLUGIN_ROOT="$ten" \
        bash "$hook" <<<"$(edit_payload s9)" 2>/dev/null)")"
if grep -q 'crowded' <<<"$out"; then
  bad "ten rules do not trigger the prune warning" "it warned at ten"
else
  ok "ten rules do not trigger the prune warning"
fi

eleven="$tmp/eleven"
for i in 1 2 3 4 5 6 7 8 9 10 11; do mkrule "$eleven/rules/craft" "r$i.md" "rule number $i" evidence 'a cost'; done
out="$(context "$(TMPDIR="$state" CLAUDE_PROJECT_DIR="$empty_project" CLAUDE_PLUGIN_ROOT="$eleven" \
        bash "$hook" <<<"$(edit_payload s10)" 2>/dev/null)")"
if grep -q 'crowded' <<<"$out" && grep -q '11 rules' <<<"$out"; then
  ok "eleven rules trigger the prune warning, and it names the count"
else
  bad "eleven rules trigger the prune warning" "no warning, or it did not name 11"
fi

# --- an unset plugin root falls back to the hook's own directory ------------
out="$(context "$(run "" "$(edit_payload s11)")")"
if grep -q '^- ' <<<"$out"; then
  ok "an unset CLAUDE_PLUGIN_ROOT falls back to the plugin's own rules"
else
  bad "an unset CLAUDE_PLUGIN_ROOT falls back to the plugin's own rules" "nothing loaded"
fi

# --- a rule about issues loads only where there is a tracker ------------------
mkrule "$root/rules/git" plain.md  'a rule for every project' evidence x
mkrule "$root/rules/git" issues.md 'a rule about issues' tracker github
saved="$project"; project="$tmp/tracker-repo"; git init -q -b main "$project"
body="$(context "$(run "$root" "$(bash_payload s-notracker 'git status')")")"
if grep -q 'a rule for every project' <<<"$body" && ! grep -q 'a rule about issues' <<<"$body"; then
  ok "with no tracker, a rule marked tracker: github stays out"
else
  bad "with no tracker, a rule marked tracker: github stays out" "$body"
fi
mkdir -p "$project/.orrery"; printf '{"tracker":"github"}' > "$project/.orrery/config.json"
body="$(context "$(run "$root" "$(bash_payload s-github 'git status')")")"
project="$saved"
if grep -q 'a rule about issues' <<<"$body" && grep -q 'a rule for every project' <<<"$body"; then
  ok "with a GitHub tracker it loads"
else
  bad "with a GitHub tracker it loads" "$body"
fi

# --- a push loads the process rules once, then is a git command -------------
mkrule "$root/rules/process" consent.md 'a process rule' evidence z
body="$(context "$(run "$root" "$(bash_payload s-push 'git push origin feat')")")"
if grep -q 'a process rule' <<<"$body"; then ok "a session's first push loads the process rules"
else bad "a session's first push loads the process rules" "$body"; fi
body="$(context "$(run "$root" "$(bash_payload s-push 'git push origin feat')")")"
if grep -q 'a rule for every project' <<<"$body" && ! grep -q 'a process rule' <<<"$body"; then
  ok "and the next push enters the git rules instead"
else bad "and the next push enters the git rules instead" "$body"; fi

# --- without jq it says so once, then stops repeating itself ----------------
# The payload is built before PATH is narrowed: a here-string is expanded with
# the command's environment already in place, so building it inline would run jq
# with jq removed and feed the hook an empty document.
nojq_payload="$(edit_payload s12)"
nojq() { TMPDIR="$state/nojq" PATH="$fakebin" CLAUDE_PLUGIN_ROOT="$root" \
           "$fakebin/bash" "$hook" <<<"$nojq_payload" 2>/dev/null; }
out="$(nojq)"
if ! grep -q 'WARNING' <<<"$out"; then
  bad "no jq is announced" "expected a WARNING payload, got: $out"
elif [ -n "$(nojq)" ]; then
  bad "no jq is announced once" "it warned again on the next tool call"
else
  ok "no jq is announced once, then the loader stays quiet"
fi

# --- in a repository the markers are Orrery's own ----------------------------
while IFS='=' read -r _var _; do unset "$_var"; done < <(env | grep '^GIT_')
repo="$tmp/repo"; mkdir -p "$repo"; git -C "$repo" init -q -b main
git -C "$repo" config user.email t@example.invalid; git -C "$repo" config user.name t
( cd "$repo" && TMPDIR="$state" CLAUDE_PROJECT_DIR="$repo" CLAUDE_PLUGIN_ROOT="$root" \
    bash "$hook" <<<"$(edit_payload s-repo)" >/dev/null 2>&1 )
if [ -n "$(find "$repo/.orrery/local/sessions" -name 'rules-s-repo-*' 2>/dev/null)" ] \
   && [ -z "$(git -C "$repo" status --porcelain)" ]; then
  ok "in a repository the marker lands in .orrery/local/sessions/, where git does not see it"
else
  bad "in a repository the marker lands in .orrery/local/sessions/" "$(ls -R "$repo/.orrery" 2>&1)"
fi

printf '\n%s cases, %s passing, %s failing\n' "$((pass + fail))" "$pass" "$fail"
[ "$fail" -eq 0 ]
