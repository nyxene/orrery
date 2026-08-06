#!/usr/bin/env bash
# Checks the library's checkable claims about itself.
#
# `sharpen`'s health pass looks for dangling references, disagreements and
# unreachable material. Three of its six checks are mechanical — a path either
# exists or does not, a count either matches `find` or does not — and doing them
# by hand is how they get skipped. In one audit round this file's checks were
# each run manually, from memory, three times.
#
# What it caught when it was written, all of which had been found by hand first:
# an orphaned root document, a frontmatter field documented in README that no
# rule carries, labels declared in CLAUDE.md that the tracker did not have, and
# four counter sentences that had gone stale in a single week.
#
# It cannot check prose. A skill that contradicts another skill in meaning, or a
# rule whose advice is wrong, is invisible here — that is what the reading half
# of a health pass is for, and this replaces none of it.
set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
fail=0
note() { printf '  %s\n' "$1"; fail=1; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '\033[31m✗\033[0m %s\n' "$1"; }

# Everything this repository holds that makes a claim about itself. `.githooks`
# is in the list because the hook names the gates it runs, and a gate whose
# files are not here is red on the first commit rather than on some later one.
SCOPE=(CANON.md README.md CLAUDE.md CHANGELOG.md .githooks
       skills agents rules hooks install)

# --- 1. Every path the library names exists ---------------------------------
# Paths inside the guard corpus are test inputs, not references — a case file
# names paths precisely because they must not resolve, so it is excluded by name.
#
# The pattern is anchored to directory names on purpose. Matching any path with
# an extension was tried and reverted: it reads `$HOME/.claude/settings.json`
# and `${CLAUDE_PLUGIN_ROOT}/skills/doctor/check-install.sh` as repository paths
# and reports both as dangling, which is a checker that has to be argued with
# rather than believed.
missing=""
while read -r p; do
  [ -e "$p" ] || missing="$missing $p"
done < <(grep -rhoE --exclude=cases.tsv '(skills|agents|rules|hooks|install)/[A-Za-z0-9_./-]+\.(md|sh|json|tsv)' \
           "${SCOPE[@]}" 2>/dev/null | sort -u)
if [ -z "$missing" ]; then ok "every named path resolves"
else bad "dangling paths"; for p in $missing; do note "$p"; done; fi

# --- 2. Counters match what is on disk --------------------------------------
n_skills=$(find skills -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')
n_rules=$(find rules -name '*.md' | wc -l | tr -d ' ')
n_agents=$(find agents -name '*.md' | wc -l | tr -d ' ')
n_hooks=$(jq -r '[.hooks[][].hooks[]] | length' hooks/hooks.json)
n_deny=$(jq '.permissions.deny | length' hooks/permissions.json)

# Written-out numbers are how these sentences read; digits are how they are kept.
word() { case "$1" in
  4) echo four;; 5) echo five;; 10) echo ten;; 11) echo eleven;; 12) echo twelve;;
  13) echo thirteen;;
  *) echo "$1";; esac; }

# The host's sharpen log records what each pass changed, and a logged
# before-and-after count is history rather than a claim about now — checking it
# against disk would make every change ever logged a permanent failure. Hosts
# declare that log's location in their CLAUDE.md; keep it outside the SCOPE
# directories above, or this sweep will read its history as stale claims.
#
# Do not write an example of such a count in this comment. One was written here,
# and this file was then the only place in the repository still asserting the old
# number: the checker failed on its own explanation of why not to fail on it.
check_count() { # $1 = what, $2 = expected, $3 = regex capturing the stated number
  local stated
  stated=$(grep -rhoE "$3" "${SCOPE[@]}" 2>/dev/null | grep -oE '[0-9]+|four|five|ten|eleven|twelve|thirteen' | sort -u | tr '\n' ' ')
  if [ -z "$stated" ]; then note "$1: nothing states it ($2 on disk)"; return; fi
  for s in $stated; do
    if [ "$s" != "$2" ] && [ "$s" != "$(word "$2")" ]; then
      bad "$1: text says '$s', disk says $2"; fail=1; return
    fi
  done
  ok "$1: $2, and every sentence agrees"
}
check_count "skills"     "$n_skills" '(eleven|ten|twelve|thirteen|[0-9]+) skills'
check_count "rules"      "$n_rules"  '[0-9]+ rules'
check_count "agents"     "$n_agents" '(four|five|[0-9]+) agents'
check_count "hooks"      "$n_hooks"  '(four|five|[0-9]+) hooks'
check_count "deny rules" "$n_deny"   '[0-9]+ deny rules'

# --- 3. The manifest ships every skill --------------------------------------
# A skill missing from this list does not ship, and nothing reports it.
declared=$(jq -r '.skills[]' .claude-plugin/plugin.json | sed 's|^\./||' | sort)
ondisk=$(find skills -maxdepth 1 -mindepth 1 -type d | sort)
if [ "$declared" = "$ondisk" ]; then ok "plugin manifest lists every skill"
else bad "manifest and skills/ disagree"; diff <(echo "$declared") <(echo "$ondisk") | sed 's/^/  /'; fail=1; fi

# --- 4. One version, stated in both places ----------------------------------
# The version lives in the plugin manifest, because that is what Claude Code
# reads to decide an installed plugin has an update. README restates it for a
# human. There is no package.json here: this repository is a plugin, not an npm
# package, and reading one produced a jq error and an empty half of a comparison
# that then reported a split which did not exist.
v_plugin=$(jq -r '.version' .claude-plugin/plugin.json)
v_readme=$(grep -oE 'Version [0-9]+\.[0-9]+\.[0-9]+' README.md | head -1 | awk '{print $2}')
if [ "$v_plugin" = "$v_readme" ]; then ok "version $v_plugin, consistent"
else bad "version split: plugin=$v_plugin readme=$v_readme"; fail=1; fi

# --- 5. Every rule carries what the loader reads ----------------------------
# `rules-loader.sh` emits `rule` and `evidence`; a rule missing either reaches a
# working session as a blank line. `cost:` is the loader's fallback for a host's
# own rules under .claude/rules/, which this sweep never sees — a rule shipped
# here carries `evidence:` and the check says so, rather than accepting both and
# letting an unsanitized one through.
thin=""
for f in rules/*/*.md; do
  grep -q '^rule:' "$f" && grep -q '^evidence:' "$f" || thin="$thin $f"
done
if [ -z "$thin" ]; then ok "every rule has rule/evidence"
else bad "rules missing frontmatter the loader requires"; for f in $thin; do note "$f"; done; fi

# The workshop keeps `learned:` and `origin:` — a date and a narrative naming
# what happened, to whom, in which repository. Sanitization replaces both with a
# single neutral `evidence:` line, and a rule arriving here with either field
# still on it is private residue that a promotion missed. CLAUDE.md states the
# discipline; this is the part of it a command can hold.
residue=""
for f in rules/*/*.md; do
  grep -qE '^(learned|origin):' "$f" && residue="$residue $f"
done
if [ -z "$residue" ]; then ok "no rule carries workshop provenance"
else bad "rules carrying provenance that sanitization should have stripped"; for f in $residue; do note "$f"; done; fi

# --- 6. Declared labels exist in the tracker --------------------------------
# A label nobody created returns an empty list, not an error — and an empty list
# is indistinguishable from a clean backlog. This is the failure
# rules/craft/library-skills-declare-taxonomy-rather-than-hardcode-it.md is about.
if command -v gh >/dev/null 2>&1 && gh repo view >/dev/null 2>&1; then
  have=$(gh label list --limit 100 2>/dev/null | cut -f1)
  absent=""
  for l in $(grep -oE '`(type|area|priority)/[a-z|\\]+`' CLAUDE.md | tr -d '`' \
               | awk -F/ '{n=split($2,v,/[\\|]+/); for(i=1;i<=n;i++) if(v[i]!="") print $1"/"v[i]}'); do
    case "$l" in */\*) continue ;; esac
    grep -qxF "$l" <<<"$have" || absent="$absent $l"
  done
  if [ -z "$absent" ]; then ok "declared labels exist in the tracker"
  else bad "labels declared in CLAUDE.md that the tracker does not have"; for l in $absent; do note "$l"; done; fi
else
  printf '\033[33m–\033[0m tracker not reachable; label check skipped\n'
fi

# --- 7. plugin.json doesn't redeclare an auto-discovered path ---------------
# Claude Code loads hooks/hooks.json by convention. Declaring it again in
# plugin.json's "hooks" key made every install fail with "Duplicate hooks
# file detected" — `claude plugin validate --strict` passed it anyway. Caught
# once by hand; a mechanical check on the exact shape belongs here so it
# cannot ship a second time unnoticed.
if jq -e '.hooks | strings | endswith("hooks.json")' .claude-plugin/plugin.json >/dev/null 2>&1; then
  bad "plugin.json redeclares a hooks path — Claude Code auto-discovers hooks/hooks.json; remove the key"
else
  ok "plugin.json doesn't redeclare the auto-discovered hooks path"
fi

echo
[ "$fail" -eq 0 ] && echo "claims check: clean" || echo "claims check: $fail area(s) need attention"
exit "$fail"
