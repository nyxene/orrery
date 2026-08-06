#!/usr/bin/env bash
# Diagnoses one host project's orrery plugin install: loaded, current, and not
# double-wired against global scope.
#
# `claude plugin validate --strict` can pass a manifest that still fails to
# load; the only reliable signal is `claude plugin list` inside the host
# project. This script runs that check (and the others below) on a schedule
# instead of by memory, so a stale install (edited source, un-updated cache)
# shows up before it causes a session that behaves like an old version.
#
# Notes on the checks: `claude plugin list --json` carries no status/error
# field, so only the plain-text form reports a load failure — this script
# reads both. Paths are canonicalized so matching survives symlinks; freshness
# compares git SHAs, not version strings, so a source change without a version
# bump still registers; and the log lives outside the plugin cache, which is
# version-pinned and replaced on every update.
#
# Usage: check-install.sh [project-dir]   (default: $CLAUDE_PROJECT_DIR or cwd)
set -uo pipefail

PROJECT="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"
PROJECT="$(cd "$PROJECT" 2>/dev/null && pwd -P || echo "$PROJECT")"
fail=0
ok()   { printf '\033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '\033[31m✗\033[0m %s\n' "$1"; fail=$((fail + 1)); }
warn() { printf '\033[33m–\033[0m %s\n' "$1"; }

declare -a ROW_NAME=() ROW_RESULT=()
row() { ROW_NAME+=("$1"); ROW_RESULT+=("$2"); }

echo "orrery doctor — $PROJECT"
echo

# --- 0. the tools this script itself needs -----------------------------------
have_jq=1; have_claude=1
command -v jq >/dev/null 2>&1     || have_jq=0
command -v claude >/dev/null 2>&1 || have_claude=0

if [ "$have_jq" -eq 1 ]; then ok "jq on PATH"; row "jq" "ok"
else bad "jq missing — loaders announce failure, guards fail closed (deny everything)"; row "jq" "missing"; fi

if [ "$have_claude" -eq 1 ]; then ok "claude CLI on PATH"; row "claude CLI" "ok"
else
  warn "claude CLI not on PATH — cannot check install/enablement state this way"
  warn "common under cron: cron's PATH usually lacks nvm/homebrew shims — use an absolute path or a login shell"
  row "claude CLI" "missing"
fi

if [ "$have_jq" -eq 0 ]; then
  echo; echo "doctor: cannot proceed without jq"
  row "install found" "n/a"; row "enabled on branch" "n/a"; row "global conflict" "n/a"
  row "cache fresh" "n/a"; row "manifest shape" "n/a"
  fail=1
fi

# --- 1. what claude plugin list actually says for this project --------------
# --json has no status/error field (confirmed empirically) — only the plain
# text form carries "Status: failed to load" and the reason, so both are read.
proj_entry="" user_entry="" plain_block=""
if [ "$have_jq" -eq 1 ] && [ "$have_claude" -eq 1 ]; then
  # A project-scope plugin's "enabled" state is contextual to the invoking
  # cwd, not just to a path argument — running from elsewhere with $PROJECT
  # only as data reported a false "disabled" here during testing. Run inside
  # the target project so the CLI sees the right context.
  json=$(cd "$PROJECT" 2>/dev/null && claude plugin list --json 2>/dev/null)
  proj_entry=$(echo "$json" | jq -c --arg p "$PROJECT" '[.[] | select(.id=="orrery@orrery" and .scope=="project" and .projectPath==$p)] | .[0] // empty')
  user_entry=$(echo "$json" | jq -c '[.[] | select(.id=="orrery@orrery" and .scope=="user")] | .[0] // empty')
  plain_block=$(cd "$PROJECT" 2>/dev/null && claude plugin list 2>/dev/null | awk '/orrery@orrery/{f=1} f{print} f && /^[[:space:]]*$/ && NR>1{if(seen)exit; seen=1}')

  if [ -n "$proj_entry" ] && [ -n "$user_entry" ]; then
    warn "both a project-scope and a user-scope orrery install exist — using project-scope for freshness checks below; this combination is itself the double-fire risk check 3 looks for"
  fi
  entry="${proj_entry:-$user_entry}"

  if [ -z "$entry" ]; then
    bad "no orrery install found for this project (claude plugin list --json)"
    row "install found" "no"
    row "load status" "n/a (no install for this project)"
  else
    cached_ver=$(echo "$entry" | jq -r '.version')
    install_path=$(echo "$entry" | jq -r '.installPath')
    scope=$(echo "$entry" | jq -r '.scope')
    ok "found: $cached_ver, scope=$scope"
    row "install found" "$cached_ver ($scope)"

    # claude plugin list --json carries no gitCommitSha — only the raw state
    # file does. Matched by installPath: unique per plugin+marketplace+version.
    installed_json="$HOME/.claude/plugins/installed_plugins.json"
    if [ -f "$installed_json" ]; then
      cached_sha=$(jq -r --arg ip "$install_path" \
        '.plugins["orrery@orrery"][]? | select(.installPath==$ip) | .gitCommitSha // empty' \
        "$installed_json" 2>/dev/null)
    fi

    # Plain text carries no projectPath, so its status line can only be
    # trusted once --json has confirmed an install for THIS project exists.
    # If orrery is also project-scope-installed in an unrelated project, the
    # first "orrery@orrery" block in the text may belong to that one instead —
    # a real gap, noted in SKILL.md rather than silently assumed away.
    status_line=$(echo "$plain_block" | grep -m1 'Status:')
    error_line=$(echo "$plain_block" | grep -m1 'Error:')
    case "$status_line" in
      *"failed to load"*)
        bad "claude plugin list reports: failed to load"
        [ -n "$error_line" ] && bad "  $(echo "$error_line" | sed 's/^ *//')"
        row "load status" "failed to load"
        ;;
      *"enabled"*) ok "claude plugin list reports: enabled"; row "load status" "enabled" ;;
      *"disabled"*) bad "claude plugin list reports: disabled"; row "load status" "disabled" ;;
      *) warn "no status line found for orrery@orrery in claude plugin list"; row "load status" "unknown" ;;
    esac
  fi
elif [ "$have_jq" -eq 1 ]; then
  row "install found" "n/a (no claude CLI)"; row "load status" "n/a (no claude CLI)"
fi

# --- 2. enabled on the branch actually checked out ---------------------------
if [ "$have_jq" -eq 1 ]; then
  if [ -f "$PROJECT/.claude/settings.json" ]; then
    proj_scope_enabled=$(jq -r '.enabledPlugins["orrery@orrery"] // false' "$PROJECT/.claude/settings.json" 2>/dev/null)
    branch=$(git -C "$PROJECT" branch --show-current 2>/dev/null)
    branch="${branch:-detached/no-git}"
    if [ "$proj_scope_enabled" = "true" ]; then
      ok "enabledPlugins true on checked-out branch '$branch'"
      row "enabled on branch" "yes ($branch)"
    else
      bad "enabledPlugins missing/false on branch '$branch' — this branch may predate the install commit"
      row "enabled on branch" "no ($branch)"
    fi
  else
    warn "$PROJECT/.claude/settings.json not found"
    row "enabled on branch" "n/a"
  fi
fi

# --- 3. global scope isn't double-enabling on top of this project's scope ---
if [ "$have_jq" -eq 1 ]; then
  global_enabled=$(jq -r '.enabledPlugins["orrery@orrery"] // false' "$HOME/.claude/settings.json" 2>/dev/null)
  if [ "$global_enabled" = "true" ] && [ "${proj_scope_enabled:-false}" = "true" ]; then
    bad "orrery is enabled both globally (user scope) and for this project — every hook fires twice"
    row "global conflict" "yes — double-enabled"
  elif [ "$global_enabled" = "true" ]; then
    ok "orrery enabled at user scope globally; no project-scope entry to conflict with"
    row "global conflict" "user-scope only"
  else
    ok "no global enablement of orrery"
    row "global conflict" "none"
  fi
fi

# --- 4. cache is current with the marketplace source -------------------------
# Two marketplace source shapes: a local "directory" (read its plugin.json and
# git HEAD directly) or a "github" repo (no local clone to read — ask the
# remote for its HEAD sha via ls-remote, no full clone needed).
if [ "$have_jq" -eq 1 ]; then
  src_kind=$(jq -r '.extraKnownMarketplaces.orrery.source.source // empty' "$PROJECT/.claude/settings.json" 2>/dev/null)
  live_sha=""
  case "$src_kind" in
    directory)
      src_path=$(jq -r '.extraKnownMarketplaces.orrery.source.path // empty' "$PROJECT/.claude/settings.json" 2>/dev/null)
      if [ -n "$src_path" ] && [ -f "$src_path/.claude-plugin/plugin.json" ]; then
        live_ver=$(jq -r '.version' "$src_path/.claude-plugin/plugin.json" 2>/dev/null)
        live_sha=$(git -C "$src_path" rev-parse HEAD 2>/dev/null)
      else
        warn "source directory not resolvable ($src_path) — skipping drift check"
      fi
      ;;
    github)
      src_repo=$(jq -r '.extraKnownMarketplaces.orrery.source.repo // empty' "$PROJECT/.claude/settings.json" 2>/dev/null)
      if [ -n "$src_repo" ]; then
        live_sha=$(git ls-remote "https://github.com/$src_repo.git" HEAD 2>/dev/null | cut -f1)
        [ -z "$live_sha" ] && warn "couldn't reach https://github.com/$src_repo.git — skipping drift check (offline?)"
      else
        warn "no repo recorded for the github-sourced marketplace — skipping drift check"
      fi
      ;;
    *)
      warn "unrecognized or missing marketplace source kind ('$src_kind') — skipping drift check"
      ;;
  esac

  if [ -n "$live_sha" ]; then
    if [ -n "$cached_sha" ]; then
      if [ "$cached_sha" = "$live_sha" ]; then
        ok "cache (${cached_ver:-?} @ ${cached_sha:0:7}) matches source HEAD"
        row "cache fresh" "yes"
      else
        bad "cache is stale: cached @${cached_sha:0:7} (${cached_ver:-?}), source is @${live_sha:0:7}${live_ver:+ ($live_ver)} — a SHA mismatch catches source changes even without a version bump"
        row "cache fresh" "no (SHA mismatch)"
      fi
    elif [ -n "${cached_ver:-}" ] && [ -n "${live_ver:-}" ]; then
      if [ "$cached_ver" = "$live_ver" ]; then
        ok "cache ($cached_ver) matches source version (no SHA recorded to compare more precisely)"
        row "cache fresh" "yes (version only)"
      else
        bad "cache is stale: cached=$cached_ver, source=$live_ver — run: claude plugin update orrery@orrery --scope ${scope:-project}, then restart the session"
        row "cache fresh" "no ($cached_ver vs $live_ver)"
      fi
    else
      warn "no cached entry to compare against the source"
      row "cache fresh" "n/a"
    fi
  else
    row "cache fresh" "n/a"
  fi
fi

# --- 5. the loaded cache isn't the buggy manifest shape ----------------------
if [ "$have_jq" -eq 1 ]; then
  if [ -n "${install_path:-}" ] && [ -f "$install_path/.claude-plugin/plugin.json" ]; then
    if jq -e '.hooks | strings | endswith("hooks.json")' "$install_path/.claude-plugin/plugin.json" >/dev/null 2>&1; then
      bad "loaded cache's plugin.json redeclares a hooks path — fails with 'Duplicate hooks file' if it matches the auto-discovered hooks/hooks.json"
      row "manifest shape" "buggy"
    else
      ok "loaded cache's plugin.json doesn't redeclare a hooks path"
      row "manifest shape" "clean"
    fi
  else
    warn "no installed cache path to check for the manifest bug"
    row "manifest shape" "n/a"
  fi
fi

echo
if [ "$fail" -eq 0 ]; then echo "doctor: clean"; else echo "doctor: $fail area(s) need attention"; fi

# --- append a compact row to the per-project log for trend-analysis ---------
# Lives under the user's home directory, not next to this script: installed as
# a plugin, this script runs from inside a version-pinned cache directory that
# gets replaced on every update, which would silently reset the history.
LOG_DIR="$HOME/.claude/orrery-doctor-log"
mkdir -p "$LOG_DIR" 2>/dev/null
slug=$(echo "$PROJECT" | sed 's#^/##; s#[/ ]#-#g')
LOG="$LOG_DIR/$slug.md"
[ -f "$LOG" ] || printf '# orrery doctor log — %s\n\nOldest run at top, newest at the bottom — check the tail for the latest.\n\n---\n' "$PROJECT" > "$LOG"
{
  echo
  echo "## $(date -u +%Y-%m-%dT%H:%M:%SZ) — $([ "$fail" -eq 0 ] && echo clean || echo "$fail flagged")"
  echo
  echo "| Check | Result |"
  echo "|---|---|"
  for i in "${!ROW_NAME[@]}"; do
    echo "| ${ROW_NAME[$i]} | ${ROW_RESULT[$i]} |"
  done
} >> "$LOG"
echo "(log: $LOG)"

exit "$fail"
