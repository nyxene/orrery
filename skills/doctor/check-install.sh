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
# reads both. (It does carry `enabled`, a two-state boolean, which is what
# decides enabled vs. disabled; "failed to load" is the third state it cannot
# express.) Paths are canonicalized so matching survives symlinks; freshness
# compares git SHAs, not version strings, so a source change without a version
# bump still registers; and the log lives outside the plugin cache, which is
# version-pinned and replaced on every update.
#
# Check 7 hands the deny-list comparison to hooks/permissions-check.sh rather
# than repeating it, and one limit follows: `--report` compares the rules of the
# copy that is running, not the rules of whatever version the inspected project
# has cached. Run as the plugin — the normal case — those are the same thing.
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

# Per-project state: the run log at the bottom, and the cache baseline check 6
# compares against. Both live under your home directory rather than beside this
# script, which runs from inside a version-pinned cache directory that is
# replaced on every update — state kept there would reset silently.
#
# `~/.claude/orrery/` is one directory for everything orrery keeps on a
# machine, with a per-purpose level under it.
STATE_DIR="$HOME/.claude/orrery"
LOG_DIR="$STATE_DIR/doctor"
slug=$(echo "$PROJECT" | sed 's#^/##; s#[/ ]#-#g')
LOG="$LOG_DIR/$slug.md"
DIGEST_FILE="$LOG_DIR/$slug.cache-digest"

# One-time move from the previous `orrery-doctor-log/`. The run history would
# only be orphaned, but a missing cache baseline is worse than untidy: check 6
# would re-record silently and report the next run as its first, which is the
# same state an edited install produces.
OLD_LOG_DIR="$HOME/.claude/orrery-doctor-log"
if [ -d "$OLD_LOG_DIR" ] && [ ! -d "$LOG_DIR" ]; then
  mkdir -p "$STATE_DIR" 2>/dev/null && mv "$OLD_LOG_DIR" "$LOG_DIR" 2>/dev/null \
    && warn "moved previous state from $OLD_LOG_DIR to $LOG_DIR"
fi

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
# --json carries `enabled`, a two-state boolean, and no `status` and no `error`
# key in any entry shape — measured, not read off the documentation. There are
# two shapes: a user-scope entry has no `projectPath`, which is why the
# selection below matches on it only for the scopes that carry it. Re-run
# `claude plugin list --json | jq -c '[.[]|keys]|unique'` rather than trusting
# this sentence, since the CLI may add a field. So `enabled` decides
# enabled vs. disabled, and only the plain-text form can report "failed to
# load" and the reason behind it — a third state a boolean cannot express.
# Both are read, for different questions.
proj_entry="" local_entry="" user_entry="" plain_block="" plain_all=""
if [ "$have_jq" -eq 1 ] && [ "$have_claude" -eq 1 ]; then
  # A project-scope plugin's "enabled" state is contextual to the invoking
  # cwd, not just to a path argument — running from elsewhere with $PROJECT
  # only as data reported a false "disabled" here during testing. Run inside
  # the target project so the CLI sees the right context.
  json=$(cd "$PROJECT" 2>/dev/null && claude plugin list --json 2>/dev/null)
  proj_entry=$(echo "$json" | jq -c --arg p "$PROJECT" '[.[] | select(.id=="orrery@orrery" and .scope=="project" and .projectPath==$p)] | .[0] // empty')
  # `local` scope is the install a project gets when its enablement is written
  # to the untracked .claude/settings.local.json — which is what a repository
  # whose index other people read does, to keep the owner's configuration out
  # of it. Public or private is not the condition and never was: a private
  # repository with collaborators has the same reason. This scope was invisible
  # to the check below until it was fixed, and while it was, a correctly
  # installed, enabled, demonstrably running plugin reported as
  # "no orrery install found".
  local_entry=$(echo "$json" | jq -c --arg p "$PROJECT" '[.[] | select(.id=="orrery@orrery" and .scope=="local" and .projectPath==$p)] | .[0] // empty')
  user_entry=$(echo "$json" | jq -c '[.[] | select(.id=="orrery@orrery" and .scope=="user")] | .[0] // empty')
  plain_all=$(cd "$PROJECT" 2>/dev/null && claude plugin list 2>/dev/null)
  plain_block=$(printf '%s\n' "$plain_all" | awk '/orrery@orrery/{f=1} f{print} f && /^[[:space:]]*$/ && NR>1{if(seen)exit; seen=1}')

  if [ -n "$proj_entry" ] && [ -n "$user_entry" ]; then
    warn "both a project-scope and a user-scope orrery install exist — using project-scope for freshness checks below; this combination is itself the double-fire risk check 3 looks for"
  fi
  entry="${proj_entry:-${local_entry:-$user_entry}}"

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
    # file does. Matched by installPath, which is keyed by
    # plugin+marketplace+version and so shared by every project installing that
    # version: the match yields one entry per project. `first` is what keeps
    # this a sha rather than a newline-joined list of them, which equals no real
    # sha while printing, truncated to 7 characters, as though it matched.
    installed_json="$HOME/.claude/plugins/installed_plugins.json"
    if [ -f "$installed_json" ]; then
      cached_sha=$(jq -r --arg ip "$install_path" \
        'first(.plugins["orrery@orrery"][]? | select(.installPath==$ip) | .gitCommitSha) // empty' \
        "$installed_json" 2>/dev/null)
    fi

    # Enabled vs. disabled comes from the entry matched on projectPath above,
    # so it is attributed to THIS project by construction.
    entry_enabled=$(echo "$entry" | jq -r '.enabled | select(. != null) | tostring')

    # "failed to load" is a third state no boolean can carry, and only the
    # plain text reports it. But plain text carries no projectPath: the awk
    # above takes the FIRST "orrery@orrery" block in the whole output, which on
    # a machine with orrery installed in several projects belongs to whichever
    # the CLI printed first. So the text is consulted only when it is
    # unambiguous — exactly one such block — and otherwise reports unknown
    # rather than attributing a neighbour's failure to this project.
    orrery_blocks=$(printf '%s\n' "$plain_all" | grep -c 'orrery@orrery')
    status_line=""; error_line=""
    if [ "$orrery_blocks" -eq 1 ]; then
      status_line=$(printf '%s\n' "$plain_block" | grep -m1 'Status:')
      error_line=$(printf '%s\n' "$plain_block" | grep -m1 'Error:')
    fi

    case "$status_line" in
      *"failed to load"*)
        bad "claude plugin list reports: failed to load"
        [ -n "$error_line" ] && bad "  $(printf '%s\n' "$error_line" | sed 's/^ *//')"
        row "load status" "failed to load"
        ;;
      *)
        # `enabled` is attributed correctly in every case, but it cannot rule
        # *out* a load failure — an enabled plugin that failed to load still
        # reads true. So where the text was too ambiguous to consult, "enabled"
        # ships with that limit attached rather than as a clean pass.
        case "$entry_enabled" in
          true)
            if [ "$orrery_blocks" -eq 1 ]; then
              ok "claude plugin list reports: enabled"; row "load status" "enabled"
            else
              warn "enabled per --json, but $orrery_blocks orrery@orrery blocks in the text — a load failure could not be ruled out for this project"
              row "load status" "enabled (load failure not ruled out)"
            fi
            ;;
          false) bad "claude plugin list reports: disabled"; row "load status" "disabled" ;;
          *)
            # No `enabled` field: a CLI older than the one measured in 2026-09.
            # Fall back to the text status, which is what this check read
            # before the field existed — but only where the text is
            # unambiguous, since that is the whole reason the field is
            # preferred when it is there.
            case "$status_line" in
              *"enabled"*)  ok "claude plugin list reports: enabled"; row "load status" "enabled" ;;
              *"disabled"*) bad "claude plugin list reports: disabled"; row "load status" "disabled" ;;
              *)
                if [ "$orrery_blocks" -eq 1 ]; then
                  warn "no enabled field and no status line for orrery@orrery in claude plugin list"
                  row "load status" "unknown"
                else
                  warn "no enabled field, and $orrery_blocks orrery@orrery blocks in the text — a status here could belong to another project"
                  row "load status" "unknown (more than one orrery block in the text)"
                fi
                ;;
            esac
            ;;
        esac
        ;;
    esac
  fi
elif [ "$have_jq" -eq 1 ]; then
  row "install found" "n/a (no claude CLI)"; row "load status" "n/a (no claude CLI)"
fi

# --- 2. enabled where the project actually writes it -------------------------
# Two files, because a repository whose index other people read keeps the
# owner's configuration out of it and enables the plugin in the untracked
# settings.local.json.
# Reading only the tracked file reported those projects as not enabled.
#
# `select(. != null)` and not `// false`: the alternative operator yields a
# non-empty string for a missing key, so "last non-null wins" implemented with
# `// false` means "last file that EXISTS wins" — settings.json true plus a
# settings.local.json without the key would have flipped to a false red. Check
# 8 carries the same note for the same reason.
#
# Which file answered is carried, not discarded. The tracked file varies by
# branch, which is the whole point of this check — a branch predating the
# install commit lacks the key. The untracked one does not vary by branch at
# all, so reporting it as a branch fact would be a check that cannot fire
# dressed as one that passed.
if [ "$have_jq" -eq 1 ]; then
  proj_scope_enabled=""; enabled_where=""
  for f in "$PROJECT/.claude/settings.json" "$PROJECT/.claude/settings.local.json"; do
    [ -f "$f" ] || continue
    v=$(jq -r '.enabledPlugins["orrery@orrery"] | select(. != null) | tostring' "$f" 2>/dev/null) || continue
    [ -n "$v" ] && { proj_scope_enabled="$v"; enabled_where="${f#"$PROJECT"/}"; }
  done
  branch=$(git -C "$PROJECT" branch --show-current 2>/dev/null)
  branch="${branch:-detached/no-git}"

  if [ -z "$enabled_where" ]; then
    if [ -f "$PROJECT/.claude/settings.json" ] || [ -f "$PROJECT/.claude/settings.local.json" ]; then
      bad "no enabledPlugins entry for orrery in either settings file on branch '$branch'"
      row "enabled on branch" "no ($branch)"
    else
      warn "neither $PROJECT/.claude/settings.json nor .claude/settings.local.json found"
      row "enabled on branch" "n/a"
    fi
  elif [ "$enabled_where" = ".claude/settings.local.json" ]; then
    # Untracked and therefore not branch-conditional — say so instead of
    # naming a branch the answer does not depend on.
    if [ "$proj_scope_enabled" = "true" ]; then
      ok "enabledPlugins true, from .claude/settings.local.json — untracked, so not a branch fact"
      row "enabled on branch" "yes (local file)"
    else
      bad "enabledPlugins false in .claude/settings.local.json — switched off deliberately, not a branch that predates the install"
      row "enabled on branch" "no (local file)"
    fi
  else
    if [ "$proj_scope_enabled" = "true" ]; then
      ok "enabledPlugins true on checked-out branch '$branch'"
      row "enabled on branch" "yes ($branch)"
    else
      bad "enabledPlugins false on branch '$branch' — this branch may predate the install commit"
      row "enabled on branch" "no ($branch)"
    fi
  fi
fi

# --- 3. user scope isn't double-enabling on top of this project's own -------
if [ "$have_jq" -eq 1 ]; then
  global_enabled=$(jq -r '.enabledPlugins["orrery@orrery"] // false' "$HOME/.claude/settings.json" 2>/dev/null)
  if [ "$global_enabled" = "true" ] && [ "${proj_scope_enabled:-false}" = "true" ]; then
    bad "orrery is enabled both globally (user scope) and for this project — every hook fires twice"
    row "global conflict" "yes — double-enabled"
  elif [ "$global_enabled" = "true" ]; then
    ok "orrery enabled at user scope globally; no project-local entry to conflict with"
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
#
# Two files record that source and both are read, project first — a project
# that writes its own `extraKnownMarketplaces` entry means it. The fallback is
# Claude Code's own ~/.claude/plugins/known_marketplaces.json, where the
# `source` object has exactly the shape the project entry uses.
#
# Reading only the project meant an install whose project never wrote that entry
# had this check skipped from the day it was installed — as a `warn`, so the run
# stayed green and the row read `n/a`, which is accurate and hard to tell from a
# check that ran and agreed. The messages below name which file answered.
if [ "$have_jq" -eq 1 ]; then
  known_json="$HOME/.claude/plugins/known_marketplaces.json"
  src_obj=$(jq -c '.extraKnownMarketplaces.orrery.source // empty' "$PROJECT/.claude/settings.json" 2>/dev/null)
  src_where="the project's .claude/settings.json"
  if [ -z "$src_obj" ]; then
    src_obj=$(jq -c '.orrery.source // empty' "$known_json" 2>/dev/null)
    src_where="$known_json"
  fi
  src_kind=$(printf '%s' "$src_obj" | jq -r '.source // empty' 2>/dev/null)
  live_sha=""
  case "$src_kind" in
    directory)
      src_path=$(printf '%s' "$src_obj" | jq -r '.path // empty' 2>/dev/null)
      if [ -n "$src_path" ] && [ -f "$src_path/.claude-plugin/plugin.json" ]; then
        live_ver=$(jq -r '.version' "$src_path/.claude-plugin/plugin.json" 2>/dev/null)
        live_sha=$(git -C "$src_path" rev-parse HEAD 2>/dev/null)
      else
        warn "source directory not resolvable ($src_path, named in $src_where) — skipping drift check"
      fi
      ;;
    github)
      src_repo=$(printf '%s' "$src_obj" | jq -r '.repo // empty' 2>/dev/null)
      if [ -n "$src_repo" ]; then
        live_sha=$(git ls-remote "https://github.com/$src_repo.git" HEAD 2>/dev/null | cut -f1)
        [ -z "$live_sha" ] && warn "couldn't reach https://github.com/$src_repo.git — skipping drift check (offline?)"
      else
        warn "no repo recorded for the github-sourced marketplace in $src_where — skipping drift check"
      fi
      ;;
    *)
      warn "no marketplace source found — looked in the project's .claude/settings.json and in $known_json — skipping drift check"
      ;;
  esac

  if [ -n "$live_sha" ]; then
    # Braced with a default. `cached_sha` is assigned only where an install for
    # this project was found, and under `set -u` reading it otherwise ends the
    # script mid-report with `unbound variable` — which is every run against a
    # repository that develops the plugin as a checkout rather than installing
    # it. The suite never saw it because its fixture always plants an install.
    if [ -n "${cached_sha:-}" ]; then
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

# --- 6. the loaded cache is still the bytes that were installed --------------
# Check 4 asks whether a different revision was installed than the source now
# holds. It cannot see the other way you end up running something nobody is
# looking at: a file edited in place inside the install. The recorded commit sha
# does not move when that happens, so check 4 reports the cache fresh while the
# loaded hooks and skills are something else. Reproducing a problem by poking at
# an installed copy is exactly when this happens.
#
# The baseline is trust-on-first-use, and the limit that follows is worth
# knowing: an edit made before this check ever ran here is recorded *as* the
# baseline and will not be reported. Every edit after that is.
#
# Keyed by install path, so upgrading re-records instead of crying wolf — a new
# install having different bytes is the reason for installing it.
if [ "$have_jq" -eq 1 ] && [ -n "${install_path:-}" ] && [ -d "$install_path" ]; then
  sum=""
  command -v shasum    >/dev/null 2>&1 && sum="shasum -a 256"
  [ -n "$sum" ] || { command -v sha256sum >/dev/null 2>&1 && sum="sha256sum"; }

  if [ -z "$sum" ]; then
    warn "no shasum or sha256sum on PATH — cannot check whether the cache was edited"
    row "cache unedited" "n/a (no hashing tool)"
  else
    # `.in_use` is written into the cache by Claude Code and moves on its own.
    # Hashing it would report every session as a tampered install. It is a
    # directory of one file per live session, named after the PID, so the path
    # exclusion is the one that holds — `-type f` never yields the directory
    # for the name filter to reject. The name filter stays for the file shape.
    now=$(find "$install_path" -type f ! -name '.in_use' ! -path '*/.in_use/*' -print0 2>/dev/null \
            | LC_ALL=C sort -z | xargs -0 $sum 2>/dev/null | $sum | cut -d' ' -f1)
    mkdir -p "$LOG_DIR" 2>/dev/null
    recorded=$(cat "$DIGEST_FILE" 2>/dev/null)
    rec_path="${recorded%%	*}"
    rec_digest="${recorded##*	}"

    if [ -z "$recorded" ]; then
      printf '%s\t%s\n' "$install_path" "$now" > "$DIGEST_FILE"
      warn "cache baseline recorded ($install_path) — first run here, so there is nothing to compare against yet"
      row "cache unedited" "baseline recorded"
    elif [ "$rec_path" != "$install_path" ]; then
      printf '%s\t%s\n' "$install_path" "$now" > "$DIGEST_FILE"
      ok "install path changed since last check — new baseline recorded for $install_path"
      row "cache unedited" "re-baselined (new install)"
    elif [ "$rec_digest" = "$now" ]; then
      ok "cache contents unchanged since the last check"
      row "cache unedited" "yes"
    else
      bad "cache contents changed at the same install path — a file inside $install_path was edited after installation; reinstall with: claude plugin update orrery@orrery"
      row "cache unedited" "no — edited in place"
    fi
  fi
elif [ "$have_jq" -eq 1 ]; then
  row "cache unedited" "n/a (no install path)"
fi

# --- 7. this project's copy of the deny-list is current ----------------------
# The deny rules this plugin ships are merged into your project's settings by
# hand. The plugin updates itself; that copy does not, and until this check
# existed nothing reported the gap — an install can sit dozens of rules behind
# with every other check here green.
#
# The comparison itself lives in hooks/permissions-check.sh and this calls it.
# Its three exit codes are kept apart on purpose: a comparison that could not be
# made is not drift, and reporting it as drift would make the finding worthless.
if [ "$have_jq" -eq 1 ]; then
  check="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/hooks/permissions-check.sh"
  if [ ! -x "$check" ]; then
    warn "permissions-check.sh not found beside this install ($check)"
    row "deny-list" "n/a"
  else
    out=$("$check" --report "$PROJECT" 2>&1); rc=$?
    case "$rc" in
      0) ok "deny-list current"; row "deny-list" "current" ;;
      1) bad "deny rules missing from this project's settings"
         printf '%s\n' "$out" | sed 's/^/    /'
         # The only copy with both operands resolved: the session-start hook
         # prints the path too, but leaves the project to default. The plugin
         # root is a version-pinned cache directory that moves on every update,
         # so a copy kept in a note goes stale. The sentence above it says whose
         # command it is, and `%q` keeps the line pasteable when a directory
         # along either path contains a space.
         warn "declined on purpose? that is recorded once, by the person at the keyboard, and never on their behalf:"
         printf '    %q --reconcile %q\n' "$check" "$PROJECT"
         row "deny-list" "behind" ;;
      *) warn "deny-list could not be compared — this is NOT a drift finding"
         printf '%s\n' "$out" | sed 's/^/    /'
         row "deny-list" "unknown" ;;
    esac
  fi
else
  row "deny-list" "n/a"
fi

# --- 8. whether the platform sandbox is switched on here ---------------------
# The defence has five layers and installing this plugin gives you three. Layers
# 4 and 5 are a `sandbox` block in settings.json, and **a plugin cannot write
# that file** — for the same reason it never merges the deny-list on your
# behalf: the file carrying every deny decision is not one a plugin may edit.
#
# So the sandbox never arrives with an install, and until this check existed
# nothing said so. A project could merge the deny-list, read a green doctor, and
# have no way to learn that two of the layers it had read about were not there.
#
# Reported, never failed. Whether to sandbox is your decision, and a doctor that
# goes red on a deliberate choice is a doctor people stop running — after which
# the deny-list findings above go unread too.
#
# **Two layers, two sources, and this check reported them as one.**
# `sandbox.enabled` in a project settings file buys layer 4: the kernel refuses
# a write outside the project. It does not buy layer 5.
# `network.strictAllowlist` is honoured only from user settings, managed
# settings or `--settings` on the command line — the last per session and the
# only scoped one — and is *ignored* from a
# repository's own file — so what a project settings file can do to egress is
# pre-allow, never deny, and an unlisted domain is asked about rather than
# refused. In auto mode that question goes to the classifier and not to you.
#
# So a project that switched the sandbox on used to read `layers 4 and 5` here
# while an unlisted domain answered normally. The two are reported apart now,
# and the second one names the per-session way to close it.
if [ "$have_jq" -eq 1 ]; then
  sb=""
  for f in "$PROJECT/.claude/settings.json" "$PROJECT/.claude/settings.local.json"; do
    [ -f "$f" ] || continue
    # `select(. != null)` and not `// empty`: jq's alternative operator treats
    # `false` as empty, so a sandbox switched off deliberately would have read
    # as one never configured — the two states this check exists to tell apart.
    v=$(jq -r '.sandbox.enabled | select(. != null) | tostring' "$f" 2>/dev/null) || continue
    [ -n "$v" ] && sb="$v"
  done
  case "$sb" in
    true)  ok "platform sandbox enabled — layer 4, the filesystem half"; row "sandbox" "on" ;;
    false) warn "platform sandbox is configured here but switched off"; row "sandbox" "off" ;;
    *)     warn "no platform sandbox here — layers 4 and 5 do not arrive with the plugin, and are yours to switch on"
           printf '    see "Optional: switch on the sandbox" in the install guide\n'
           row "sandbox" "absent" ;;
  esac

  # Layer 5 is asked only when layer 4 is on: the network block does nothing
  # with the sandbox off, and "egress does not deny" printed beside "no sandbox
  # here" reads as two problems where there is one.
  if [ "$sb" = "true" ]; then
    strict=""
    # The managed path is a variable so a test can point it somewhere it
    # controls: as a literal it would pass on any machine lacking the file.
    for f in "$HOME/.claude/settings.json" \
             "${DOCTOR_TEST_MANAGED-/Library/Application Support/ClaudeCode/managed-settings.json}"; do
      [ -r "$f" ] || continue
      v=$(jq -r '.sandbox.network.strictAllowlist | select(. != null) | tostring' "$f" 2>/dev/null) || continue
      [ -n "$v" ] && strict="$v"
    done
    case "$strict" in
      # The setting is only honoured from v2.1.219. On an older CLI it parses,
      # sits in the file, and does nothing — which reads exactly like the state
      # it claims to prevent, which is how this was missed the first time.
      # `sort -V` rather than a numeric compare: 2.1.9 is older than 2.1.100.
      # A version it cannot read gets its own answer rather than the happy one.
      # Falling through to `ok` there would print "egress denies" having
      # verified nothing, which is this check's own failure mode wearing the
      # sentence that says it was caught.
      true) cli="$(claude --version 2>/dev/null | awk '{print $1}')"
            case "$cli" in [0-9]*.[0-9]*.[0-9]*) ;; *) cli="" ;; esac
            if [ -z "$cli" ]; then
              warn "strictAllowlist is set, and the CLI version could not be read — unverified"
              printf '    it is honoured from 2.1.219; older than that it parses and does nothing\n'
              row "layer5" "cli-unknown"
            elif [ "$(printf '%s\n2.1.219\n' "$cli" | sort -V | head -1)" = "$cli" ] \
               && [ "$cli" != "2.1.219" ]; then
              warn "strictAllowlist is set and this CLI ($cli) predates it — egress does not deny"
              row "layer5" "cli-too-old"
            else
              ok "egress denies unlisted domains — layer 5, from a source the platform honours"
              row "layer5" "denying"
            fi ;;
      # No line for the machine-wide sources, deliberately: closing it there for
      # *this* project tightens every other one, met somewhere else with nothing
      # connecting it to a plugin installed here. A library that may not write a
      # settings file must not talk you into writing the more dangerous one by
      # hand. `--settings` is the third source and is per session; measured, so
      # it is named as a recipe rather than as a possibility.
      *)    warn "egress pre-allows and never denies — layer 5 is not closed here"
            printf '    an unlisted domain is asked about, not refused, and in auto mode nobody is asked\n'
            printf '    two of the three sources that would close it are machine-wide and would\n'
            printf '    tighten every other project you have, so no line for those is printed here\n'
            printf '    the third is per project and measured: put sandbox.network.strictAllowlist in\n'
            printf '    a file and start with  claude --settings <file>  — binds that session only\n'
            printf '    this check reads files, not the running session: it says pre-allow even inside\n'
            printf '    a session started that way, so the flag is not something it can confirm\n'
            row "layer5" "pre-allow" ;;
    esac
  else
    row "layer5" "n/a"
  fi
else
  row "sandbox" "n/a"
  row "layer5" "n/a"
fi

# --- 9. the method this plugin implements is installed alongside it ---------
# `orrery` declares `orrery-method` as a dependency: the corpus is published
# once, as its own plugin, and installing orrery pulls it in. So both present is
# the healthy state, and orrery alone is the failure — every skill still loads
# and every guard still fires, while the method they implement is simply not in
# the session. Nothing else reports that.
if [ "$have_jq" -eq 1 ] && [ "$have_claude" -eq 1 ] && [ -n "${json:-}" ]; then
  family=$(echo "$json" | jq -r --arg p "$PROJECT" \
    '[.[] | select((.id | startswith("orrery")) and (.scope == "user" or .projectPath == $p)) | .id] | unique | .[]' \
    2>/dev/null)
  has_full=0; has_method=0; extra=""
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    case "${id%%@*}" in
      orrery)        has_full=1 ;;
      orrery-method) has_method=1 ;;
      *)             extra="$extra ${id%%@*}" ;;
    esac
  done <<< "$family"

  if [ "$has_full" -eq 1 ] && [ "$has_method" -eq 1 ]; then
    ok "orrery and its orrery-method dependency are both here"
    row "family" "orrery + method"
  elif [ "$has_full" -eq 1 ]; then
    bad "orrery is installed and orrery-method is not — the method its skills implement is missing, and nothing else will say so"
    printf '    the dependency installs with orrery; if it did not, the marketplace may not allow the cross-marketplace reference\n'
    row "family" "orrery, method missing"
  elif [ "$has_method" -eq 1 ]; then
    ok "orrery-method only — the corpus, without the machinery that executes it"
    row "family" "orrery-method"
  else
    row "family" "none found"
  fi
  [ -n "$extra" ] && warn "also installed from this family:$extra — unknown to this doctor, check it is meant to be there"
fi

# --- 10. installed and loaded is not the same as used ------------------------
#
# Every check above answers "is the plugin present and current". None answers
# "is any of it running", and the two come apart further than they look: a
# project can close 141 issues and merge 154 pull requests in a week with no
# orrery skill in its call log at all, the only part of the library executing
# there being a hook. Another can spawn every agent untyped — no critic, no
# auditor — which is the role frontmatter never applying, silently.
#
# None of that is a broken install, so nothing here counts toward `fail`. It is
# reported because otherwise nobody looks: "is the method actually being used
# here" had no command behind it, and the answer turned out to be no.
#
# The call log is off unless you asked for it, and that absence is itself the
# finding — a project with no log cannot answer this question at all.
echo
DAYS="${ORRERY_DOCTOR_DAYS:-7}"
since="$(date -u -v-"${DAYS}"d +%Y-%m-%d 2>/dev/null || date -u -d "$DAYS days ago" +%Y-%m-%d)"
calls="${ORRERY_CALL_LOG:-}"
case "$calls" in ''|/*) ;; *) calls="$PROJECT/$calls" ;; esac
[ -n "$calls" ] || calls="$PROJECT/.claude/orrery-calls.tsv"

if [ ! -f "$calls" ]; then
  warn "no call log, so what has actually run here is unknowable — see install/into-project.md"
  row "usage" "no log"
else
  skills_ran="$(awk -F'\t' -v s="$since" '$1>=s && $3=="Skill" && $6=="ran" && $4 ~ /^orrery:/ {print $4}' "$calls" | sort -u | tr '\n' ' ')"
  spawns="$(awk -F'\t' -v s="$since" '$1>=s && $3=="Agent" && $6=="ran"' "$calls" | wc -l | tr -d ' ')"
  # `-`, empty, or the literal `general-purpose`. The recorder writes `-` only
  # when no type was passed at all, and the failure this reports — a role's
  # model and tool list never applying — happens just as completely when a
  # session passes `general-purpose` explicitly. Counting only `-` made the
  # check dead against the very log that motivated it.
  untyped="$(awk -F'\t' -v s="$since" '$1>=s && $3=="Agent" && $6=="ran" && ($4=="-" || $4=="" || $4=="general-purpose")' "$calls" | wc -l | tr -d ' ')"
  if [ -n "$skills_ran" ]; then
    ok "skills that fired in the last $DAYS days: $skills_ran"
    row "usage" "skills: $skills_ran"
  else
    warn "no orrery skill has fired here in $DAYS days — the plugin is loaded and nothing is invoking it"
    row "usage" "no skills in $DAYS days"
  fi
  if [ "$untyped" -gt 0 ]; then
    warn "$untyped of $spawns agent spawns carried no role — untyped or general-purpose, so no role's model and tool list applied"
    row "spawns" "$untyped/$spawns untyped"
  fi

  # The log trims itself oldest-first at its cap, silently. A window shorter
  # than the one asked for makes every count above a floor rather than a total,
  # and saying so is the difference between a number and a misleading one.
  cap="${ORRERY_CALL_LOG_MAX:-262144}"
  size="$(wc -c < "$calls" | tr -d ' ')"
  oldest="$(head -1 "$calls" | cut -f1)"
  if [ "$size" -gt $(( cap * 9 / 10 )) ]; then
    warn "the call log is at $size of $cap bytes and drops its oldest rows — it starts at $oldest, so the counts above are a floor"
  fi
fi

# --- the number that says whether any of this worked -------------------------
#
# Every count above is about *this* machine: which skills ran, which spawns
# carried a role. None of them answers the question the retrospective gate was
# built for — are issues closing with their cost recorded — and a mechanism
# whose effect nobody measures is how the first version of this problem went
# unnoticed for months.
#
# Two numbers, side by side. Issues closed in the window carrying no
# retrospective, and waivers recorded in the same window. The first is the
# failure; the second is the part of it somebody decided on purpose, which is a
# different fact and must not be averaged into the first.
#
# This is the one check here that needs the network, and every way it can fail
# has to be visibly different from a clean answer. A tool in this method shipped the other
# behaviour once, where a failed fetch and a successful one produced identical
# reports, and a release was prepared twice on the strength of it. Four
# failure shapes, four distinct words:
#
#   * it cannot ask                    -> `unknown`, never zero
#   * it answers something unparseable -> `unknown`, because `[ "x" -gt 0 ]`
#                                         errors and falls into the *success*
#                                         branch, printing a green tick
#   * it hits the page limit           -> says the numbers are a floor, the way
#                                         the call-log cap above already does
#   * nothing closed at all            -> says so, rather than a tick that reads
#                                         as "all of them carried one"
RETRO_LIMIT="${ORRERY_DOCTOR_LIMIT:-500}"
if command -v gh >/dev/null 2>&1; then
  counts="$(cd "$PROJECT" 2>/dev/null && gh issue list --state closed \
    --search "closed:>=$since" --limit "$RETRO_LIMIT" --json number,comments \
    --jq '[(length), ([.[] | select(((([.comments[]?.body] // []) | join("")) | contains("<!-- retrospective")) | not)] | length)] | @tsv' \
    2>/dev/null || true)"
else
  counts=""
fi

# Two integers and a tab, or nothing. Anything else is an answer this cannot
# read, and reading it anyway is how a malformed reply printed a green tick.
case "$counts" in
  *[!0-9$'\t']*|'' | *$'\t'*$'\t'*) counts="" ;;
  *$'\t'*) ;;
  *) counts="" ;;
esac

if [ -n "$counts" ]; then
  n_closed="$(printf '%s' "$counts" | cut -f1)"
  n_bare="$(printf '%s' "$counts" | cut -f2)"

  # The waiver log resolves the way `hooks/waiver.sh` resolves it, not the way
  # the call log does. Deriving it from `$calls` meant any project that named
  # its call log elsewhere got a silent `0 waived` beside a file full of
  # waivers — the same zero-that-means-unknown this section refuses to print.
  wlog="${ORRERY_WAIVER_LOG:-.claude/orrery-waivers.tsv}"
  case "$wlog" in /*) ;; *) wlog="$PROJECT/$wlog" ;; esac
  waived=0
  if [ -f "$wlog" ]; then
    # Only waivers for a close. The log records every deliberate skip, so an
    # unfiltered count could exceed the number it annotates.
    waived="$(awk -F'\t' -v s="$since" '$1>=s && $4 ~ /^gh issue close/' "$wlog" | wc -l | tr -d ' ')"
  fi

  if [ "$n_closed" -eq 0 ]; then
    warn "no issues closed here in $DAYS days, so there is nothing to say about retrospectives"
    row "retrospectives" "nothing closed"
  elif [ "$n_bare" -gt 0 ]; then
    warn "$n_bare of $n_closed issues closed in $DAYS days carry no retrospective ($waived waived on purpose)"
    # Most of these are closes a merge performed, which no hook sees. The
    # workflow is the half that does; naming it here is what turns a number
    # into a next step.
    printf '    a merge closes issues past every hook — install/ci/retrospective-on-close.yml reopens those\n'
    row "retrospectives" "$n_bare/$n_closed missing, $waived waived"
  else
    ok "every issue closed in $DAYS days carries a retrospective ($n_closed of them)"
    row "retrospectives" "$n_closed/$n_closed"
  fi
  [ "$n_closed" -ge "$RETRO_LIMIT" ] && warn "the query stopped at $RETRO_LIMIT issues, so those counts are a floor — ORRERY_DOCTOR_LIMIT raises it"
else
  warn "could not read an answer from the tracker, so whether closed issues carry retrospectives is unknown here — not zero"
  row "retrospectives" "unknown"
fi

# The one gate a hook cannot be. A merge closes an issue server-side, from an
# event no local hook is present for, so this half lives in your repository —
# and a copied file can simply be absent.
# Any workflow that runs the matcher, not one filename. This repository carries
# the same gate inline in its own `gates.yml`, so a filename check reported it
# missing on the first project anyone would run this against — a check with one
# implementation, wrong where it was written.
#
# And a repository with no workflows at all gets the warning too. The previous
# shape said nothing there, which is silence for exactly the repository with
# zero merge-side coverage.
if [ -d "$PROJECT/.github/workflows" ] \
   && grep -rlq 'names-an-issue' "$PROJECT/.github/workflows" 2>/dev/null; then
  ok "a workflow refuses a pull request that names no issue"
  row "pr gate" "present"
else
  warn "nothing refuses a pull request that names no issue — a merge can close an issue no pull request named, and no hook can see it"
  row "pr gate" "missing"
fi

echo
if [ "$fail" -eq 0 ]; then echo "doctor: clean"; else echo "doctor: $fail area(s) need attention"; fi

# --- append a compact row to the per-project log for trend-analysis ---------
mkdir -p "$LOG_DIR" 2>/dev/null
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
