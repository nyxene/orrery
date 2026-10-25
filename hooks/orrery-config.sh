#!/usr/bin/env bash
# Where Orrery's own state lives, and what the project declared. Sourced, never
# run: the hooks and scripts that need a path or a setting call these functions,
# so there is one answer to each question instead of one per caller.
#
#   .orrery/config.json   committed; every setting the project declares
#   .orrery/local/        per machine, never committed; written only by hooks
#   .orrery/work/<work>/  what a piece of work generates; committed by default
#
# Orrery keeps nothing of its own in a folder that is not its own, and never
# edits the user's `.gitignore` — `local/` carries its own.
#
# Two roots, on purpose. `config.json` and `work/` are read from the toplevel of
# the tree the session stands in, so a branch that changes the config is
# exercised in its own worktree. `local/` belongs to the clone, so it is read
# from the main checkout, found through the common git directory — a session
# launched in the main checkout and working in a worktree, and one launched in
# the worktree itself, then reach the same log.
#
# Reading fails open: a missing or malformed config is the defaults. A session
# is never blocked by a settings file. Whether that silence is acceptable is the
# caller's question — the loader warns about it, see `orrery_config_problem`.

# The main checkout of the repository containing $1 (default: the current
# directory). Empty outside a repository.
orrery_main() {
  local common
  common="$(git -C "${1:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 0
  case "$common" in
    */.git) printf '%s' "${common%/.git}" ;;
    *)      printf '%s' "$(git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null)" ;;
  esac
}

# The toplevel of the tree $1 stands in — a worktree's own root, not the main
# checkout's. Empty outside a repository.
orrery_toplevel() {
  git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null || true
}

# The config file for the tree $1 stands in.
orrery_config_file() {
  local top; top="$(orrery_toplevel "${1:-.}")"
  # Returns 0 either way: a caller under `set -e` that assigns this outside a
  # repository must get an empty answer, not an exit. The loader was killed
  # that way once, silently, before it had printed the canon.
  [ -n "$top" ] || return 0
  printf '%s/.orrery/config.json' "$top"
}

# orrery_config <key> [default] [dir] — the declared value, or the default.
# A string prints as itself; anything else as compact JSON.
orrery_config() {
  local f v
  f="$(orrery_config_file "${3:-.}")"
  if [ -n "$f" ] && [ -r "$f" ]; then
    v="$(jq -r --arg k "$1" 'if (.[$k] | type) == "string" then .[$k] elif has($k) then (.[$k] | tojson) else empty end' "$f" 2>/dev/null)" || v=""
  fi
  printf '%s' "${v:-${2:-}}"
}

# `none` unless the project declared a tracker. Every tracker-dependent
# behaviour asks this and nothing else, so the adapter interface has one place
# to replace.
orrery_tracker() {
  local t; t="$(orrery_config tracker none "${1:-.}")"
  case "$t" in github) printf github ;; *) printf none ;; esac
}

# Why the config would not be read, or nothing when it is fine: `missing` or
# `malformed`. Only worth saying where the project is plainly on GitHub — a
# project with no config and no GitHub remote is the default case, not a fault.
orrery_config_problem() {
  local f; f="$(orrery_config_file "${1:-.}")"
  [ -n "$f" ] || return 0
  if [ ! -e "$f" ]; then
    git -C "${1:-.}" remote get-url origin 2>/dev/null | grep -q 'github\.com' && printf missing
  elif ! jq -e 'type == "object"' "$f" >/dev/null 2>&1; then
    printf malformed
  fi
  return 0
}

# The name of the work the tree $1 stands in: the worktree's directory name, or
# on the main checkout the branch. No date: a record written one day would not
# be found under the next day's name. `/` in a branch name would make a nested
# directory, so it is replaced.
orrery_work() {
  local top main branch
  top="$(orrery_toplevel "${1:-.}")"; main="$(orrery_main "${1:-.}")"
  [ -n "$top" ] || return 0
  if [ "$top" != "$main" ]; then
    printf '%s' "$(basename "$top")"
  else
    branch="$(git -C "$top" symbolic-ref --short -q HEAD 2>/dev/null || printf detached)"
    printf '%s' "${branch//\//-}"
  fi
}

# When branch $1 began, from its first reflog entry, as UTC `YYYY-MM-DDTHH:MM:SSZ`
# — the call log's spelling, so the two compare as strings. Nothing when the
# reflog holds none (expired after 90 days by default, or never kept).
orrery_born() {
  TZ=UTC0 git -C "${2:-.}" reflog show --date=format-local:%Y-%m-%dT%H:%M:%SZ \
    --format=%gd "refs/heads/$1" -- 2>/dev/null | tail -1 | sed -n 's/.*@{\(.*\)}$/\1/p' || true
}

# The per-machine directory, created with its own `.gitignore` before anything
# is written into it, so nothing there can reach a commit. Prints the path.
# Returns 1 outside a repository: a hook calling it under `set -e` writes
# `d="$(orrery_local_ensure)" || exit 0`, or it dies the way the loader once did.
# Needs git 2.31 or later (`--path-format`); older git reads every root as
# "not a repository".
orrery_local_ensure() {
  local main d
  main="$(orrery_main "${1:-.}")"
  [ -n "$main" ] || return 1
  d="$main/.orrery/local"
  mkdir -p "$d" 2>/dev/null || return 1
  [ -f "$d/.gitignore" ] || printf '*\n' > "$d/.gitignore" 2>/dev/null || return 1
  printf '%s' "$d"
}

# orrery_local_file <name> <old> [dir] — the path of a per-machine file, ensured.
# The first time it is asked for, the file it replaces is copied in, once, and
# left where it was: 0.31 still reads the old one, so a rollback loses only the
# rows written since. <old> is relative to the main checkout unless absolute.
# Returns 1 where orrery_local_ensure does.
orrery_local_file() {
  local d old
  d="$(orrery_local_ensure "${3:-.}")" || return 1
  if [ ! -e "$d/$1" ] && [ -n "$2" ]; then
    case "$2" in /*) old="$2" ;; *) old="$(orrery_main "${3:-.}")/$2" ;; esac
    if [ -f "$old" ]; then cp "$old" "$d/$1" 2>/dev/null || true
    elif [ -d "$old" ]; then cp -R "$old" "$d/$1" 2>/dev/null || true; fi
  fi
  printf '%s/%s' "$d" "$1"
}

# orrery_marker <name> [dir] — the path of a once-per-session marker, in
# `local/sessions/`. One file per session would only grow, so asking for a
# marker that does not exist yet removes those older than a week. Outside a
# repository it falls back to $TMPDIR: there is no `.orrery/` to keep it in, and
# without a marker a hook that fires before every tool call repeats itself.
orrery_marker() {
  local d
  if d="$(orrery_local_ensure "${2:-.}")" && mkdir -p "$d/sessions" 2>/dev/null; then
    [ -e "$d/sessions/$1" ] || find "$d/sessions" -type f -mtime +7 -delete 2>/dev/null || true
    printf '%s/sessions/%s' "$d" "$1"
  else
    printf '%s/orrery-%s' "${TMPDIR:-/tmp}" "$1"
  fi
}

# Where a reader finds a per-machine file without creating anything: the new
# place once it exists, else the old one, else the new one. A host that has not
# yet run a session under this version still has its history where it was.
orrery_local_read() {
  local main new old
  main="$(orrery_main "${3:-.}")"
  [ -n "$main" ] || return 0
  new="$main/.orrery/local/$1"
  case "$2" in /*) old="$2" ;; *) old="$main/$2" ;; esac
  if [ ! -e "$new" ] && [ -n "$2" ] && [ -e "$old" ]; then printf '%s' "$old"; else printf '%s' "$new"; fi
}
