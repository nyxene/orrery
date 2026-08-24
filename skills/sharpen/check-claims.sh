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

# Shows how two newline-separated lists differ, for a check that has already
# decided they do. Not `diff <(echo "$a") <(echo "$b")`: with the platform
# sandbox on, an external tool cannot open the descriptors process substitution
# hands it, so the explanation of a real failure would itself fail. The verdict
# here never depended on diff — string equality decides it — but a failure
# nobody can read is a failure nobody acts on.
show_difference() { # $1 = expected, $2 = actual
  local a b
  a="$(mktemp "${TMPDIR:-/tmp}/claims.XXXXXX")"
  b="$(mktemp "${TMPDIR:-/tmp}/claims.XXXXXX")"
  printf '%s\n' "$1" > "$a"
  printf '%s\n' "$2" > "$b"
  diff "$a" "$b" | sed 's/^/  /'
  rm -f "$a" "$b"
}

# Everything this repository holds that makes a claim about itself. `.githooks`
# is in the list because the hook names the gates it runs, and a gate whose
# files are not here is red on the first commit rather than on some later one.
SCOPE=(CANON.md README.md CLAUDE.md CHANGELOG.md .githooks
       skills agents rules hooks install)

# The same list without the changelog, for the counting pass below. A release
# note describes a past state by construction: 0.10.0's notes say seventeen
# rules and always will. Counting them as present-tense claims makes every
# future change to any counter unshippable, and the only way past it is
# rewriting the record of a release that already went out. Pass 1 still reads
# CHANGELOG.md — a path named in a release note should still resolve.
COUNT_SCOPE=()
for s in "${SCOPE[@]}"; do [ "$s" = CHANGELOG.md ] || COUNT_SCOPE+=("$s"); done

# A test file's text is fixtures, not claims. A corpus names paths precisely
# because they must not resolve, and a suite builds a tree under mktemp and then
# asserts on paths and counts inside it. Resolving either against this
# repository fails on a *passing* test, so every suite and every corpus is
# excluded from both checks below.
#
# Do not write an example of a fixture path or a fixture count in this file. The
# exclusion is by filename and this file is not excluded from itself, so the
# example becomes the only place still asserting it.
FIXTURES=(--exclude='*.test.sh' --exclude=cases.tsv --exclude=agent-cases.tsv)

# --- 1. Every path the library names exists ---------------------------------
#
# The pattern is anchored to directory names on purpose. Matching any path with
# an extension was tried and reverted: it reads `$HOME/.claude/settings.json`
# and `${CLAUDE_PLUGIN_ROOT}/skills/doctor/check-install.sh` as repository paths
# and reports both as dangling, which is a checker that has to be argued with
# rather than believed.
missing=""
while read -r p; do
  [ -e "$p" ] || missing="$missing $p"
done < <(grep -rhoE "${FIXTURES[@]}" '(skills|agents|rules|hooks|install)/[A-Za-z0-9_./-]+\.(md|sh|json|tsv)' \
           "${SCOPE[@]}" 2>/dev/null | sort -u)
if [ -z "$missing" ]; then ok "every named path resolves"
else bad "dangling paths"; for p in $missing; do note "$p"; done; fi

# --- 2. Counters match what is on disk --------------------------------------
n_skills=$(find skills -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')
n_rules=$(find rules -name '*.md' | wc -l | tr -d ' ')
n_agents=$(find agents -name '*.md' | wc -l | tr -d ' ')
# Distinct commands, not registration entries. Every sentence this is checked
# against counts hook *scripts*, and the two numbers were equal only by
# coincidence until one script was registered on a second event — the call log,
# which now records a call and its outcome. Counting entries then reports one
# more than there are files and blames the prose.
#
# `unique` on the command string, so a script registered twice collapses. Two
# registrations spelling the same path differently would not, and that is a
# limit rather than a bug: the same script under two spellings is worth a look.
n_hooks=$(jq -r '[.hooks[][].hooks[].command] | unique | length' hooks/hooks.json)
n_deny=$(jq '.permissions.deny | length' hooks/permissions.json)

# Written-out numbers are how these sentences read; digits are how they are kept.
word() { case "$1" in
  3) echo three;; 4) echo four;; 5) echo five;; 6) echo six;; 7) echo seven;;
  10) echo ten;; 11) echo eleven;;
  12) echo twelve;; 13) echo thirteen;;
  *) echo "$1";; esac; }

# The host's sharpen log records what each pass changed, and a logged
# before-and-after count is history rather than a claim about now — checking it
# against disk would make every change ever logged a permanent failure. Hosts
# declare that log's location in their CLAUDE.md; keep it outside the SCOPE
# directories above, or this sweep will read its history as stale claims.
#
# Do not write an example of such a count in this comment. One was written here,
# and this file was then the only place in the repository still asserting the old
# number: the checker failed on its own explanation of why not to fail on it. The
# same holds for a count spelled out beside its noun anywhere else in this file.
#
# Both greps are case-insensitive, and neither was until a count sentence on this
# repository's own front page turned out to be capitalised at the head of a list
# item — where no case-sensitive match could ever see it. The lower-case
# sentences were kept current, this check printed a tick, and the stale one was
# the first thing a reader saw. The extraction is lowered rather than matched
# twice, because the comparison below is against the lower-case word form.
check_count() { # $1 = what, $2 = expected, $3 = regex capturing the stated number
  local stated
  stated=$(grep -rhoiE "${FIXTURES[@]}" "$3" "${COUNT_SCOPE[@]}" 2>/dev/null \
             | grep -oiE '[0-9]+|three|four|five|six|seven|ten|eleven|twelve|thirteen' \
             | tr 'A-Z' 'a-z' | sort -u | tr '\n' ' ')
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
check_count "agents"     "$n_agents" '(three|four|five|[0-9]+) agents'
check_count "hooks"      "$n_hooks"  '(four|five|six|seven|[0-9]+) hooks'
check_count "deny rules" "$n_deny"   '[0-9]+ deny rules'

# --- 3. The manifest ships every skill --------------------------------------
# A skill missing from this list does not ship, and nothing reports it.
declared=$(jq -r '.skills[]' .claude-plugin/plugin.json | sed 's|^\./||' | sort)
ondisk=$(find skills -maxdepth 1 -mindepth 1 -type d | sort)
if [ "$declared" = "$ondisk" ]; then ok "plugin manifest lists every skill"
else bad "manifest and skills/ disagree"; show_difference "$declared" "$ondisk"; fail=1; fi

# --- 4. One version, stated in both places ----------------------------------
# The version lives in the plugin manifest, because that is what Claude Code
# reads to decide an installed plugin has an update. README restates it for a
# human. There is no package.json here: this repository is a plugin, not an npm
# package, and reading one produced a jq error and an empty half of a comparison
# that then reported a split which did not exist.
#
# Every version-shaped string in the README, not the first one. This read only
# the prose form, `Version 0.10.9`, which matched the sentence in the footer and
# stopped — while the shields.io badge at the top, written `version-0.10.7`, sat
# two releases behind and was never looked at. A checker that reads one of the
# two places a fact is written certifies that the other one is wrong.
v_plugin=$(jq -r '.version' .claude-plugin/plugin.json)
stated=$(grep -ohE '(Version |version-)[0-9]+\.[0-9]+\.[0-9]+' README.md \
           | sed -E 's/^(Version |version-)//' | sort -u)
if [ -z "$stated" ]; then
  note "version: README states none ($v_plugin in plugin.json)"
elif [ "$stated" = "$v_plugin" ]; then
  ok "version $v_plugin, and every place the README states it agrees"
else
  bad "version split: plugin.json=$v_plugin, README states: $(tr '\n' ' ' <<<"$stated")"
  fail=1
fi

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
#
# The probe is the payload. A guard verb in front of the call that matters can
# fail for reasons the real call would not have, and then the check announces
# the tracker is unreachable when it is not. Nothing is sent to /dev/null
# either: whichever of "no gh", "no token" or "the network is down" happened,
# the line a person reads should carry what gh actually said.
if ! command -v gh >/dev/null 2>&1; then
  printf '\033[33m–\033[0m label check skipped: gh is not on PATH\n'
elif ! gh_out=$(gh label list --limit 100 2>&1); then
  printf '\033[33m–\033[0m label check skipped: gh could not list labels\n'
  printf '%s\n' "$gh_out" | sed 's/^/    /'
else
  have=$(cut -f1 <<<"$gh_out")
  absent=""
  for l in $(grep -oE '`(type|area|priority)/[a-z|\\]+`' CLAUDE.md | tr -d '`' \
               | awk -F/ '{n=split($2,v,/[\\|]+/); for(i=1;i<=n;i++) if(v[i]!="") print $1"/"v[i]}'); do
    case "$l" in */\*) continue ;; esac
    grep -qxF "$l" <<<"$have" || absent="$absent $l"
  done
  if [ -z "$absent" ]; then ok "declared labels exist in the tracker"
  else bad "labels declared in CLAUDE.md that the tracker does not have"; for l in $absent; do note "$l"; done; fi
fi

# --- 7. plugin.json doesn't redeclare an auto-discovered path ---------------
# Claude Code loads hooks/hooks.json by convention. Declaring it again in
# plugin.json's "hooks" key made every install fail with "Duplicate hooks
# file detected" — `claude plugin validate --strict` passed it anyway. Caught
# once by hand; a mechanical check on the exact shape belongs here so it
# cannot ship a second time unnoticed.
#
# `bad` prints and `note` is what moves the counter, so this branch reported the
# defect and exited 0 for as long as it existed — a red line in a run that
# passed. Evidence: a mutation suite over the equivalent check.
if jq -e '.hooks | strings | endswith("hooks.json")' .claude-plugin/plugin.json >/dev/null 2>&1; then
  bad "plugin.json redeclares a hooks path — Claude Code auto-discovers hooks/hooks.json; remove the key"
  fail=1
else
  ok "plugin.json doesn't redeclare the auto-discovered hooks path"
fi

# --- 8. A case that defers to a deny rule names one that exists -------------
# The Bash guard does not refuse the plain destructive git verbs, because the
# deny list carries them — so each of those verbs is refused in exactly one
# place. The corpus records which rule took over, beside the `allow` it
# justifies, as a comment. Drop that rule from `hooks/permissions.json` and the
# verb stops being refused anywhere, with the corpus still green and still
# asserting that letting it through is correct.
#
# This says nothing about whether the rule is right — only that the thing the
# corpus points at is still there. A rule contains spaces, so misses are
# collected one per line and read back with field splitting off.
absent=""
while IFS= read -r rule; do
  [ -n "$rule" ] || continue
  jq -e --arg r "$rule" '.permissions.deny | index($r)' hooks/permissions.json >/dev/null 2>&1 \
    || absent="$absent$rule"$'\n'
done < <(grep -oE '#[[:space:]]*Bash\([^)]*\)' hooks/cases.tsv | sed 's/^#[[:space:]]*//' | sort -u)
if [ -z "$absent" ]; then ok "every deny rule the corpus defers to still exists"
else
  bad "the corpus defers to deny rules that are not in permissions.json"
  while IFS= read -r r; do [ -n "$r" ] && note "$r"; done <<<"$absent"
fi

# --- 9. A hook exists, is registered, and its suite is run ------------------
# A script sitting in `hooks/` that `hooks/hooks.json` never names is a hook
# that was written, tested and shipped without ever firing — indistinguishable
# from one that works. Three arms, because that silence arrives from three
# directions: a script nothing registers, a suite no gate runs, and a
# registration whose path resolves to nothing. The last one is what catches an
# assembly that omitted a file the manifest still points at.
#
# `guard-test-lib.sh` is excluded by name: the guard suites source it and
# Claude Code never runs it, so it is a library that happens to live in `hooks/`.
#
# The first token of a command, not the whole string — a registration may carry
# arguments, and reading one as part of the path invents two defects at once: a
# script nothing registers, and a registration with no script.
#
# Every arm reports through `note`, which is what moves the counter; `bad` only
# prints. Check 7 above is what forgetting that costs.
cmds=$(jq -r '[.hooks[][].hooks[].command] | .[]' hooks/hooks.json | awk '{print $1}' | tr -d '"')
scripts=$(ls hooks/*.sh | sed 's#hooks/##' | grep -v '\.test\.sh$' | grep -v '^guard-test-lib\.sh$' | sort)
registered=$(printf '%s\n' "$cmds" | sed 's#.*/hooks/##' | sort -u)
if [ "$scripts" = "$registered" ]; then ok "every hook script is registered in hooks.json"
else bad "hooks/ and hooks.json name different scripts"
     note "on disk:    $(printf '%s' "$scripts" | tr '\n' ' ')"
     note "registered: $(printf '%s' "$registered" | tr '\n' ' ')"; fi

unrun=""
for f in hooks/*.test.sh; do
  grep -qF "$f" .githooks/pre-commit || unrun="$unrun $f"
done
if [ -z "$unrun" ]; then ok "every hook suite is run by the pre-commit gate"
else bad "hook suites that no gate runs"; for f in $unrun; do note "$f"; done; fi

dangling=""
while IFS= read -r p; do
  [ -f "$p" ] || dangling="$dangling $p"
done < <(printf '%s\n' "$cmds" | sed 's#[$]{CLAUDE_PLUGIN_ROOT}#.#' | sort -u)
if [ -z "$dangling" ]; then ok "every registered hook command resolves to a file"
else bad "hooks.json registers commands with no script behind them"
     for p in $dangling; do note "$p"; done; fi

# --- 10. Every frontmatter block is YAML somebody else can read -------------
# `description` decides whether a skill or an agent fires, and the block it
# sits in is YAML. Claude Code reads that line by splitting on its first colon
# rather than parsing it, so a description a strict parser refuses installs
# and displays perfectly, and breaks only in whatever else reads the tree.
#
# One pattern rather than a parser: a plain scalar may not carry a colon
# followed by a space, and that is the rule a prose description trips over.
unparseable=""
for f in skills/*/SKILL.md agents/*.md rules/*/*.md; do
  [ -f "$f" ] || continue
  keys=$(awk 'NR==1 && $0!="---" { exit } NR>1 && $0=="---" { exit }
              NR>1 && match($0, /^[A-Za-z_-]+: /) {
                v=substr($0,RLENGTH+1)
                if (v !~ /^["'"'"'[{]/ && v ~ /: /) print substr($0,1,RLENGTH-2)
              }' "$f")
  [ -n "$keys" ] && unparseable="$unparseable $f:$(printf '%s' "$keys" | tr '\n' ',')"
done
if [ -z "$unparseable" ]; then ok "every skill, agent and rule frontmatter parses as YAML"
else bad "frontmatter carries an unquoted value containing a colon and a space"
     for f in $unparseable; do note "$f"; done; fi

echo
[ "$fail" -eq 0 ] && echo "claims check: clean" || echo "claims check: $fail area(s) need attention"
exit "$fail"
