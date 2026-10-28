#!/usr/bin/env bash
# PreToolUse guard for the Bash tool, and for the edit tools on Orrery's two
# settings files (see that block below). One act refused until its obligation is
# met — where the work heads for the default branch, with no auditor run in this
# session since it last did, or with no record of the work committed — and one
# act refused outright, because the harness does it the safe way:
# `git worktree add`. The act is `gh pr create` where the project's tracker is
# GitHub, and a branch's first `git push` where it has none.
#
# The gate does not reach: a pull request opened by a person, in
# the web UI, through `gh api`, or by a spelling its matcher misses; a heredoc
# fed to a shell (`bash <<EOF`), whose body runs although it is read as text; a
# project that switched the call log off, where the auditor half has nothing to
# read; commits pushed to a pull request after its audit; and a merge that needs
# no pull request where a project allows one. It refuses falsely on a line of a
# multi-line quoted string that begins with `gh pr create` — it reads lines, not
# shell quoting — which costs an argument, not a boundary.
#
# ## Why a separate file from hooks/bash-guard.sh
#
# That guard's own header argues against being loaded up: it is a nudge against
# an unrecoverable accident, spent "on the few commands whose accident is
# unrecoverable, and nowhere else", because every additional check is another
# false refusal today and another row in an advisory table later. This one is a
# different trade with a different failure direction — a false refusal here
# costs an argument, not a boundary — so it gets its own file, its own corpus,
# and its own answer to the question below.
#
# ## Fail open, deliberately, which is the opposite of the other two guards
#
# The Bash guard denies when it cannot parse its input: doubt about a delete is
# resolved toward refusing. Copying that here would mean a session with no `jq`
# cannot run *any* command, in exchange for enforcing bookkeeping. The first
# thing anyone would do is remove the hook, and then neither the bookkeeping
# nor the delete guard exists.
#
# So: anything this cannot read is passed through, and the corpus pins that.
# The gate is a nudge at the one moment it can still change the outcome, not a
# boundary — nothing here resists a session that means to get past it, and the
# waiver below is the supported way to do exactly that.
#
# ## What it actually enforces, and what it stopped enforcing
#
# Measured over one week across three host projects: 179 issues closed, 218
# pull requests merged, 2 retrospectives. A step inside a skill nobody invokes is
# not a mechanism: what has a refusal behind it works, what relies on a session
# remembering does not.
#
# For months the refusal sat on `gh issue close`, with a workflow in the host
# repository reopening what a merge closed bare. Both are gone. The record is now
# a file committed with the work (`skills/build/record.sh`), so the act that
# carries it to the default branch is the pull request, and the refusal moved
# there in the same change — a forcing function retired without its successor
# is a gap. Closing an issue is the person's act again, and the workflow no
# longer rewrites a state a person sets.
#
# Exit contract: prints a permissionDecision JSON and exits 0 to deny; prints
# nothing and exits 0 to pass through.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=hooks/orrery-config.sh
. "$here/orrery-config.sh"

# Every refusal ends with the rule that governs it; see the same line in
# `bash-guard.sh` for why it is carried here rather than left to the loader.
refusal_note="A refusal is the person's to rule on, not yours. If you think this one is wrong, stop, quote it to them and say why. Do not reach the same outcome another way — another tool, a script file, a respelling, a split command — unless this message names that way."

deny() {
  jq -n --arg r "$1" --arg note "$refusal_note" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:($r + "\n\n" + $note)}}'
  exit 0
}

# No `command -v jq` probe and no `[ -n "$cmd" ]` guard above the matcher. Both
# were here and both were removed after a mutation pass showed neither could be
# killed: with jq absent the extraction below yields an empty string, an empty
# string matches nothing, and every `-n` test on a match below exits 0
# — the same fail-open the probes assert, reached by one path instead of three.
# A line whose deletion changes no observable behaviour is a line that reads as
# a decision and is not one.
input="$(cat)"
cmd="$(jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null || true)"
# The tree the command runs in, from the harness; the launch directory when the
# payload has none. Where the waiver and the gate's state are written.
dir="$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null || true)"
[ -n "$dir" ] && [ -d "$dir" ] || dir="${CLAUDE_PROJECT_DIR:-.}"

# `gh pr create`, however it is spaced or flagged, but only where a command can
# actually start. An unanchored match would refuse `echo "gh pr create"` and a
# commit message describing the guard itself. A false refusal is what gets a
# hook deleted, and a deleted hook enforces nothing.
#
# A command position is the start, or after `;`, `&`, `(`, an unescaped `|`,
# `then`, `do` or `if`, followed by any number of environment assignments. That
# last part is not decoration: the waiver below *is* an assignment prefix, so a
# pattern that stopped at the first `VAR=` would pass the waived form through
# without ever recording it — permitting exactly the case whose whole purpose is
# to leave a trace. The assignment's value has to allow quoted spaces for the
# same reason; a reason worth writing has spaces in it.
q="'"
assign="[A-Za-z_][A-Za-z0-9_]*=(\"[^\"]*\"|${q}[^${q}]*${q}|[^[:space:]]*)[[:space:]]+"
# `command`, `env` and a leading backslash are ordinary spellings rather than
# evasions, and each of them slipped past the first version. `gh -R owner/repo
# pr create` is not an evasion at all — it is what a session writes when it is
# being careful about which repository it is in.
# A `|` preceded by a backslash is not a pipe: `grep 'push\|gh pr create'` is a
# pattern with alternation, and reading its `\|` as a command boundary counted an
# auditor's own search as a pull request opened — after which the gate refused
# the real one, because the audit now looked older than the "pull request".
pos="(^|[;&(]|(^|[^\\\\])\\||\\bthen\\b|\\bdo\\b|\\bif\\b)[[:space:]]*(${assign})*(command[[:space:]]+|env[[:space:]]+|\\\\)*"
ghflags="(-[^[:space:]]+([[:space:]]+[^-][^[:space:]]*)?[[:space:]]+)*"

# The whole matched segment, not the whole command. `grep -q` over `$cmd` said
# only *whether* something matched, so the waiver check then searched the entire
# command for `ORRERY_WAIVE=` — which is how `ORRERY_WAIVE="x" echo hi; gh issue
# close 42` recorded a waiver that was never attached to the close. `|| true`
# because of `pipefail`: with no match, `grep` exits 1, the assignment fails and
# `set -e` ends the script with status 1 on every command that does not match —
# erroring thousands of times a day, invisibly, because the harness reads a
# non-zero hook as a non-blocking error. Found by the mutation pass.
# Heredoc bodies are text, never commands. `^` in `pos` matches at the start of
# every line, so a document written through `cat > f <<'EOF'` whose line reads
# `ORRERY_WAIVE="…" gh pr create` was a command here — refused, or worse,
# recorded as a waiver nobody issued. Everything between `<<WORD` and `WORD` is
# dropped before either matcher reads the command. `<<<` is a here-string and
# untouched; `<<-` strips leading tabs from the terminator, as bash does; a body
# with no terminator runs to the end. One heredoc per line is read — a second
# on the same line is the rare spelling this leaves to the matchers. A heredoc
# fed to a shell (`bash <<EOF`) runs its body, and this lets it through: that is
# the fail-open direction, and the header names it.
scan="$(awk -v sq="'" '
  hd { t = $0; if (dash) sub(/^\t+/, "", t); if (t == delim) hd = 0; next }
  { print; s = $0; gsub(/<<</, "\001", s)
    if (match(s, "<<-?[ \t]*[\"" sq "]?[A-Za-z_][A-Za-z0-9_]*")) {
      m = substr(s, RSTART, RLENGTH); dash = (m ~ /^<<-/)
      sub("^<<-?[ \t]*[\"" sq "]?", "", m); delim = m; hd = 1 } }' <<<"$cmd" 2>/dev/null || printf '%s' "$cmd")"

# The fingerprint `hooks/call-log.sh` writes, computed the same way, byte for
# byte — including `nosession` and `nohash` — because the pull-request gate
# below looks this session up in that log, and a different spelling of the same
# session finds nothing there and refuses forever.
fingerprint() {
  local s fp=""
  s="$(jq -r '.session_id // "nosession"' <<<"$input" 2>/dev/null || true)"
  if command -v shasum >/dev/null 2>&1; then
    fp="$(printf '%s' "$s" | shasum -a 256 2>/dev/null | cut -c1-8 || true)"
  elif command -v sha256sum >/dev/null 2>&1; then
    fp="$(printf '%s' "$s" | sha256sum 2>/dev/null | cut -c1-8 || true)"
  fi
  printf '%s' "${fp:-nohash}"
}

# The escape, and the record, are the same act. Without this the gate has no
# supported way past it, and a gate with no supported way past it is removed
# rather than obeyed. $1 is the matched segment, $2 the act as recorded.
waive() {
  local rest reason record
  # Parameter expansion rather than sed, after the sed version accepted `""` as
  # a reason: the quoted branch returned empty, the unquoted fallback then
  # captured the two quote characters themselves, and an empty waiver was
  # recorded as a real one. The three cases are the three ways a shell value is
  # written, and each has to end at its own delimiter.
  rest="${1#*ORRERY_WAIVE=}"
  case "$rest" in
    '"'*) reason="${rest#\"}"; reason="${reason%%\"*}" ;;
    "'"*) reason="${rest#\'}"; reason="${reason%%\'*}" ;;
    *)    reason="${rest%% *}" ;;
  esac
  if [ -z "$reason" ]; then
    deny "ORRERY_WAIVE is set with no reason behind it.

A waiver with an empty reason records that something was skipped and not why,
which is the silence the waiver exists to end. Write the reason:

  ORRERY_WAIVE=\"owner said to skip it, we are mid-incident\" $2"
  fi
  # `command`, never `typed`. The field says *how* the waiver arrived, and on
  # this path the token was spelled by whichever agent composed the Bash call —
  # not by the owner. Hardcoding the strongest provenance class here asserted
  # owner authorization for a self-authorized skip, in the one file whose value
  # is that its rows are true. `stated` is for a human running waiver.sh.
  #
  # And the record is what permits, rather than something attempted beside it.
  # This was `|| true` with stderr discarded, so a recording that failed — no
  # project root, an unwritable directory — granted the exemption silently and
  # left nothing at all. Fail open on input this cannot read; fail closed on a
  # record it cannot write. Those are different questions and they get opposite
  # answers on purpose.
  if ! record="$(cd "$dir" 2>/dev/null && ORRERY_WAIVE_SESSION="$(fingerprint)" \
        bash "$here/waiver.sh" "$2" "$reason" command 2>&1)"; then
    deny "The waiver could not be recorded, so the exemption is not granted.

$record

An unrecorded skip is the silence this gate exists to end — it cannot be handed
out on the strength of having tried."
  fi
}

# --- a worktree is made by the harness, never by `git worktree add` ----------
# The sandbox protects `.claude/` paths in every checkout, so this fails there,
# and the retry a session reaches for is the same command with the sandbox off —
# every protection lifted for the whole call. The harness's own ways cover the
# need, so it is refused either way. `rtk` may have rewritten `git` already.
gitflags="(-[Cc][[:space:]]+([^[:space:]\"${q}]|\"[^\"]*\"|${q}[^${q}]*${q})+[[:space:]]+|--?[A-Za-z][A-Za-z-]*(=[^[:space:]]*)?[[:space:]]+)*"
if grep -qE "${pos}(rtk[[:space:]]+)?git[[:space:]]+${gitflags}worktree[[:space:]]+add\\b" <<<"$scan"; then
  deny "A session does not make worktrees with git worktree add: in the sandbox it
fails on protected .claude/ paths, and outside it nothing is protected. Use
EnterWorktree for this session, or isolation: \"worktree\" on an Agent. If
neither fits, ask the person to run it in their terminal."
fi

# --- the settings, and the records the gates read, are not a session's -------
# `.orrery/config.json` and this machine's `.orrery/local/config.json`: either
# can switch a gate off, and the local one is outside review entirely — written
# by a session, nothing would show it until the next session's start.
#
# And the records (`orrery-config.sh` states the rule: `.orrery/local/` is
# written only by hooks). What is at stake is the evidence, not the gates' force
# — every gate here is a nudge, and an idle auditor is cheaper than a forged
# row — so the threat is erasing or rewriting: the call log, the gate's state
# (deleted, its "since" resets), the waiver log, `deny.json` (a matching hash
# silences the startup line), the session markers (a worktree's creator record), the
# doctor's cache-digest baseline, the archived records, `onboard/install-record.json`
# (rollback writes it into the plugin registry), and the decline record with its
# legacy name, which silences the missing-deny-rules line. Every file directly in
# `.orrery/local/` is protected, and everything under `sessions/`, `doctor/` and
# `work/`; open are only onboard's draft directories, `onboard/<project>/`, and
# only on a path with no `.`/`..` segment after `.orrery/`. Their writers are
# hooks and scripts, whose command lines name none of this, so nothing they do is
# refused. The deny rules, once merged, cover the same files by name — never
# `Edit(**/.orrery/local/*)`, which as a directory pattern could deny the draft
# directories themselves.
#
# The edit tools. The deny list keeps them off both files, but only once it is
# merged into the project's settings, and a session in a fresh project wrote the
# local one with Write before that (the 0.33.0 rehearsal). Plugin hooks arrive
# with the install, so this holds from the first session; the deny rule, once
# merged, is the boundary, and this is the nudge before it. No `tool_name` test:
# the matcher already scopes, and a Bash payload has no file_path, so such a
# line could be deleted without anything changing. The pattern absorbs `//`;
# a `config.json` on a path with a `.` or `..` segment is refused outright, and
# so is anything below either file (`config.json/`, `config.json/x/..`), which
# a resolver folds back onto it — a legitimate one is rare where the tools take
# absolute paths, and rewriting the path first missed `/././` (one pass cannot
# see overlapping matches). Not modelled: a directory symlink written through
# (`link/config.json`), Windows separators.
#
# The shell. A redirect (`>`, `>>`, `>|`), `tee` (up to a `<`, which feeds it
# instead), `sed`/`perl` in place, either file anywhere in `mv`, `rm`, `ln`,
# `link` or `cp -l` — a link to it is a second name to write it by — or as the
# last argument of `cp`, `install` or `truncate`. Reads pass, and so does the
# file as a copy's source. The path is matched without regard to case on both
# sides — on macOS `.Orrery/Config.json` is the same file — and the flags are
# not: for `sed` any `i` or `I` in a flag group is in place (BSD's `-I` is,
# and `-ie` is `-i` with the backup suffix `e`; sed has no other flag of either
# letter), while for `perl` the `i` must end the group, so `perl -Mstrict` and
# `perl -I lib` are reads. The shell side is not anchored on the left, so it
# also refuses `x.orrery/config.json`, which the edit side passes; erring that
# way costs a false refusal, not a write. Deleting `.orrery` or
# `.orrery/local` whole is refused with them, and so is a glob in the file name
# (`rm .orrery/local/*`); `find … -delete` and a glob in a directory segment
# (`.orrery/l*/calls.tsv`) are not. `call-log.sh --purge` empties the call log without naming it, and is the
# owner's (`--reconcile` is refused by `bash-guard.sh`). A spelling this misses
# passes, as everywhere here.
settings_msg="Orrery's settings and the records its gates read — .orrery/config.json,
.orrery/deny-declined.json and its older name .claude/orrery-deny.json, and what
sits in .orrery/local/ outside onboard's draft directories — are written by a
person or by Orrery's own hooks, never by a session: they switch gates off, or
are what the gates decide from. Say what you
would change and why, and let the owner write it. A skip the owner gave you in
words is recorded with: hooks/waiver.sh \"<act>\" \"<reason>\" stated — and if
that fails with Operation not permitted, quote the skip to the owner instead.
call-log.sh --purge and permissions-check.sh --reconcile are the owner's to run.
A test fixture is written from a test script, not from the command line."
# The names, each letter in either case: on the shell side the flags around them
# must keep their case, so the path cannot be matched with `grep -i`.
lit() { awk '{ o = ""; for (i = 1; i <= length($0); i++) { c = substr($0, i, 1); u = toupper(c); o = o (c != u ? "[" c u "]" : c) } printf "%s", o }' <<<"$1"; }
# `cfgpath` is the path alone and `cfg` the path with what may end it; the
# last-argument shape needs the first, since it reads its own ending — with both,
# `cp f .orrery/config.json; ls` had its `;` eaten by one and `ls` met by the
# other. A `.`/`..` segment anywhere after `.orrery/` or `.claude/` refuses the
# rest of the path. A draft directory under `onboard/` stays open, named with its
# trailing slash; bare, it cannot be told from `install-record.json`.
cfgpath="($(lit '\.orrery/+')($(lit '(local/+)?config\.json|deny-declined\.json')|$(lit 'local/+')[^/[:space:]\"${q};&|]+|$(lit 'local/+(sessions|doctor|work)/')[^[:space:]\"${q};&|]*)/*|$(lit '\.orrery/+local/+onboard/+')[^/[:space:]\"${q};&|]+|$(lit '\.orrery(/+local)?')/*|$(lit '\.claude/+orrery-deny\.json')/*|$(lit '\.(orrery|claude)/')([^[:space:];&|]*/)?\\.\\.?(/[^[:space:]\"${q};&|]*)?)"
cfg="${cfgpath}([\"${q}[:space:];&|)]|\$)"
target="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input" 2>/dev/null || true)"
if grep -qiE "(^|/)\\.orrery/+(local/+)?config\\.json(/.*)?\$|(^|/)\\.\\.?/(.*/)?config\\.json\$|(^|/)\\.orrery/+(deny-declined\\.json|local/+([^/]+|(sessions|doctor|work)/.*|onboard/+[^/]+))/*\$|(^|/)\\.orrery/(.*/)?\\.\\.?(/|\$)|(^|/)\\.claude/+orrery-deny\\.json/*\$|(^|/)\\.\\.?/(.*/)?orrery-deny\\.json\$" <<<"$target"; then deny "$settings_msg"; fi
if grep -qE "${pos}([a-z]*sh[[:space:]]+|(\\.|source)[[:space:]]+)?[^;&|[:space:]]*call-log\\.sh[^;&|]*[[:space:]][\"${q}]?--purge" <<<"$scan"; then deny "$settings_msg"; fi
if grep -qE ">[>|]?[[:space:]]*[\"${q}]?[^[:space:];&|]*${cfg}|${pos}tee\\b[^;&|<]*${cfg}|${pos}sed\\b[^;&|]*[[:space:]](-[A-Za-z]*[iI]|--in-place)[^;&|]*${cfg}|${pos}perl\\b[^;&|]*[[:space:]](-[A-Za-z]*i([^A-Za-z]|$)|--in-place)[^;&|]*${cfg}|${pos}(mv|rm|ln|link)\\b[^;&|]*${cfg}|${pos}cp\\b[^;&|]*[[:space:]](-[A-Za-z]*l|--link)[^;&|]*${cfg}|${pos}(cp|install|truncate)\\b[^;&|]*${cfgpath}[\"${q}]?[[:space:]]*($|[;&|)])" <<<"$scan"; then
  deny "$settings_msg"
fi

# --- a pull request is opened only after an auditor ran --------------------
# `build` held the only "auditor before commit", and told its reader to skip
# itself for small changes; `plan` said to implement at once with script gates
# only. So a change smaller than `build` reached `main` with nothing asking for
# an auditor, and one sharpen pass counted at least nine that did. Opening a pull
# request is the gated act rather than a commit: under a protected `main` it is
# where a change heads there, once per change — a commit gate refused every plan
# commit, every follow-up and every retry, each wanting a waiver the agent wrote
# for itself.
#
# Readable only where the project keeps a call log, because that is the only
# record of what this session spawned. It is on unless the project declared
# `"callLog": false`; switched off, or unreadable → pass through, per the
# header, and the text in `plan` and `build` carries it there.
#
# "Since the last one" comes from a state file this guard appends to whenever it
# lets `gh pr create` through, `.orrery/local/pr-gate.tsv` in the main checkout
# beside the log, ignored by its own `.gitignore`. It lived in git's common
# directory until Orrery's files moved into `.orrery/`; its rows come with it
# once. A row counts only if the call log holds `ran` for its id: a create that
# failed did not open anything, and must not consume the audit.
#
# What this proves is that an auditor was spawned, not that its verdict was
# read — a background spawn is `ran` the moment it launches.
# The work's record, missing from commit $1 — or the one the default branch
# already holds, an earlier work's met again under a reused branch or worktree
# name. It travels with the work and arrives on the default branch with the
# merge, which is the closing act. Where the project ignores `.orrery/work/`, on
# disk is all there can be.
record_missing() { # $1 = commit, $2 = the work's name (default: this tree's)
  local base last
  rec=".orrery/work/${2:-$(orrery_work "$dir")}/retrospective.md"
  base="$(git -C "$top" rev-parse -q --verify refs/remotes/origin/HEAD 2>/dev/null \
    || git -C "$top" rev-parse -q --verify main 2>/dev/null || true)"
  last="$(git -C "$top" log -1 --format=%H "$1" -- "$rec" 2>/dev/null || true)"
  { ! git -C "$top" cat-file -e "$1:$rec" 2>/dev/null \
    || { [ -n "$base" ] && [ -n "$last" ] && git -C "$top" merge-base --is-ancestor "$last" "$base"; }; } \
    && ! { git -C "$top" check-ignore -q "$rec" 2>/dev/null && [ -f "$top/$rec" ]; }
}
no_record() { # $1 = the act, $2 = where the record had to be
  deny "$1 is where the work heads for the default branch, and its record is not
committed: $rec is not in $2, or is the one the default branch already holds
from an earlier work of the same name.

Write it and commit it with the work:

  $here/../skills/build/record.sh write --what \"one line on what happened\"

It builds the spend table from this session's transcripts. Re-run it before a
later push and it refreshes. Work that ends without merging is closed with
record.sh close refused|withdrawn|answered|enacted instead.

If the owner told you in this session to skip the record, quote them:

  ORRERY_WAIVE=\"owner: <their words>\" $1 …"
}
# Whether this session spawned an auditor after $1. Reads $log, $fp.
audited() {
  awk -F'\t' -v fp="$fp" -v since="$1" '
        $2 == fp && $3 == "Agent" && ($4 == "auditor" || $4 ~ /:auditor$/) &&
        $6 == "ran" && $1 > since { found = 1 } END { exit !found }' "$log"
}
no_auditor() { # $1 = the act, $2 = since when
  deny "$1 is where a change heads for main, and no auditor has run in this
session since $2.

Spawn the auditor agent against the plan, or the change's stated intent, read
its verdict, and then run it again. This guard sees only that an auditor was
spawned — reading what it said is yours.

If the owner told you in this session to skip the audit, quote them:

  ORRERY_WAIVE=\"owner: <their words>\" $1 …

That is recorded in .orrery/local/waivers.tsv, which the next sharpen pass
reads. Your own judgement that this change needs no audit is not a reason it
accepts."
}
# Sets $log: the call log, or nothing where the project switched it off or has
# none yet. Read only once a gated act matched — every Bash call passes here.
read_log() {
  log=""
  if [ "$(orrery_config callLog true "$dir")" != false ]; then
    log="$(orrery_local_read calls.tsv "${ORRERY_CALL_LOG:-.claude/orrery-calls.tsv}" "$dir")"
  fi
  [ -r "$log" ] || log=""
}

# With a GitHub tracker the gated act is the pull request; without one, the
# first push of a branch, below. One gated act per mode, never two on one state.
pr="gh[[:space:]]+${ghflags}pr[[:space:]]+create\\b"
prmatch="$(grep -oE "${pos}${pr}" <<<"$scan" | head -1 || true)"
if [ -n "$prmatch" ] && [ "$(orrery_tracker "$dir")" = github ]; then
  top="$(orrery_toplevel "$dir")"; read_log
  # A waiver passes both halves, and is recorded before anything else — with the
  # call log switched off, the auditor half below never runs, and a waiver
  # recorded only there would pass unrecorded.
  waived=""
  if grep -q 'ORRERY_WAIVE=' <<<"$prmatch"; then waive "$prmatch" "gh pr create"; waived=1; fi
  if [ -n "$top" ] && [ -z "$waived" ] && record_missing HEAD; then no_record "gh pr create" HEAD; fi
  gitdir="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [ -n "$log" ] && [ -n "$gitdir" ]; then
    state="$(orrery_local_file pr-gate.tsv "$gitdir/orrery-pr-gate" "$dir" || true)"
    fp="$(fingerprint)"
    since=""
    [ ! -f "$state" ] || since="$(awk -F'\t' -v fp="$fp" '
      NR == FNR { if ($6 == "ran") ran[$7] = 1; next }
      $2 == fp && ($3 in ran) { s = $1 } END { print s }' "$log" "$state" 2>/dev/null || true)"
    if [ -z "$waived" ] && ! audited "$since"; then no_auditor "gh pr create" "its last pull request"; fi
    { printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$fp" \
        "$(jq -r '.tool_use_id // "-"' <<<"$input" 2>/dev/null || true)" >>"$state"; } 2>/dev/null || true
  fi
fi

# --- without a tracker, the first push of a branch ------------------------
# A project with no tracker opens no pull request through `gh`, so the moment a
# work leaves the machine is its branch's first push: no remote-tracking ref for
# it yet, a remote that is a URL, or `-u` given. The audit counts from the
# branch's first reflog entry, so no state file is kept. Later pushes pass — the
# same gap as commits pushed after an audit. Not gated, and stated as lacking:
# a push straight to the default branch. Read against the payload's tree even
# for `git -C <path> push`; a remote-tracking ref left after its branch was
# deleted on the remote reads as pushed; `push.default=upstream` naming another
# branch is read as the same name.
#
# Prints the first local branch this push sends for the first time. $1 = the
# push's own words, split on spaces with quoting not honoured.
first_push() {
  local w remote="" u=0 tags=0 skip=0 cur def src dst
  local -a words refs=()
  read -ra words <<<"$1 "
  # `${a[@]+…}`: bash 3.2 calls an empty array unbound under `set -u`.
  for w in ${words[@]+"${words[@]}"}; do
    # The value of an option that takes one separately is neither the remote nor
    # a refspec. `--repo <remote>` is not among them: its value is the remote.
    [ "$skip" = 0 ] || { skip=0; continue; }
    case "$w" in
      -o|--push-option|--receive-pack|--exec) skip=1 ;;
      -u|--set-upstream) u=1 ;;
      # `--tags` pushes tags in addition to any refspec named, and alone only tags.
      --tags) tags=1 ;;
      -d|--delete|--mirror) return 0 ;;
      --all|--branches) while IFS= read -r src; do refs+=("$src"); done \
          < <(git -C "$top" for-each-ref --format='%(refname:short)' refs/heads) ;;
      -*) ;;
      *) if [ -z "$remote" ]; then remote="$w"; else refs+=("$w"); fi ;;
    esac
  done
  cur="$(git -C "$top" symbolic-ref --short -q HEAD || true)"
  def="$(git -C "$top" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  def="${def#origin/}"; def="${def:-main}"
  [ -n "$remote" ] || remote="$(git -C "$top" config "branch.$cur.pushRemote" || git -C "$top" config remote.pushDefault \
    || git -C "$top" config "branch.$cur.remote" || echo origin)"
  [ "${#refs[@]}" -gt 0 ] || { [ "$tags" = 0 ] || return 0; refs=(HEAD); }
  for w in "${refs[@]}"; do
    w="${w#+}"; src="${w%%:*}"; dst="${w#*:}"
    [ "$src" != HEAD ] || src="$cur"
    [ "$dst" != HEAD ] || dst="$src"
    src="${src#refs/heads/}"
    case "$dst" in refs/heads/*) dst="${dst#refs/heads/}" ;; refs/*) continue ;; esac
    git -C "$top" show-ref -q --verify "refs/heads/$src" || continue
    [ "$dst" != "$def" ] || continue
    # A URL for a remote has no remote-tracking ref, so it reads as first too.
    if [ "$u" = 1 ] || ! git -C "$top" rev-parse -q --verify "refs/remotes/$remote/$dst" >/dev/null; then
      printf '%s' "$src"; return 0
    fi
  done
}
pushmatch="$(grep -oE "${pos}(rtk[[:space:]]+)?git[[:space:]]+${gitflags}push\\b[^;&|]*" <<<"$scan" | head -1 || true)"
if [ -n "$pushmatch" ] && [ "$(orrery_tracker "$dir")" = none ] \
   && top="$(orrery_toplevel "$dir")" && [ -n "$top" ]; then
  read_log
  # The words after the matched head: `push` can also sit in `-c push.default=…`
  # or in a `-C` path before it.
  head="$(grep -oE "${pos}(rtk[[:space:]]+)?git[[:space:]]+${gitflags}push\b" <<<"$pushmatch" | head -1 || true)"
  first="$(first_push "${pushmatch#"$head"}" || true)"
  if [ -n "$first" ]; then
    if grep -q 'ORRERY_WAIVE=' <<<"$pushmatch"; then waive "$pushmatch" "git push"; exit 0; fi
    # On the main checkout a branch is its own work, checked out or not.
    work=""
    [ "$top" != "$(orrery_main "$dir")" ] || work="${first//\//-}"
    if record_missing "refs/heads/$first" "$work"; then no_record "git push" "the pushed branch $first"; fi
    fp="$(fingerprint)"
    if [ -n "$log" ] && ! audited "$(orrery_born "$first" "$top")"; then
      no_auditor "git push" "branch $first began"
    fi
  fi
fi
