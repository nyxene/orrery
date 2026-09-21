#!/usr/bin/env bash
# PreToolUse guard for the Bash tool. Refuses to close an issue that is not
# carrying its retrospective, and names the command that does both.
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
# The other half needs a workflow in the host repository, which is a separate
# piece of work and is filed as one. Do not read this guard as closing the gap;
# read it as closing the part a hook can reach.
#
# Exit contract: prints a permissionDecision JSON and exits 0 to deny; prints
# nothing and exits 0 to pass through.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
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
matched="$(grep -oE "${pos}(${close}|${api}|${xargsform})" <<<"$cmd" | head -1 || true)"
[ -n "$matched" ] || exit 0

# The escape, and the record, are the same act. Without this line the gate has
# no supported way past it, and a gate with no supported way past it is removed
# rather than obeyed.
if grep -q 'ORRERY_WAIVE=' <<<"$matched"; then
  cmd="$matched"
  # Parameter expansion rather than sed, after the sed version accepted `""` as
  # a reason: the quoted branch returned empty, the unquoted fallback then
  # captured the two quote characters themselves, and an empty waiver was
  # recorded as a real one. The three cases are the three ways a shell value is
  # written, and each has to end at its own delimiter.
  rest="${cmd#*ORRERY_WAIVE=}"
  case "$rest" in
    '"'*) reason="${rest#\"}"; reason="${reason%%\"*}" ;;
    "'"*) reason="${rest#\'}"; reason="${reason%%\'*}" ;;
    *)    reason="${rest%% *}" ;;
  esac
  if [ -z "$reason" ]; then
    deny "ORRERY_WAIVE is set with no reason behind it.

A waiver with an empty reason records that something was skipped and not why,
which is the silence the waiver exists to end. Write the reason:

  ORRERY_WAIVE=\"owner said to skip it, we are mid-incident\" gh issue close <N>"
  fi
  session="$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null || true)"
  if [ -n "$session" ]; then
    if command -v shasum >/dev/null 2>&1; then
      session="$(printf '%s' "$session" | shasum -a 256 2>/dev/null | cut -c1-8 || true)"
    elif command -v sha256sum >/dev/null 2>&1; then
      session="$(printf '%s' "$session" | sha256sum 2>/dev/null | cut -c1-8 || true)"
    fi
  fi
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
  if ! record="$(ORRERY_WAIVE_SESSION="${session:-}" \
        bash "$here/waiver.sh" "gh issue close${n:+ #$n}" "$reason" command 2>&1)"; then
    deny "The waiver could not be recorded, so the exemption is not granted.

$record

An unrecorded skip is the silence this gate exists to end — it cannot be handed
out on the strength of having tried."
  fi
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

  ORRERY_WAIVE=\"why\" gh issue close <N>

That line is written to .claude/orrery-waivers.tsv with the issue number and
your reason. It is the supported way past this gate; there is no quiet one."
