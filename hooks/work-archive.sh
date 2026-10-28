#!/usr/bin/env bash
# PostToolUse hook. Where a project ignores `.orrery/work/`, a work's records —
# retrospective, handoff, plan, debt — live only in its worktree, and
# `git worktree remove` deletes them: an ignored file is in no branch. This copies
# them into the main checkout's `.orrery/local/work/` each time one is written.
#
# ## Why a hook, and why after the write
#
# The record is written in the tree, by `record.sh` or the Write and Edit tools,
# because that is where a session can write: a sandboxed session cannot reach the
# main checkout, measured. A hook runs outside the sandbox and can. No event fires
# on `git worktree remove`, so the copy is made at the only moments that exist —
# right after something touched the records — and the copy is always the newest.
#
# ## Which tree
#
# Not the session's directory: a session launched in the main checkout writes
# into a worktree as often as one launched in it. A Write or Edit names its file,
# so its own tree is the one. A Bash command does not say where it ran
# (`cd <wt> && record.sh write`), so every worktree of the clone is archived —
# each copy is cheap and replaces nothing.
#
# ## Cheap first
#
# This runs after every Bash, Write and Edit call. Nothing touches git unless the
# payload mentions `.orrery/work` or `record.sh`; everything else exits here.
# Fails open and silent: an archive that cannot be made never stops a session.
input="$(cat)"
case "$input" in *.orrery/work*|*record.sh*) ;; *) exit 0 ;; esac
command -v jq >/dev/null 2>&1 || exit 0
here="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=hooks/orrery-config.sh
. "$here/orrery-config.sh"

tool="$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null)"
case "$tool" in
  Write|Edit)
    f="$(jq -r '.tool_input.file_path // empty' <<<"$input" 2>/dev/null)"
    case "$f" in */.orrery/work/*) ;; *) exit 0 ;; esac
    d="$(dirname "$f")"; [ -d "$d" ] || exit 0
    orrery_work_archive "$d" ;;
  Bash)
    cwd="$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)"
    [ -n "$cwd" ] && [ -d "$cwd" ] || exit 0
    git -C "$cwd" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' \
      | while IFS= read -r wt; do [ -d "$wt" ] && orrery_work_archive "$wt"; done ;;
esac
exit 0
