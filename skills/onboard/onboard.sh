#!/usr/bin/env bash
# The one thing `onboard` writes with. A session drafts; a person runs this from a
# terminal, because what it writes — the settings that switch gates, the deny list —
# a session is denied, and should be.
#
#   onboard.sh check    <project>                    writes nothing in the project (it fetches origin): what is there, what the next verb does
#   onboard.sh prepare  <project> --config <file> --mode committed|local [--label <l>] [--pr-gate]
#   onboard.sh update   <project> [--records-ok]     the plugin, once the settings are in force
#   onboard.sh rollback <project>                    the install record `update` saved
#
# `prepare --mode committed` opens an issue and a pull request carrying
# `.orrery/config.json`, the deny list merged into `.claude/settings.json`, a dead
# `orrery-method` entry removed, and with `--pr-gate` the PR-names-an-issue
# workflow. It works in a worktree of its own, so the project's checkout and any
# work in it are not touched. Run again once the settings are on the default
# branch, it leaves them as reviewed and only brings the deny list up to date —
# what an update that adds a rule asks for; a run that would change nothing opens
# nothing. `--mode local` writes `.orrery/local/config.json` and
# merges the deny list into `.claude/settings.local.json` — this machine only, no
# pull request.
#
# `update` is ordered after `prepare` on purpose. Since 0.32 the gate refuses a pull
# request whose work committed no record; a project whose agents open pull requests
# without one would be stopped by the update, so it refuses while the default
# branch's recent merges carry none, until `--records-ok` says that is understood.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$here/../.." && pwd -P)}"
# shellcheck source=hooks/orrery-config.sh
. "$root/hooks/orrery-config.sh"

die() { printf 'onboard: %s\n' "$1" >&2; exit 1; }
usage() { sed -n '6,9p' "$0" | sed 's/^# //' >&2; exit 2; }

verb="${1:-}"; target="${2:-}"
[ -n "$verb" ] && [ -n "$target" ] || usage
shift 2
config="" mode="" label="" prgate=0 recordsok=0
while [ $# -gt 0 ]; do
  case "$1" in
    --config) config="${2:-}"; shift 2 ;;
    --mode) mode="${2:-}"; shift 2 ;;
    --label) label="${2:-}"; shift 2 ;;
    --pr-gate) prgate=1; shift ;;
    --records-ok) recordsok=1; shift ;;
    *) usage ;;
  esac
done

main="$(orrery_main "$target")"
[ -n "$main" ] || die "$target is not a git repository"
plugins="${ORRERY_INSTALLED_PLUGINS:-$HOME/.claude/plugins/installed_plugins.json}"
saved="$main/.orrery/local/onboard/install-record.json"
deny="$root/hooks/permissions.json"
git -C "$main" fetch -q origin 2>/dev/null || true
base="$(git -C "$main" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || echo main)"

entry() { jq -c --arg p "$main" '[.plugins["orrery@orrery"][]? | select(.projectPath == $p)] | .[0] // empty' "$plugins" 2>/dev/null || true; }
committed() { git -C "$main" cat-file -e "$base:.orrery/config.json" 2>/dev/null; }
in_force() { committed || [ -f "$main/.orrery/local/config.json" ]; }
# Merges into the settings file $1, creating it, keeping every other key and the
# order of the rules already there; a rule already present is not added twice.
merge_deny() {
  [ -s "$1" ] || { mkdir -p "$(dirname "$1")"; printf '{}\n' > "$1"; }
  jq --indent 2 --slurpfile s "$deny" '
      .permissions.deny = reduce $s[0].permissions.deny[] as $r ((.permissions.deny // []);
        if index([$r]) then . else . + [$r] end)
    | if has("enabledPlugins") then .enabledPlugins |= del(.["orrery-method@orrery-method"]) else . end
    | if has("extraKnownMarketplaces") then .extraKnownMarketplaces |= del(.["orrery-method"]) else . end
  ' "$1" > "$1.new" && mv "$1.new" "$1"
}
# Merged recently with no record: the last ten changes on the default branch, and
# none of them brought one — the case the gate would turn into a refusal. Each of
# the ten is asked what it changed, as doctor asks: `git log -10 -- <path>` would
# answer with the last ten that ever touched a record, however old.
unrecorded() {
  local c any=0
  for c in $(git -C "$main" rev-list --first-parent -10 "$base" 2>/dev/null); do
    any=1
    git -C "$main" diff-tree --root --no-commit-id --name-only -r -m --first-parent "$c" 2>/dev/null \
      | grep -qE '^\.orrery/work/[^/]+/retrospective\.md$' && return 1
  done
  [ "$any" = 1 ]
}
has_pr_gate() { grep -rlqE 'names-an-issue|pull_request\.body' "$main/.github/workflows" 2>/dev/null; }

case "$verb" in
check)
  e="$(entry)"
  echo "project:      $main (default branch $base)"
  echo "installed:    $([ -n "$e" ] && jq -r '"\(.version), \(.scope) scope"' <<<"$e" || echo 'not for this project')"
  if committed; then echo "settings:     .orrery/config.json on $base"
  elif [ -f "$main/.orrery/local/config.json" ]; then echo "settings:     .orrery/local/config.json (this machine)"
  else echo "settings:     none in force -> prepare"; fi
  # Only the files that exist: jq exits 2 on a missing one, and under `set -e` that
  # ended `check` here, silently, in the usual project with no settings.local.json.
  have="$(for f in "$main/.claude/settings.json" "$main/.claude/settings.local.json"; do
            [ ! -f "$f" ] || jq -r '.permissions.deny[]?' "$f" 2>/dev/null || true; done | sort -u)"
  echo "deny rules:   $(jq -r '.permissions.deny[]' "$deny" | sort -u | comm -23 - <(printf '%s\n' "$have") | grep -c . || true) missing"
  echo "pr gate:      $(has_pr_gate && echo present || echo none)"
  echo "records:      $(unrecorded && echo 'recent merges carry none -> update refuses without --records-ok' || echo ok)"
  ;;
prepare)
  valid() { [ -r "$config" ] && jq -e -s 'length == 1 and (.[0] | type) == "object"' "$config" >/dev/null 2>&1; }
  case "$mode" in
  local)
    valid || die "--config must name one JSON object"
    d="$(orrery_local_ensure "$main")" || die "cannot create $main/.orrery/local"
    cp "$config" "$d/config.json"
    merge_deny "$main/.claude/settings.local.json"
    echo "written: $d/config.json and the deny list in .claude/settings.local.json — this machine only"
    ;;
  committed)
    # Where the default branch already carries the settings, they stay as reviewed
    # and only the deny list is brought up to date — the step every update that
    # adds a rule asks for. The change is built before the issue is opened, so a
    # run that changes nothing opens nothing; and whatever fails, the worktree and
    # the draft branch go with the exit.
    if committed; then what="Orrery's deny list brought up to date"
    else valid || die "--config must name one JSON object"; what="Orrery settings in .orrery/config.json"; fi
    wt="$(mktemp -d "${TMPDIR:-/tmp}/onboard.XXXXXX")"; draft="onboard-draft-$$"
    trap 'git -C "$main" worktree remove --force "$wt" 2>/dev/null; rm -rf "$wt"; git -C "$main" branch -D "$draft" >/dev/null 2>&1' EXIT
    git -C "$main" worktree add -q -b "$draft" "$wt" "$base"
    committed || { mkdir -p "$wt/.orrery"; cp "$config" "$wt/.orrery/config.json"; }
    merge_deny "$wt/.claude/settings.json"
    if [ "$prgate" = 1 ] && [ "$(jq -r '.tracker // empty' "$wt/.orrery/config.json")" = github ] && ! has_pr_gate; then
      mkdir -p "$wt/.github/workflows" "$wt/install/ci"
      cp "$root/install/ci/pr-names-an-issue.yml" "$wt/.github/workflows/"
      cp "$root/install/ci/names-an-issue.sh" "$root/install/ci/names-an-issue.test.sh" "$wt/install/ci/"
    fi
    git -C "$wt" add -A
    if git -C "$wt" diff --cached --quiet; then echo "nothing to change: $what is already so on $base"; exit 0; fi
    repo="$(cd "$main" && gh repo view --json nameWithOwner -q .nameWithOwner)"
    url="$(gh issue create --repo "$repo" ${label:+--label "$label"} --title "chore: $what" \
      --body "Brings this project's Orrery settings into the repository: \`.orrery/config.json\` where it is missing, Orrery's deny list merged into \`.claude/settings.json\`, and a dead \`orrery-method\` plugin entry removed if there is one.")"
    n="${url##*/}"; branch="chore/$n-orrery-settings"
    git -C "$wt" branch -m "$draft" "$branch"
    git -C "$wt" commit -q -m "chore: $what (#$n)"
    git -C "$wt" push -q -u origin "$branch"
    (cd "$wt" && gh pr create --base "${base#origin/}" --head "$branch" --title "chore: $what" --body "Closes #$n")
    ;;
  *) die "--mode is committed or local" ;;
  esac
  ;;
update)
  in_force || die "no settings in force yet — run prepare, and merge its pull request"
  if unrecorded && [ "$recordsok" = 0 ]; then
    die "the last changes on $base carry no .orrery/work/*/retrospective.md. The updated gate refuses such a pull request, so this project's agents would be stopped. Add --records-ok once that is understood."
  fi
  e="$(entry)"; [ -n "$e" ] || die "orrery is not installed for $main"
  mkdir -p "$(dirname "$saved")"; [ -f "$saved" ] || printf '%s\n' "$e" > "$saved"
  (cd "$main" && claude plugin marketplace update orrery && claude plugin update orrery@orrery --scope "$(jq -r .scope <<<"$e")")
  echo "updated; the record before it is in $saved. Restart this project's sessions, then run /orrery:doctor."
  ;;
rollback)
  [ -f "$saved" ] || die "no saved install record for $main"
  old="$(cat "$saved")"
  # The record is written back into the plugin registry, so its path has to be
  # the plugin cache's, beside that registry: a record naming anywhere else would
  # install that.
  # Both resolved first, so `cache/../../x` is judged by where it lands.
  [ -d "$(jq -r .installPath <<<"$old")" ] || die "the saved version's files are no longer in the plugin cache"
  case "$(cd "$(jq -r .installPath <<<"$old")" && pwd -P)" in
    "$(cd "$(dirname "$plugins")/cache" 2>/dev/null && pwd -P)/"*) ;;
    *) die "the saved record names a path outside the plugin cache — not restoring it" ;;
  esac
  jq --indent 2 --arg p "$main" --argjson o "$old" \
    '.plugins["orrery@orrery"] |= map(if .projectPath == $p then $o else . end)' "$plugins" > "$plugins.new" \
    && mv "$plugins.new" "$plugins"
  echo "back on $(jq -r .version <<<"$old"). Restart this project's sessions."
  ;;
*) usage ;;
esac
