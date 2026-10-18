#!/usr/bin/env bash
# PreToolUse guard for the Bash tool. Two acts, each refused until its
# obligation is met: closing an issue that is not carrying its retrospective —
# the refusal names the command that does both — and, where the project keeps a
# call log, opening a pull request when no auditor has run in this session since
# its last one.
#
# The pull-request half does not reach: a pull request opened by a person, in
# the web UI, through `gh api`, or by a spelling its matcher misses; a heredoc
# fed to a shell (`bash <<EOF`), whose body runs although it is read as text; a
# host with no call log, where the text in `plan` and `build` is all there is;
# commits pushed to a pull request after its audit; and a merge that needs no
# pull request where a project allows one. It refuses falsely on a line of a
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
# ## What it actually enforces
#
# Measured over one week across three host projects: 179 issues closed, 218
# pull requests merged, 2 retrospectives. `build` step 9 has said to post one
# since long before that; `build` ran once in the week. A step inside a skill
# nobody invokes is not a mechanism, and this is the same finding the whole
# library keeps re-learning: what has a refusal behind it works, what relies on
# a session remembering does not.
#
# The refusal is unconditional rather than conditional on a comment existing.
# Checking would cost a network call inside a hook that runs before every Bash
# command, and it would be wrong the moment someone posts the wrong comment.
# Making the permitted path do both instead means there is nothing to verify.
#
# ## What this does not reach, stated rather than discovered later
#
# An issue closed by a merging pull request — `Closes #N` in the body, which is
# what `build` step 8 tells you to write — never passes through here. There is
# no Bash call to intercept: GitHub closes it server-side, after the merge, from
# an event this machine does not see. So the coverage is every close somebody
# types and no close a merge performs, and on a project that lands most work
# through pull requests that is the smaller half.
#
# The other half is a workflow in the host repository:
# `install/ci/retrospective-on-close.yml` reopens an issue that closed as
# finished work with no retrospective on it. For a long time this paragraph said
# that half was "filed as one" — it was not, and one host closed more than a
# hundred issues in a week through this gap, one with a retrospective. Do not read this guard as
# closing the gap; read it as closing the part a hook can reach, and copy the
# workflow for the rest.
#
# Exit contract: prints a permissionDecision JSON and exits 0 to deny; prints
# nothing and exits 0 to pass through.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"

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
# string matches nothing, and the `-n "$matched"` test three lines down exits 0
# — the same fail-open the probes assert, reached by one path instead of three.
# A line whose deletion changes no observable behaviour is a line that reads as
# a decision and is not one.
input="$(cat)"
cmd="$(jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null || true)"

# `gh issue close`, however it is spaced or flagged, but only where a command
# can actually start. An unanchored match would refuse `echo "gh issue close"`
# and — the case that arrived within an hour of writing this — a commit message
# describing the guard itself. A false refusal is what gets a hook deleted, and
# a deleted hook enforces nothing.
#
# A command position is the start, or after `;`, `&`, `|`, `then` or `do`,
# followed by any number of environment assignments. That last part is not
# decoration: the waiver below *is* an assignment prefix, so a pattern that
# stopped at the first `VAR=` would pass the waived form through without ever
# recording it — permitting exactly the case whose whole purpose is to leave a
# trace. The assignment's value has to allow quoted spaces for the same reason;
# a reason worth writing has spaces in it.
# **The argument after `close` must look like an issue.** A digit, a `#`, a
# variable or a quote — never a word and never `<N>`. That one character class
# is what separates a command from writing *about* the command, and it was
# added after a review reproduced two failures the previous anchor caused:
#
#   git commit -m "guard works; gh issue close is gated now"   → refused
#   cat > doc.md <<'EOF' … ORRERY_WAIVE="why" gh issue close <N> … EOF
#                                                              → recorded a row
#
# The second is the worse of the two: an invented row in the one file whose
# entire value is that its rows are true. The regex is quote-blind and cannot
# be made otherwise without parsing shell, so the fix is to require the shape
# of a real argument rather than to reason about where the text sits.
#
# The URL form is caught too, and its issue number is read from `issues/<n>`
# rather than from the first digits in the argument — see the extraction below
# for why that order is not a detail.
q="'"
assign="[A-Za-z_][A-Za-z0-9_]*=(\"[^\"]*\"|${q}[^${q}]*${q}|[^[:space:]]*)[[:space:]]+"
# `command`, `env` and a leading backslash are ordinary spellings rather than
# evasions, and each of them slipped past the first version. `gh -R owner/repo
# issue close` is not an evasion at all — it is what a session writes when it
# is being careful about which repository it is in.
pos="(^|[;&|(]|\\bthen\\b|\\bdo\\b|\\bif\\b)[[:space:]]*(${assign})*(command[[:space:]]+|env[[:space:]]+|\\\\)*"
ghflags="(-[^[:space:]]+([[:space:]]+[^-][^[:space:]]*)?[[:space:]]+)*"
# The whole argument token, not its first character. Stopping at one character
# made `matched` end at `close 4`, and the issue number read out of it was `4`
# for issue 42 — a row pointing at the wrong issue, which is worse than a row
# pointing at none.
#
# The class gained `h` and `{`. A URL is what a session reaches for after
# copying a link out of a browser — an ordinary spelling that closed an issue
# leaving no trace at all — and `{}` is xargs' placeholder. Both are narrow:
# `h` only matches where `ttps?://` follows, and `{` only as `{}`.
close="gh[[:space:]]+${ghflags}issue[[:space:]]+close[[:space:]]+([#0-9\$${q}\"][^[:space:]]*|https?://[^[:space:]]*|\\{\\})"
# `gh api` is gh's own documented way to close an issue and bypassed this
# entirely. Matched separately because it shares no words with the form above.
api="gh[[:space:]]+api\\b.*(state=closed|\"state\"[[:space:]]*:[[:space:]]*\"closed\")"
# A batch close through `xargs`, which is its own alternative rather than a
# prefix on the form above — **because with xargs there is no argument after
# `close` at all**, the numbers arrive on stdin. Requiring one caught only the
# spellings that happen to carry `{}`, and let the plainest form of all through:
#
#   echo 42 | xargs gh issue close
#
# That was a corpus written to the regex instead of to the spellings; a review
# found five bypasses here, including that one. The flag skip is `ghflags`,
# which already handles a value attached (`-n1`) or detached (`-n 1`, `-I {}`,
# `-P 4`, `-a list.txt`) — the previous xargs-specific one handled only the
# attached shape. A batch is where the gate matters most in aggregate and least
# per issue, so this is the alternative worth getting right.
xargsform="xargs[[:space:]]+${ghflags}gh[[:space:]]+${ghflags}issue[[:space:]]+close\\b"

# The whole matched segment, not the whole command. `grep -q` over `$cmd` said
# only *whether* something matched, so the waiver check below then searched the
# entire command for `ORRERY_WAIVE=` — which is how `ORRERY_WAIVE="x" echo hi;
# gh issue close 42` recorded a waiver that was never attached to the close.
# `|| true` because of `pipefail`: with no match, `grep` exits 1, the pipeline
# takes its status, the assignment fails and `set -e` ends the script right
# here — with status 1, on every Bash command in the session that is not a
# close. The harness reads a non-zero hook as a non-blocking error, so nothing
# broke visibly; the guard was simply erroring thousands of times a day, and
# the line below it was dead code. Found by the mutation pass the moment it
# stopped being able to kill mutants by their own location.
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
# rather than obeyed. Shared by both acts this guard gates, so the protections
# below hold for each: $1 is the matched segment, $2 the act as recorded.
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
  if ! record="$(ORRERY_WAIVE_SESSION="$(fingerprint)" \
        bash "$here/waiver.sh" "$2" "$reason" command 2>&1)"; then
    deny "The waiver could not be recorded, so the exemption is not granted.

$record

An unrecorded skip is the silence this gate exists to end — it cannot be handed
out on the strength of having tried."
  fi
}

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
# record of what this session spawned. No log, or one this cannot read → pass
# through, per the header; the text in `plan` and `build` carries it there.
#
# "Since the last one" comes from a state file this guard appends to whenever it
# lets `gh pr create` through, in git's common directory — outside every working
# tree, so `git add -A` never stages it and no host needs an ignore line. A row
# counts only if the call log holds `ran` for its id: a create that failed did
# not open anything, and must not consume the audit.
#
# What this proves is that an auditor was spawned, not that its verdict was
# read — a background spawn is `ran` the moment it launches.
pr="gh[[:space:]]+${ghflags}pr[[:space:]]+create\\b"
prmatch="$(grep -oE "${pos}${pr}" <<<"$scan" | head -1 || true)"
if [ -n "$prmatch" ]; then
  log="${ORRERY_CALL_LOG:-}"
  case "$log" in
    ''|/*) ;;
    *) if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then log="$CLAUDE_PROJECT_DIR/$log"; else log=""; fi ;;
  esac
  gitdir="$(git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [ -n "$log" ] && [ -r "$log" ] && [ -n "$gitdir" ]; then
    state="$gitdir/orrery-pr-gate"
    fp="$(fingerprint)"
    since=""
    [ ! -f "$state" ] || since="$(awk -F'\t' -v fp="$fp" '
      NR == FNR { if ($6 == "ran") ran[$7] = 1; next }
      $2 == fp && ($3 in ran) { s = $1 } END { print s }' "$log" "$state" 2>/dev/null || true)"
    if grep -q 'ORRERY_WAIVE=' <<<"$prmatch"; then
      waive "$prmatch" "gh pr create"
    elif ! awk -F'\t' -v fp="$fp" -v since="$since" '
        $2 == fp && $3 == "Agent" && ($4 == "auditor" || $4 ~ /:auditor$/) &&
        $6 == "ran" && $1 > since { found = 1 } END { exit !found }' "$log"; then
      deny "Opening a pull request is where a change heads for main, and no auditor has
run in this session since its last pull request.

Spawn the auditor agent against the plan, or the change's stated intent, read
its verdict, and then open the pull request. This guard sees only that an
auditor was spawned — reading what it said is yours.

If the owner told you in this session to skip the audit, quote them:

  ORRERY_WAIVE=\"owner: <their words>\" gh pr create …

That is recorded in .claude/orrery-waivers.tsv, which the next sharpen pass
reads. Your own judgement that this change needs no audit is not a reason it
accepts."
    fi
    { printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$fp" \
        "$(jq -r '.tool_use_id // "-"' <<<"$input" 2>/dev/null || true)" >>"$state"; } 2>/dev/null || true
  fi
fi

matched="$(grep -oE "${pos}(${close}|${api}|${xargsform})" <<<"$scan" | head -1 || true)"
[ -n "$matched" ] || exit 0

if grep -q 'ORRERY_WAIVE=' <<<"$matched"; then
  # The number, so a row can be reconciled against the issue it belongs to.
  # Without it every row read `gh issue close` and you could not go and look.
  # Trim to the argument first, then read from its start. A leading `.*` is
  # greedy, so `s/.*close *#\?\([0-9][0-9]*\).*/\1/` returned the LAST digit of
  # the number rather than the number.
  #
  # **A URL is tried first, and that order is the whole fix.** The general form
  # below stops at the first digit run anywhere in the argument, which inside a
  # URL is part of the host or the repository name: `.../o/web3-app/issues/42`
  # recorded `#3`, and `.../nyxene/orrery-v2/issues/306` recorded `#2`. The
  # `issues/` branch existed but sat behind `[ -n "$n" ] ||`, and the general
  # form always returns something for a URL — so it was unreachable, and
  # deleting it changed no output and left the corpus green. A row pointing at
  # the wrong issue is worse than a row pointing at none, in the one file whose
  # value is that its rows are true.
  tail="${matched##*close}"
  case "$tail" in
    *issues/*) n="$(sed -n 's|^.*issues/\([0-9][0-9]*\).*$|\1|p' <<<"$tail" | head -1)" ;;
    *)         n="" ;;
  esac
  [ -n "$n" ] || n="$(sed -n 's/^[[:space:]]*[^0-9#]*#\{0,1\}\([0-9][0-9]*\).*/\1/p' <<<"$tail" | head -1)"
  waive "$matched" "gh issue close${n:+ #$n}"
  exit 0
fi

deny "Closing an issue is where its retrospective is posted, and this command posts none.

Across three host projects in one week: 179 issues closed, 218 pull requests
merged, 2 retrospectives. Nobody decided to stop writing them — there was
simply nothing that noticed.

Use the path that does both:

  $here/../skills/build/close-issue.sh <N> --what \"one line on what happened\"

It builds the spend table from this session's own transcripts, posts it, and
then closes the issue. Add --since <iso8601> when this session already reported
on an earlier issue, or that issue's spend is counted here again.

Closing an umbrella is the other case: its retrospective is summed from the
children rather than measured from this session, so assemble it and pass it in.

  $here/../skills/build/close-issue.sh <N> --body-file <path>

If this issue really should close without one, say why and it is recorded:

  $here/../skills/build/close-issue.sh <N> --waive \"why\"

That posts the reason on the issue, where a project running
install/ci/retrospective-on-close.yml reads it, and writes it to
.claude/orrery-waivers.tsv. It is the supported way past this gate; there is no
quiet one. ORRERY_WAIVE=\"why\" gh issue close <N> records the row only — use it
where that workflow is not installed, or the server reopens what you excused."
