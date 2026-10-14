#!/usr/bin/env bash
# PreToolUse guard for the Bash tool. Reads the proposed command from stdin
# (Claude Code hook JSON) and refuses it if it names a secret store or deletes
# outside the session scratchpad.
#
# **This is not a security boundary, and nothing here should be written as if it
# were.** It reasons about a string, and a string can be spelled another way:
# across every harness surveyed, the layer that keeps failing is the
# one that reasons about strings, and the layer that has not failed is the
# kernel. Thirty published advisories against Claude Code include eight pure
# pre-execution-matching bypasses, every one of them against a command on the
# *safe* list. Anthropic states the same thing in one clause about its own
# permission gate: it is a gate, not a sandbox.
#
# What this is instead: a nudge delivered at the one moment it can still change
# the outcome — before the command runs. It stops an accident, not an attacker,
# and the one thing that makes it worth keeping at all is that a hook's `deny`
# holds even in bypassPermissions mode, which no allow-list and no setting can
# say. Spend that on the few commands whose accident is unrecoverable, and
# nowhere else. Every additional check is another row in a future advisory
# table and another false refusal today.
#
# Against a malicious operator, a compromised plugin, or prompt injection in
# content the agent reads, this file does nothing at all — those need capability
# reduction, egress control and process isolation. Say so rather than implying
# otherwise; a nudge mistaken for a boundary is how the boundary never gets built.
#
# **A container is where this guard and the sandbox both end.** `docker exec` is
# unwrapped below like `sudo`, so the verb inside it is judged — but `docker run`
# with a bind mount is not, and cannot usefully be: the container path has to be
# mapped back to the host path to mean anything, and an image can delete on start
# with no command in the line at all. Both cases are `allow` entries in the
# corpus so the limit is a claim rather than a silence.
#
# What makes that worth saying here rather than only there: the sandbox does not
# cover it either. Seatbelt confines *this* process, and `docker` is a client
# handing work to a daemon that lives outside it — so the usual "the guard is a
# nudge, the kernel is the boundary" does not apply. Behind a container there is
# no second layer. Anyone reasoning about what happens when this file misses
# something should know that this is the one place where the answer is nothing.
#
# `hooks/cases.tsv` is the corpus that pins this file, and `hooks/bash-guard.test.sh` runs
# it. Change nothing here without running `hooks/bash-guard.test.sh --mutate` after: a
# mutation pass is what proves the corpus still holds the code, and this guard
# has now shipped two regressions that a corpus would have caught at the time.
#
# Exit contract: prints a permissionDecision JSON and exits 0 to deny;
# prints nothing and exits 0 to pass through (let normal permission flow decide).
set -euo pipefail

# An error anywhere below must refuse, not pass the command through.
#
# The harness reads a non-zero hook exit as a non-blocking error and runs the
# command anyway. So every failure this script did not anticipate — a `set -u`
# violation, a missing tool, a broken pipe — was an open door: the guard fell
# over and the command it never checked proceeded. The header above has always
# claimed the opposite, and only the `jq` branch made it true.
#
# Installed before anything else runs. The first version sat below the first
# jq call, so the parse failure it existed to catch happened while the trap
# did not yet exist.
#
# EXIT rather than ERR, because ERR does not fire on a `set -u` violation: that
# exits directly and would have walked straight past a trap that looked
# complete. Verified rather than assumed, after the ERR version was written.
#
# `printf` rather than `jq`, because jq may be exactly what is broken.
on_exit() {
  local rc=$?
  # An explicit `if`, not `[ ... ] && exit 0`: that form returns non-zero on a
  # non-zero rc, and `set -e` then kills the trap before it can refuse — which
  # is how the first version of this trap silently did nothing at all.
  if [ "$rc" -eq 0 ]; then exit 0; fi
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"The Bash guard failed while checking this command (exit %s), so it cannot say the command is safe. Refusing rather than passing it through. This is a defect in the guard — report it."}}\n' "$rc"
  exit 0
}
trap on_exit EXIT

input="$(cat)"

# A guard that cannot run must not fail open. Without jq every check below is
# skipped, the hook exits non-zero, and the harness treats that as a non-blocking
# error — so `rm -rf ~/dev` would simply proceed. Refusing everything is the only
# safe reading of "the guard is not working".
if ! command -v jq >/dev/null 2>&1; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"The Bash guard requires jq and cannot find it, so no command can be checked. Install jq before running anything through this shell."}}\n'
  exit 0
fi

cmd="$(jq -r '.tool_input.command // empty' <<<"$input")"
[ -z "$cmd" ] && exit 0

deny() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}


lower="$(tr '[:upper:]' '[:lower:]' <<<"$cmd")"
project_root="$(pwd -P)"
# The scratchpad prefix is the one path here that differs per OS — and after
# section 1b was retired it is the only thing in this file that reads `uname` at
# all.
#
# The `else` used to be every other platform, which meant that on one this guard
# does not model — a Windows shell, where the delete verbs, the profile
# variable and the temp root are all spelled differently — nothing matched and
# everything was allowed, while the plugin still reported as installed. That is
# the same condition as a missing `jq` above, and it had the opposite answer.
# Now it refuses, for the same reason and in the same shape.
case "$(uname)" in
  Darwin) scratchpad_root="/private/tmp/claude-$(id -u)" ;;
  Linux)  scratchpad_root="/tmp/claude-$(id -u)" ;;
  *)
    deny "The Bash guard does not model this platform ($(uname)), so it cannot say where the session scratchpad is or what a delete looks like here. Refusing rather than checking nothing: on an unmodelled platform every pattern in this file simply fails to match, which reads exactly like a command that was examined and found safe. Orrery supports macOS and Linux. To use it here, the platform has to be taught to this file — the scratchpad root, the delete verbs and the secret paths are what differ — or the hook removed deliberately, which is a decision rather than an accident."
    ;;
esac

# Splits a command into segments that each start with their own verb. Beyond the
# shell operators this also opens command substitutions: `echo $(rm -rf /usr)`
# has two verbs, and reading only the first one is how a destructive command
# hides behind a reader.
#
# Quote-aware, because the shell is. The previous version cut on every operator
# character wherever it appeared, including inside quoted strings — so
# `grep -cE "/System|/Library" f.json` became three segments and the second one's
# "verb" was `/Library`, a directory name read as a command nobody has listed.
# That produced four refusals of read-only commands in one session, each one
# inviting whoever hit it to route around the guard, which its own denial text
# names as the failure it exists to prevent.
#
# What is split is decided by what the shell would actually interpret, so this is
# narrower without being weaker:
#
#   * inside single quotes nothing is interpreted, so nothing splits;
#   * inside double quotes only `$(`, a backtick and a backslash are live — those
#     still split, because `echo "$(rm -rf /usr)"` really does run the deletion;
#   * outside quotes every operator splits, exactly as before.
#
# A destructive command hidden in a single-quoted string can only run through an
# interpreter, and both sections that care ask about interpreters separately and
# against the whole command rather than against these segments.
#
# The whole command is one record: quote state has to carry across newlines, or a
# heredoc body reopens the question on every line.
segments() {
  awk '{ buf = buf (NR > 1 ? "\n" : "") $0 } END {
    # Accumulated rather than read as one record. `RS = "\0"` was tried and is a
    # trap: awk sees an empty string there, an empty RS means paragraph mode, and
    # the input then splits on blank lines. Every multi-line command containing
    # one was segmented as several independent records with the quote and heredoc
    # state reset between them — which is how a commit message with a blank line
    # in it came back refused.
    n = length(buf); inS = 0; inD = 0; out = ""
    for (i = 1; i <= n; i++) {
      c = substr(buf, i, 1)
      nx = (i < n) ? substr(buf, i + 1, 1) : ""

      # Inside a heredoc body, first, because nothing else applies there. Quotes
      # are literal, parentheses are literal, and only an unquoted delimiter lets
      # a substitution through. Testing this after the other branches cost a
      # refusal: a commit message containing `fix(guard):` closed a substitution
      # that was still open, which split the body and put a word from the prose
      # at the head of a segment.
      if (hd != "") {
        if (c == "\n") {
          eol = index(substr(buf, i + 1), "\n")
          line = (eol > 0) ? substr(buf, i + 1, eol - 1) : substr(buf, i + 1)
          # `<<-` lets the terminator be indented with tabs, and bash strips them
          # before comparing. Not doing the same here left the heredoc open, and
          # an open heredoc swallows the rest of the command.
          bare = line
          if (hdash) { sub(/^\t+/, "", bare) }
          if (bare == hd) { hd = ""; i += length(line); out = out "\n"; continue }
          # Segments are read back a line at a time, so a newline separates them
          # whether or not anything split on it. The body is stdin for one
          # command: keep it on that same segment.
          out = out " "; continue
        }
        if (!hdq && c == "$" && nx == "(") { out = out "\n"; i++; continue }
        if (!hdq && c == "`")              { out = out "\n"; continue }
        out = out c
        continue
      }

      if (c == "\\" && !inS)            { out = out c nx; i++; continue }
      if (c == "\047" && !inD)          { inS = !inS; out = out c; continue }
      if (c == "\"" && !inS)            { inD = !inD; out = out c; continue }
      # ANSI-C quoting. Inside it a backslash escapes, including a backslash
      # before the closing quote — and the ordinary single-quote branch below
      # cannot see that, because it disables the escape branch while inS is set.
      # So `echo $(printf x)\047\134\047\047` inverted the quote state for the
      # rest of the command and everything after it stopped being segmented.
      if (!inS && !inD && c == "$" && nx == "\047") {
        j = i + 2
        while (j <= n) {
          ch = substr(buf, j, 1)
          if (ch == "\\") { j += 2; continue }
          if (ch == "\047") { j++; break }
          j++
        }
        i = j - 1
        continue
      }
      # Arithmetic, not a command substitution. `$((1<<n))` was opened as one and
      # its `<<` was then read as a heredoc whose delimiter never appears, which
      # swallowed the rest of the command. Consumed whole: nothing executable can
      # live in an arithmetic expression.
      if (!inS && c == "$" && nx == "(" && substr(buf, i + 2, 1) == "(") {
        j = i + 3; par = 2
        while (j <= n && par > 0) {
          ch = substr(buf, j, 1)
          if (ch == "(") par++
          else if (ch == ")") par--
          j++
        }
        i = j - 1
        continue
      }
      # A command substitution starts a fresh command context: the quotes around
      # it do not reach inside. Without saving and clearing the state here,
      # a heredoc opened inside one was still marked as inside double quotes,
      # the heredoc branch never fired, and the delimiter came back as a verb.
      if (!inS && c == "$" && nx == "(") {
        depth++; savedS[depth] = inS; savedD[depth] = inD
        inS = 0; inD = 0
        out = out "\n"; i++; continue
      }
      if (!inS && c == ")" && depth > 0) {
        inS = savedS[depth]; inD = savedD[depth]; depth--
        out = out "\n"; continue
      }
      if (!inS && c == "`")              { out = out "\n"; continue }
      # A heredoc: the delimiter is a word naming where the body ends, and the
      # body is data on stdin. Splitting `python3 - <<PY` on the two `<`s left
      # `PY` at the head of a segment and the guard refused a read-only command
      # for leading with a verb called `py`; splitting the body then did it again
      # for every line of it.
      #
      # The body follows double-quote rules — only `$(` and a backtick are live —
      # or, when the delimiter is itself quoted, no rules at all. Both are handled
      # by entering the matching state and leaving it at the line that is exactly
      # the delimiter, so whatever follows the heredoc is segmented normally again.
      # A herestring is not a heredoc: `<<<` has no body and no terminator. Read
      # as one it produced the delimiter `<`, which never appears on a line of
      # its own — so the heredoc stayed open and every command after it was
      # swallowed, section 1b and section 3b included. This guard uses `<<<`
      # itself on twenty lines; it is ordinary shell, not an evasion.
      if (!inS && !inD && c == "<" && nx == "<" && substr(buf, i + 2, 1) == "<") {
        out = out "\n"; i += 2; continue
      }
      if (!inS && !inD && c == "<" && nx == "<") {
        j = i + 2
        hdash = 0
        while (j <= n && substr(buf, j, 1) == "-") { hdash = 1; j++ }
        while (j <= n && substr(buf, j, 1) == " ") j++
        q = ""
        ch = substr(buf, j, 1)
        if (ch == "\047" || ch == "\"") { q = ch; j++ }
        hd = ""
        while (j <= n) {
          ch = substr(buf, j, 1)
          if (q != "" && ch == q) { j++; break }
          # `<` and `>` end a delimiter word too. Without them
          # `cat <<EOF>/dev/null` took the redirect into the delimiter, and the
          # terminator that followed matched nothing.
          if (q == "" && index(" \t\n;&|)<>", ch) > 0) break
          hd = hd ch; j++
        }
        hdq = (q == "\047")
        # The backstop for this whole class. A heredoc delimiter is a word; if
        # what was scanned is not one, this is not a heredoc and treating it as
        # one hides everything that follows. Four separate ways of getting here
        # were found by an audit after two of them shipped, and each cost the
        # guard its sight for the rest of the command. Anything unrecognised now
        # falls through to the redirect branch, which splits and sees.
        if (hd !~ /^[A-Za-z_][A-Za-z0-9_]*$/) {
          hd = ""; out = out "\n"; i++; continue
        }
        # And the terminator has to actually be there. Entering body mode on a
        # heredoc that never closes hides everything after it from the sections
        # that matter, which is the single consequence every defect in this class
        # had. Checked by looking rather than by hoping.
        rest = substr(buf, j)
        m = split(rest, L, "\n")
        found = 0
        for (t = 1; t <= m; t++) {
          b2 = L[t]
          if (hdash) { sub(/^\t+/, "", b2) }
          if (b2 == hd) { found = 1; break }
        }
        if (!found) { hd = ""; out = out "\n"; i++; continue }
        i = j - 1
        # The `<<` stays in the segment and the body stays with it, so the
        # command keeps its own verb at the head and the sections below can still
        # see that a heredoc is present — which is how inline interpreter code
        # delivered this way is recognised as code rather than as stdin data.
        out = out "<<"
        continue
      }
      # (The heredoc-body branch is handled first, at the top of the loop.)
      # A redirect splits wherever it appears, quoted or not: what follows it is
      # a filename, and reading that filename as a verb refused
      # `cat >> hooks/cases.tsv` for leading with a verb called cases.tsv.
      #
      # Those targets used to be marked with \001 so section 1b could judge them
      # as paths rather than verbs. Section 1b is gone, and section 3b only ever
      # stripped the marker again, so it went with it.
      #
      # No apostrophe may appear anywhere in this awk program. One in a comment
      # ends the single-quoted argument, turns the rest into shell words, and the
      # guard stops parsing — which took every Bash call down until it was found.
      if (c == "<" || c == ">") { out = out "\n"; continue }
      if (!inS && !inD && index("(){};&|", c) > 0) { out = out "\n"; continue }
      # A newline separates segments in this output, so one that survives inside
      # a segment splits it later: both readers take segments back with `read -r`
      # a line at a time, and a segment containing a newline is indistinguishable
      # from two segments. Outside quotes that is right — the shell ends a command
      # there too. Inside quotes it is text, and it made the guard refuse its own
      # documentation: a multi-line commit message or issue body quoting a command
      # had that line judged as if it were about to run. Four refusals in one
      # session, three of them blamed on the wrong rule.
      #
      # A space, not a marker: what the sections downstream want from a segment is
      # its verb and its paths, and neither changes when the line breaks become
      # spaces. The separator is what must not occur in the data, and now it does
      # not.
      if (c == "\n") { out = out (inS || inD ? " " : "\n"); continue }
      out = out c
    }
    print out
  }' <<<"$1"
}

# Collapses `.` and `..` in an absolute path without asking the filesystem, so
# a path whose directory does not exist can still be compared against a prefix.
# Used only when physical resolution is impossible; symlinks stay a physical
# question and keep the physical answer wherever the directory is really there.
normalize() {
  local out="" seg
  local -a segs
  IFS=/ read -ra segs <<<"$1"
  for seg in "${segs[@]}"; do
    case "$seg" in
      ''|.) ;;
      ..) out="${out%/*}" ;;
      *) out="$out/$seg" ;;
    esac
  done
  printf '%s' "${out:-/}"
}

# The verb a segment actually runs. Leading variable assignments and exec
# wrappers are stripped rather than trusted — `env`, `command`, `sudo` and
# `xargs` all run something else, so judging them as the verb judges nothing.
verb_of() {
  awk '{
    skip = 0
    for (i = 1; i <= NF; i++) {
      t = $i
      # Assignment first, basename second. The other order stripped the
      # directory off `dir=/some/path/scratchpad` and left `scratchpad`, which no
      # longer looks like an assignment — so every variable holding a path became
      # a command nobody had listed, and section 1b refused read-only work for
      # leading with it. The line below was always meant to skip assignments; it
      # only ever saw the ones whose value had no slash in it.
      if (t ~ /^[a-z_][a-z0-9_]*=/) continue
      # Quoting and escaping are how bash spells the same verb, and this compared
      # the raw token: `rm -rf ~/dev` was refused while `\rm -rf ~/dev` was not,
      # and neither were the quoted forms — a backslash is what people type to
      # step around an `rm -i` alias, so this was one keystroke from the whole
      # delete boundary. Bash removes these before deciding what to run; so does
      # this now, and for the same reason. (No apostrophe below: \047 is one.)
      gsub(/\\/, "", t)
      gsub(/\042/, "", t)
      gsub(/\047/, "", t)
      # A parameter expansion inside the word hides the verb from a splitter that
      # only knows whitespace: `rm${IFS}-rf${IFS}~/dev` is a single token whose
      # basename was `dev`. What runs is whatever precedes the first expansion,
      # so that is what gets read. When nothing precedes it — `$r -rf ~/dev` —
      # the prefix is empty and this falls through to the checks below, which is
      # correct: the verb is genuinely unknown until the shell expands it, and
      # that case stays a written-down limit rather than a silent pass.
      if (t ~ /\$/) sub(/\$.*/, "", t)
      sub(".*/", "", t)
      # Punctuation is not a command. A closing quote left over from a command
      # substitution arrived here as the verb `"` and was refused for not being
      # on the reader list. Anything executable has a letter or a digit in it.
      if (t !~ /[a-zA-Z0-9]/) continue
      # The *value* of a wrapper flag is not a verb either, and reading it as one
      # reads no verb at all: `sudo -u root rm -rf ~/dev` was judged on the word
      # `root` and passed. `-u` and `-g` always take a value (`sudo -u`, `env -u`);
      # `-n` does not always (`sudo -n` is non-interactive), so its value is
      # recognised by being a number rather than by the flag before it.
      if (t ~ /^-[ug]$/) { skip = 1; continue }
      if (t ~ /^-/) continue
      if (skip) { skip = 0; continue }
      if (t ~ /^[0-9]+$/) continue
      # A container runner is a wrapper like the ones below, with one extra word
      # to step over. Reported by a host project after its own hook was walked
      # around this way, and it is the same defect as the quoting one: what bash
      # runs and what this reads had drifted apart. `rm -rf ~/dev` was refused
      # while `docker exec pg rm -rf ~/dev` was not, and every rule in the file
      # went with it — not the delete boundary alone.
      #
      # Ahead of the wrapper list on purpose. `exec` is already a wrapper there,
      # so with this below it the container branch was unreachable: the plain
      # `exec` arm consumed the word, the marker was never set, and the verb came
      # back as the container name.
      #
      # Only `exec` here. `docker run` puts flags, their values and an image name
      # before the command, so finding the verb there means parsing the flag
      # grammar, and a bind mount moves the target outside every path check
      # anyway. That is a different fix and is filed as one, rather than being
      # half-done under cover of this line.
      # A package manager running a command is the same wrapper shape, found in
      # the same report: `pnpm exec rm -rf ~` walked past everything, exactly as
      # the container form did. One difference decides the code — after
      # `docker exec` comes a container name, after `pnpm exec` comes the command
      # itself — so this cannot reuse the skip-one-word branch below.
      #
      # The manager is held rather than consumed, because only the next word says
      # whether it is wrapping anything. `npm run build` must still read as `npm`,
      # and it would have become `run` if the name were dropped on sight.
      #
      # `dlx` and `npx <pkg>` are deliberately not here: what they run is a
      # package whose behaviour is not in the command line, which is the limit
      # already written down for `docker run <image>`. Corpus says so.
      if (pmpending) {
        pmpending = 0
        if (t == "exec") continue
        print pmname; exit
      }
      if (t == "pnpm" || t == "yarn" || t == "npm") { pmpending = 1; pmname = t; continue }
      if (t == "docker" || t == "podman" || t == "nerdctl" || t == "kubectl") { ctr = 1; continue }
      if (ctr && t == "compose") continue
      if (ctr && t == "exec") { ctrexec = 1; continue }
      # The container or pod name. Only skipped once, and only after `exec`, so
      # `docker ps` still reads as `ps` rather than vanishing.
      if (ctrexec) { ctrexec = 0; ctr = 0; continue }
      # `source` is the same builtin as `.`, and the two spellings had different
      # verdicts for months. `.` has no letter in it, so the punctuation line
      # above drops it and the script lands in the verb position; `source` is a
      # word nobody had listed, so it *was* the verb and every rule judged at the
      # verb stopped at it. That is not a second wrapper list — it is this one,
      # missing the half of a builtin that happens to be spelled with letters.
      if (t == "env" || t == "command" || t == "sudo" || t == "doas" ||
          t == "nohup" || t == "time" || t == "nice" || t == "ionice" ||
          t == "exec" || t == "builtin" || t == "source" ||
          t == "xargs" || t == "stdbuf" ||
          t == "then" || t == "do" || t == "else") continue
      # Shell keywords are syntax, not commands. `then`, `do` and `else` were
      # here from the start and the rest were not, so a loop or a conditional put
      # `for` or `while` at the head of a segment and section 1b refused a
      # read-only command for leading with a verb nobody had listed. Whatever the
      # keyword introduces is still read: `segments` cuts on `;`, so the body has
      # its own segment with its own verb.
      # `for` and `select` are followed by the name of the loop variable, which
      # is no more a command than the keyword is. Same mechanism as the wrapper
      # flags above: mark the next token to be skipped.
      #
      # No apostrophe may appear anywhere in this awk program — it ends the
      # single-quoted argument and the rest becomes shell words.
      if (t == "for" || t == "select") { skip = 1; continue }
      # After `in` comes a word list, not a command: every item of
      # `for f in /usr/lib/x /usr/lib/y` was being read as a verb, and the first
      # one refused the loop. Stop reading this segment — anything executable in
      # that list arrives through a substitution, which is its own segment.
      if (t == "in") exit
      if (t == "while" || t == "until" || t == "if" ||
          t == "elif" || t == "fi" || t == "case" || t == "esac" ||
          t == "function" || t == "done" ||
          t == "coproc" || t == "[" || t == "[[" || t == "]" || t == "]]" ||
          t == "!") continue
      print t
      exit
    }
  }' <<<"$1"
}

# An interpreter handed a file reads it; an interpreter handed inline code can do
# anything, so the two are judged apart rather than the name being trusted. Only
# section 3b asks this now; sections 1b and 3b used to carry a copy of the list
# each — two sources for one contract, kept in step by nothing but attention.
# `npx` takes `-c`, which is inline shell exactly like `sh -c`, so it belongs on
# this list for the same reason `sh` does. The wrapper forms — `pnpm exec` and
# its neighbours — are handled in verb_of instead, because there the command is
# a word in the line rather than a string to be read.
interpreters='node|python|python2|python3|ruby|perl|php|osascript|bash|sh|zsh|deno|bun|npx'

# --- 1. Machine config and credential stores ------------------------------
#
# **Sections 1 and 2 look redundant and are not.** Where a filesystem sandbox is
# switched on, every probe below is already refused by the kernel, from a layer
# no string can be spelled around — so reading this file there, the obvious
# conclusion is that these two sections duplicate the platform and should go.
#
# They do not duplicate it anywhere the sandbox is off, which is the default and
# is where most installs run. There, an inline interpreter reading a private key
# is matched by nothing else: not by the deny rules, which match a command's
# shape rather than what it opens, and not by section 3, which is about
# deletion. These sections are the only thing standing between the two.
#
# Deleting them on duplication grounds turns no test in this repository red. The
# corpus asserts the refusal, and the refusal still happens — from a layer the
# consumer does not have.

# Refusing rather than letting the clock decide, and ahead of every section that
# walks segments, which since sections 1 and 2 do is all of them. Every segment
# costs a few processes — `verb_of` is an awk, and greps follow it — so the cost
# is mostly per segment: 3 KB carrying 500 substitutions took 23s. Not only,
# though, which this comment said for months: macOS awk walks a string by
# `substr`, which costs per byte, so a single flat 200 KB command takes about
# 18 s here before this change and 21 s after it, and passes the timeout with no
# segment cap to stop it. That limit is not closed by this one. The hook's timeout is 15 seconds,
# and a guard killed by SIGTERM runs neither its checks nor its EXIT trap, so
# above roughly 300 segments every rule in this file silently stopped applying.
#
# 100 is two orders of magnitude above real work — `ls -la` is one segment, a
# pipeline with a substitution is four, the largest thing measured here was six.
# It is not an order of magnitude inside the timeout, which this comment claimed
# until it was measured: 99 flat segments take 2 to 5 s on the machine this is
# developed on, depending on load, and about 10% more when a protected name sends
# sections 1 and 2 into their per-segment walk — up to a third of the 15 s
# budget, and an audit saw 14 s for a heavier draft under load. Lower this before adding per-segment
# work, and re-measure with the walk triggered. A command past it is a
# generated payload, and the answer to one is to refuse and let a person split
# it, not to check half of it and report success.
MAX_SEGMENTS=100
seg_count="$(segments "$cmd" | grep -c . || true)"
if [ "${seg_count:-0}" -gt "$MAX_SEGMENTS" ]; then
  deny "This command holds $seg_count separate segments and the guard checks at most $MAX_SEGMENTS. Past that it cannot finish inside its own timeout, and a guard that runs out of time does not deny — it stops applying entirely. Split the command, or write it to a script and run that."
fi

# Where a path is judged: the words a command is handed, never its text.
#
# Sections 1 and 2 used to grep the whole command line for a protected name, so
# a name refused the command wherever it stood — as the file `cat` is about to
# open, and equally as a word in a commit message, an issue body, a `sed`
# expression or a source file being written through a heredoc. Sections 3a and
# 3a-bis had that defect first and were narrowed to what executes; these were
# the last whole-text matchers left. What it cost was not only the refusals: a
# host project agent refused for adding two of these names to a deny list in
# its own source moved the same edit into a script file, which this guard does
# not read, and ran that. A false refusal is what teaches the walk-around.
#
# So a name is judged in one of two ways.
#
#   * As a word. The whole command is lexed into the words the shell hands
#     over, quotes removed, and a word is refused only when it *is* the path:
#     the whole word, after an optional `NAME=` or `--flag=`. `$(…)` and
#     backticks are lexed as commands of their own, inside double quotes too,
#     and a redirect target is a word of its own. A heredoc body is not read
#     here, though words after its delimiter on the same line are.
#
#     Lexed from the command rather than from `segments`, on purpose. The
#     segmenter splits inside quotes at `<`, `>`, `$(` and backticks, which is
#     right for finding verbs and wrong for finding words: a segment that starts
#     with the tail of a quoted string opens a quote that never closes, and the
#     path after it disappears into it. `grep KEY "$(pwd)" .env` was allowed
#     that way in the first draft of this change, which an audit caught.
#
#   * As text, for code that has no words to read. Inline interpreter code —
#     an inline-code flag, a heredoc or herestring to an interpreter, `eval`, an
#     `awk` program — and an interpreter handed no file, which reads its code
#     from stdin (`echo … | bash`). An inline read of a private key is the case
#     the section-1 note below says nothing else catches, so the name is matched
#     loosely there, as it always was. That keeps one false refusal on purpose:
#     inline code that only *writes* a name is refused too, and its denial says
#     to put that text into a file with the Edit or Write tool instead.
#
# The silence this trades for: a name that reaches a command some other way than
# as a word — assembled from variables, or read from a file — exactly as before.
command_words() {
  awk '
  # Lowercased here, on the way out, and not before lexing: `\U` and `\u` are
  # different escapes, and so are a heredoc delimiter and its lowercase.
  function emit() { if (inw) { gsub(/\n/, " ", w); print tolower(w) } w = ""; inw = 0 }
  # Is the line after position p the terminator of queued heredoc k? Sets tlen
  # to the length of that line, so the caller can step over it.
  function is_term(p, k,    e, line) {
    e = index(substr(buf, p + 1), "\n")
    line = (e > 0) ? substr(buf, p + 1, e - 1) : substr(buf, p + 1)
    tlen = length(line)
    if (hdd[k]) sub(/^\t+/, "", line)
    return line == hd[k]
  }
  function has_term(p, k,    rest, m, t, b2) {
    rest = substr(buf, p + 1); m = split(rest, L, "\n")
    for (t = 1; t <= m; t++) { b2 = L[t]; if (hdd[k]) sub(/^\t+/, "", b2); if (b2 == hd[k]) return 1 }
    return 0
  }
  # Enter the next queued body at position p (a newline). A quoted delimiter
  # makes the body pure data: skipped. An unquoted one expands `$(…)` and
  # backticks, so the body is walked in heredoc mode, where only those open a
  # command. One that never closes is neither: hiding the rest of the command
  # is worse than reading it.
  function next_body(p,    len) {
    while (cur <= hdn) {
      if (!has_term(p, cur)) { cur++; continue }
      # An empty unquoted body: its terminator is the very next line, which the
      # walk below only tests after a newline it has not reached yet. Missing
      # that held heredoc mode open over the commands that followed, and bash
      # runs them. Found by the third audit of this change.
      if (!hdq[cur] && is_term(p, cur)) { p += tlen + 1; cur++; continue }
      if (!hdq[cur]) { inH = 1; return p }
      len = 0
      while (!is_term(p + len, cur)) { e2 = index(substr(buf, p + len + 1), "\n"); len += e2 }
      p += len + tlen + 1; cur++
    }
    inH = 0; hdn = bs[depth]; cur = hdn + 1
    return p
  }
  { buf = buf (NR > 1 ? "\n" : "") $0 }
  END {
    n = length(buf); w = ""; inw = 0; inS = 0; inD = 0; inH = 0; depth = 0; hdn = 0; cur = 1; bs[0] = 0
    for (i = 1; i <= n; i++) {
      c = substr(buf, i, 1); nx = (i < n) ? substr(buf, i + 1, 1) : ""
      if (inS) { if (c == "\047") inS = 0; else w = w c; continue }
      # Inside double quotes a backslash escapes only what bash says it does.
      # Escaping everything turned `rg "\.env" src`, a search, into the bare
      # name, and the first version of this lexer refused it.
      if (c == "\\" && i < n) {
        i++; ch = substr(buf, i, 1)
        if (inH) continue
        if (inD && index("$`\042\\\n", ch) == 0) { w = w c ch; continue }
        if (ch != "\n") { w = w ch; inw = 1 }
        continue
      }
      # A substitution is a command of its own — inside double quotes, inside
      # an unquoted heredoc body, inside `$((…))` and inside `${…}`, because
      # bash runs it in all four. The word around it is set aside and resumed
      # when it closes. Arithmetic is not skipped: `$((` opens a substitution
      # here, its second `(` is a separator, its operands are words, and a `<<`
      # inside it is a shift rather than a heredoc.
      if (c == "$" && nx == "(") {
        depth++; sw[depth] = w; si[depth] = inw; sd[depth] = inD; sh[depth] = inH
        ar[depth] = (substr(buf, i + 2, 1) == "("); bk[depth] = 0
        # Heredocs queue per substitution. One opened inside `$(…)` inside an
        # unquoted body must not send the walk back into the outer body, which
        # skipped every command between the two terminators.
        sc[depth] = cur; bs[depth] = hdn; cur = hdn + 1
        w = ""; inw = 0; inD = 0; inH = 0; i++; continue
      }
      # A backtick is the same substitution with a different closer, so it takes
      # the same stack — heredoc queue included.
      if (c == "`" && depth > 0 && bk[depth]) {
        emit(); w = sw[depth]; inw = si[depth]; inD = sd[depth]; inH = sh[depth]; hdn = bs[depth]; cur = sc[depth]; depth--; continue
      }
      if (c == "`") {
        depth++; sw[depth] = w; si[depth] = inw; sd[depth] = inD; sh[depth] = inH
        ar[depth] = 0; bk[depth] = 1; sc[depth] = cur; bs[depth] = hdn; cur = hdn + 1
        w = ""; inw = 0; inD = 0; inH = 0; continue
      }
      if (c == ")" && depth > 0 && !bk[depth] && !inD && !inH) { emit(); w = sw[depth]; inw = si[depth]; inD = sd[depth]; inH = sh[depth]; hdn = bs[depth]; cur = sc[depth]; depth--; continue }
      if (inH) {
        if (c == "\n" && is_term(i, cur)) { i += tlen + 1; cur++; i = next_body(i) }
        continue
      }
      if (inD) { if (c == "\042") inD = 0; else w = w c; continue }
      # ANSI-C quoting, decoded, because it is how a name is spelled without
      # its letters: an audit of this change found a dollar-quoted dot passing
      # here after the old whole-text match had refused it. `\u` and `\U` are
      # decoded below 128, which is every character a protected name uses.
      if (c == "$" && nx == "\047") {
        j = i + 2; inw = 1
        while (j <= n) {
          ch = substr(buf, j, 1)
          if (ch == "\047") break
          if (ch == "\\" && j < n) {
            j++; e = substr(buf, j, 1)
            if (e == "x" || e == "u" || e == "U") {
              lim = (e == "x") ? 2 : (e == "u") ? 4 : 8
              h = ""; while (length(h) < lim && index("0123456789abcdefABCDEF", substr(buf, j + 1, 1)) > 0) { j++; h = h substr(buf, j, 1) }
              v = 0; for (k = 1; k <= length(h); k++) v = v * 16 + index("0123456789abcdef", tolower(substr(h, k, 1))) - 1
              w = w ((v > 0 && v < 128) ? sprintf("%c", v) : "?")
            } else if (e ~ /[0-7]/) {
              v = e + 0; for (k = 0; k < 2 && substr(buf, j + 1, 1) ~ /[0-7]/; k++) { j++; v = v * 8 + substr(buf, j, 1) }
              w = w sprintf("%c", v)
            } else if (e == "n") w = w "\n"
            else if (e == "t") w = w "\t"
            else w = w e
            j++; continue
          }
          w = w ch; j++
        }
        i = j; continue
      }
      if (c == "\047") { inS = 1; inw = 1; continue }
      if (c == "\042") { inD = 1; inw = 1; continue }
      # `${HOME}` is one word. The segmenter splits on braces; this must not.
      # Only a plain name is taken whole: `${X:-$(cmd)}` runs `cmd`, so any
      # other expansion is lexed through and its substitution is seen.
      if (c == "$" && nx == "{") {
        j = index(substr(buf, i), "}")
        if (j > 0 && substr(buf, i, j) ~ /^\$\{[A-Za-z_][A-Za-z0-9_]*\}$/) { w = w substr(buf, i, j); inw = 1; i += j - 1; continue }
      }
      # A heredoc: its delimiter is queued and its body entered at the next
      # newline, so words after the delimiter on this line are still read —
      # `cat <<EOF .env` reads the file and ignores stdin. A herestring is not
      # one: `<<<` falls through to the separator branch below.
      if (c == "<" && nx == "<" && substr(buf, i + 2, 1) != "<" && !ar[depth]) {
        emit(); j = i + 2; dash = 0
        while (j <= n && substr(buf, j, 1) == "-") { dash = 1; j++ }
        while (j <= n && substr(buf, j, 1) == " ") j++
        q = substr(buf, j, 1); if (q == "\047" || q == "\042") j++; else q = ""
        # `<<\EOF` quotes the delimiter as surely as `<<'EOF'` does.
        bq = 0; if (q == "" && substr(buf, j, 1) == "\\") { bq = 1; j++ }
        d = ""
        while (j <= n) {
          ch = substr(buf, j, 1)
          if (q != "" && ch == q) { j++; break }
          if (q == "" && index(" \t\n;&|)<>", ch) > 0) break
          d = d ch; j++
        }
        if (d ~ /^[A-Za-z_][A-Za-z0-9_]*$/) { hdn++; hd[hdn] = d; hdd[hdn] = dash; hdq[hdn] = (q != "" || bq) }
        i = j - 1; continue
      }
      if (c == "\n") {
        emit()
        if (hdn >= cur) i = next_body(i)
        continue
      }
      # A comment is not lexed: `#` starting a word runs to the end of the line.
      if (c == "#" && !inw) { while (i < n && substr(buf, i + 1, 1) != "\n") i++; continue }
      if (index(" \t;&|()<>", c) > 0) { emit(); continue }
      w = w c; inw = 1
    }
    emit()
  }' <<<"$1"
}

# Words that consume the rest of a command as code. `-c`, `-e` and `-E` are the
# common ones; `-p` (node, bun, perl), `-r` (php) and the long and subcommand
# spellings were missed by the first draft of this change, which an audit
# caught: each was refused before it and allowed after. Short bundles only, up
# to three letters, so a long single-dash flag such as `-Werror` is not one.
inline_flag='(^|[[:space:]])(-[a-z]?[a-z]?[cepr]|--eval|--print|--command|eval)([[:space:]"'"'"'=]|$)'

# The three protected classes, as whole words. Lowercase throughout, because the
# filesystem this runs on is case-insensitive — see the note on section 1 below.
word_prefix='^(-{0,2}[a-z0-9_-]+=)?'
etc_word="${word_prefix}"'(/etc|/private/etc|/private/var/root|/var/root|/var/db)(/.*)?$'
home_word="${word_prefix}"'(~|\$home|\$\{home\})/(\.(ssh|aws|gnupg|kube|docker|npmrc|netrc|git-credentials)|library/(keychains|cookies|messages|mail|safari|accounts|suggestions|autosave information))(/.*)?$'
secret_word="${word_prefix}"'(.*/)?(\.env(\.[a-z0-9_-]+)?|credentials\.json|id_rsa|id_ed25519|id_ecdsa|\.pem|\.p12|\.pfx|\.jks|\.keystore|\.npmrc|\.netrc|\.git-credentials)$'
# The example files a project commits on purpose. Exempt one at a time: the old
# test exempted a whole command when any of them appeared anywhere in it, so
# `cat .env .env.example` passed.
example_word='(^|/|=)\.env\.(example|sample|template)$'

# And the same three, loosely, for code.
etc_text='(^|[[:space:]"'"'"'=])(/etc|/private/etc|/private/var/root|/var/root|/var/db)(/|[[:space:]"'"'"']|$)'
home_text='(^|[[:space:]"'"'"'=])(~|\$home|\$\{home\})/(\.(ssh|aws|gnupg|kube|docker|npmrc|netrc|git-credentials)|library/(keychains|cookies|messages|mail|safari|accounts|suggestions|autosave information))([/[:space:]"'"'"']|$)'
secret_text='(^|[/[:space:]"'"'"'])((\.env(\.[a-z0-9_-]+)?)|credentials\.json|id_rsa|id_ed25519|id_ecdsa|\.pem|\.p12|\.pfx|\.jks|\.keystore|\.npmrc|\.netrc|\.git-credentials)([/[:space:]"'"'"']|$)'
example_text='\.env\.(example|sample|template)([/[:space:]"'"'"']|$)'

etc_hit=""; home_hit=""; secret_hit=""; inline_hit=""

words="$(command_words "$cmd")"
grep -qxE "$etc_word" <<<"$words" && etc_hit=yes
grep -qxE "$home_word" <<<"$words" && home_hit=yes
grep -xE "$secret_word" <<<"$words" | grep -qvE "$example_word" && secret_hit=yes

# The code path costs a process or two per segment, so it runs only when a
# protected name appears in the command at all — which almost no command does.
stripped="$(sed -E "s#$example_text# #g" <<<"$lower")"
if grep -qE "$etc_text|$home_text|$secret_text" <<<"$stripped"; then
  while IFS= read -r seg; do
    [ -z "${seg// /}" ] && continue
    v="$(verb_of "$seg")"
    code=""
    # The code is read from the whole command, not from this segment: the
    # segmenter splits inside quotes at `<` and `>`, so `getline < "x"` in an
    # awk program, or a comparison in inline Python, leaves the rest of the
    # program in a segment of its own.
    case "$v" in
      eval|awk|gawk|mawk|nawk) code="$lower" ;;
    esac
    if [ -z "$code" ] && grep -qxE "$interpreters" <<<"$v"; then
      if grep -qE "$inline_flag" <<<"$seg" || grep -q '<<' <<<"$seg"; then
        code="$lower"
      # Handed no file, an interpreter reads its code from stdin — a pipe or a
      # herestring, which the segmenter puts in a segment of its own.
      elif ! awk -v v="$v" '{
          for (i = 1; i <= NF; i++) {
            t = $i; gsub(/[\042\047]/, "", t); sub(".*/", "", t)
            if (seen && t != "" && t !~ /^-/) found = 1
            if (t == v) seen = 1
          }
        } END { exit !found }' <<<"$seg"; then
        code="$lower"
      fi
    fi
    [ -n "$code" ] || continue
    text="$(sed -E "s#$example_text# #g" <<<"$code")"
    grep -qE "$etc_text" <<<"$text" && { etc_hit=yes; inline_hit=yes; }
    grep -qE "$home_text" <<<"$text" && { home_hit=yes; inline_hit=yes; }
    grep -qE "$secret_text" <<<"$text" && { secret_hit=yes; inline_hit=yes; }
  done < <(segments "$lower")
fi

inline_note=""
[ -n "$inline_hit" ] && inline_note=" It was named inside inline interpreter code, where a path cannot be told from text, so it is refused even when the code only writes the name. To put text that names one into a file, use the Edit or Write tool."

# 1a. Secrets and machine config: no access at all, read included — the risk here
#     is exfiltration, and `cat` is as dangerous as `rm`.
if [ -n "$etc_hit" ]; then
  deny "Access to a system config directory (/etc, /private/etc, /var/root, /var/db) is not allowed.$inline_note"
fi

# Section 1b lived here: deny-by-default over the system trees, admitting a
# system path only when the segment's verb was on a list of sixty-nine readers.
# It was the largest thing in this file — a hundred and forty lines, and most of
# the reason the segmenter has to resolve heredocs, ANSI-C quotes and arithmetic
# at all. It was retired by the decision that moved this class of check to the
# platform, and the reason is worth keeping.
#
# The list was the attack surface. Of the eight published pre-execution-matching
# bypasses of Claude Code, every one is against a command on the safe list, and
# five of those eight — `echo`, `rg`, `find`, `sed`, `cd` — were on ours. A
# reader list several times longer than the one that produced those CVEs, with a
# hand-written awk lexer behind it rather than a parser, is not a smaller version
# of the same defence. It is the same defence with more rows.
#
# And it was paid for daily. Nine of the entries in this file's own history of
# false refusals come from this section and the segmenter it required: a commit
# message with a blank line in it, a directory name read as a command, a shell
# function definition, `cases.tsv` read as a verb. The asymmetry argument said
# each miss costs exactly one refused command — true, and it kept being paid,
# six times in one day, all to the person working on the guard. The last one
# refused the command that deleted this section, for naming the directories it
# used to protect.
#
# What replaces it is not nothing. Writes into the system trees are denied for
# the Edit and Write tools by `hooks/permissions.json`, which is machinery
# rather than prose; the platform never auto-approves them and prompts on
# anything it cannot parse; and a filesystem write scope enforced by the kernel
# is the only form of this that has never been bypassed. Section 1a above still
# refuses the directories where reading is itself the risk.
#
# The `cd` check went with it, four lines lower: refusing an absolute `cd`
# outside the project only ever mattered as a way of reaching the trees 1b
# guarded, and `cd` bypasses are their own CVE row.

# Credential and personal-data stores under the home folder: no access at all,
# read included. The `~/Library` entries are as sensitive as `~/.ssh` and are
# reached by ordinary tools rather than by anything that looks like an attack —
# `cat ~/Library/Keychains/login.keychain-db` is one `cat`.
#
# Case-insensitive, like the branch beside it, and that was the one difference
# between them for as long as both existed. macOS's default filesystem is
# case-insensitive, so a capital letter opened exactly the same file and this
# half allowed it: the lowercase spelling of the AWS credential file was refused
# and the uppercase one was matched by nothing at all — section 2 carries only
# the `.json` credential name, and that file has no extension.
#
# Paths and filenames are matched without regard to case throughout this file;
# flags are not. `git branch -D` a few lines down is matched against `$cmd`
# deliberately, because `-d` and `-D` are different commands. Both rules have a
# case in `cases.tsv` now, so neither can be "tidied" into the other.
if [ -n "$home_hit" ]; then
  deny "Access to a credential or personal-data store under the home folder (~/.ssh, ~/.aws, ~/Library/Keychains, ~/Library/Cookies, ~/Library/Messages, ...) is not allowed.$inline_note"
fi

# --- 2. Secrets: read/print .env, credentials, keys, tokens, certs -------
# Judged with sections 1a and 1c, in the segment walk above.
if [ -n "$secret_hit" ]; then
  deny "Reading or printing secret files (.env, credentials.json, private keys, certs, tokens) is not allowed.$inline_note"
fi

# --- 3. Destructive operations --------------------------------------------
# 3a. The destructive git verbs — behind a global option, and only there.
#
# This section used to repeat the deny-list: every one of these verbs, matched
# against the whole command. That cost more than it bought.
# `hooks/permissions.json` already refuses each of them, and a deny rule applies
# in **every** permission mode, including bypassPermissions — this file claimed
# the opposite for months, and the claim was load-bearing until it was checked
# against the platform's own documentation.
#
# What a deny rule cannot do is match a subcommand sitting behind git's global
# options, because permission rules match by prefix: `git -C <path> reset --hard`
# does not begin with `git reset`. Measured, not assumed — that form is refused
# here and by nothing else. So that form is what stays, and the plain one goes
# back to the layer that already had it.
#
# What the duplication cost: three false refusals in a single day, each a command
# whose *text* named a destructive verb — a commit message, a pull-request title,
# and a search across this repository's own files. Requiring the option run
# removes nearly all of that, because prose does not spell `git -C <path>`.
#
# `+` rather than `*` is the entire change, and it is worth reading twice: with
# `*` the option run was optional, which is what made this match the plain form.
gitpre='git([[:space:]]+(-c[[:space:]]*[^[:space:]]+|-C[[:space:]]*[^[:space:]]+|--git-dir[= ][^[:space:]]+|--work-tree[= ][^[:space:]]+|--no-pager|--paginate|--bare))+'
if grep -qE "$gitpre"'[[:space:]]+reset[[:space:]]+.*--hard' <<<"$lower" \
  || grep -qE "$gitpre"'[[:space:]]+push[[:space:]]+.*(--force([^-]|$)|--force-with-lease|-f([[:space:]]|$))' <<<"$lower" \
  || grep -qE "$gitpre"'[[:space:]]+clean[[:space:]]+.*-[a-z]*f' <<<"$lower" \
  || grep -qE "$gitpre"'[[:space:]]+filter-branch' <<<"$lower" \
  || grep -qE "$gitpre"'[[:space:]]+(checkout|restore)[[:space:]]+([^|;&]*[[:space:]])?\.\.?/*([[:space:]]|$)' <<<"$lower" \
  || grep -qE "$gitpre"'[[:space:]]+branch[[:space:]]+([^|;&]*[[:space:]])?-[a-zA-Z]*D' <<<"$cmd" \
  || grep -qE "$gitpre"'[[:space:]]+(update-ref|symbolic-ref)[[:space:]]+([^|;&]*[[:space:]])?(-d([[:space:]]|$)|--delete)' <<<"$lower"; then
  deny "A destructive git verb behind a global option (git -C, --git-dir, --work-tree, ...). The deny-list matches by command prefix and cannot see this form, so it is refused here. The plain spelling is refused by the deny-list instead."
fi

# 3a-bis. Destructive SQL, judged where something could execute it. No other
# layer carries these at all: there is no deny rule for SQL and the sandbox does
# not read statements.
#
# This matched the whole command line until it was measured, and the same defect
# 3a was shrunk to remove had simply moved here: a statement is a statement to a
# regex whether it sits behind a client or inside a sentence about the rule. In
# one session it refused a search of this repository, a batch of the guard's own
# test cases, and the command filing the issue that describes it — three
# refusals of the guard documenting itself.
#
# So the same shape as 3a: the segment has to be running a client. The list is
# the clients a person actually pipes a statement into, and it composes with the
# container unwrapping above, so `docker exec pg psql -c ...` is judged as
# `psql`.
#
# The silence this trades for: a statement reaching a client the list does not
# name, and `echo "..." | psql`, where the statement and the client are in
# different segments. Both are in the corpus as allow cases, so they are claims
# rather than gaps somebody discovers.
sql_clients='psql|mysql|mariadb|sqlite3|mongo|mongosh|redis-cli|clickhouse-client|cockroach|pgcli|mycli|usql'
sql_hits=""
while IFS= read -r seg; do
  [ -z "${seg// /}" ] && continue
  grep -qxE "$sql_clients" <<<"$(verb_of "$seg")" || continue
  seg_lower="$(tr '[:upper:]' '[:lower:]' <<<"$seg")"
  grep -qE '\bdrop[[:space:]]+(table|database|schema)\b' <<<"$seg_lower" \
    || grep -qE '\btruncate[[:space:]]+table\b' <<<"$seg_lower" \
    || continue
  sql_hits=yes
done < <(segments "$cmd")
if [ -n "$sql_hits" ]; then
  deny "Destructive SQL (DROP TABLE/DATABASE/SCHEMA, TRUNCATE TABLE) handed to a database client is always denied."
fi

# `update-ref` and `symbolic-ref` are plumbing: they remove a ref with none of
# the checks porcelain applies, so `-d` there is dangerous whatever it names.
# Nothing else was added, and a wider version was tried and withdrawn.
#
# For one day this file also carried a section 3c: deny-by-default over
# `stage/v*`, `refs/promote/*` and `refs/tags/v*`, written after a reserved
# stage branch was deleted from a session. It was removed on the owner's
# instruction, and the reason is worth keeping.
#
# It did not protect the product — the product is protected by `tools/promote.sh`
# being the only thing that can write to it, and by that phase needing a command
# typed at the moment it runs. What 3c restrained was this assistant, and it did
# so by restraining *everyone*: a PreToolUse hook cannot tell who typed a
# command, so the owner lost an operation they had explicitly kept for
# themselves, twice in one day. It also refused correct commands, because a
# read-only `git remote get-url` in the same line as a mention of a stage ref
# was judged by the mention.
#
# A guard earns its place by refusing what would be damage. One that refuses the
# owner, on their own repository, to enforce an instruction they gave — that is
# a guard doing the job of a rule, and it was made one instead: a reserved
# operation runs alone and announced, never as a line inside a batch composed
# for something else.

# 3b. Deletion: allowed ONLY if every path it names resolves under the session
#     scratchpad root.
#
#     This is a list of destructive verbs, and 1b was retired for being a list.
#     The difference is which way each one fails. 1b's list decided whether a
#     command could *run at all*, so every word missing from it was a refusal of
#     ordinary work, and it kept collecting them. This list only decides whether
#     to look harder at where a deletion points: a word missing from it costs a
#     warning nobody got, and a word on it costs nothing. A list that fails
#     towards silence can be incomplete; one that fails towards refusal cannot.
#
#     Kept honest by looking for the verb *anywhere* in a segment rather than
#     only at its head: that is what let `bash -c "rm -rf ~/dev"`, `xargs rm` and
#     `perl -e 'unlink ...'` walk past the old check.
#
#     A list of verbs is not a boundary, and this one is still not closed — see
#     the last paragraph. What was closed is everything that made the list not
#     even be *reached*: a `git` anywhere at the head exempted the whole command,
#     inline interpreter code was cut into pieces before it was read, and a
#     wrapper flag's value was read as the verb. Those are worth more than words:
#     each of them let every verb on the list through at once.
delete_verbs='rm|rmdir|unlink|shred|srm|grm|gshred|gunlink|safe-rm|trash|trash-put|rmtrash|gio|wipe|scrub'
# Inside inline interpreter code there is no verb position to read, so the words
# are matched loosely there — and only there. A leading `.` is part of the call,
# not a word boundary (`shutil.rmtree`, `fs.rmSync`), and a `Sync` suffix is the
# same call by its Node spelling; excluding either is how both were missed.
delete_words='(^|[^a-z0-9_-])(rm|rmdir|unlink|shred|srm|rmtree|remove_tree|removedirs|remove)(sync)?([^a-z0-9_-]|$)'

# A delete has to be the thing the segment *runs*. Matching the word anywhere
# reads `gh pr create --title "chore: rm dead code"` as a deletion; matching only
# at the head of a segment misses `bash -c "rm -rf ~/dev"`. So: the segment's
# verb is a delete, or it carries a flag that deletes (`find -delete`, and
# `rsync --delete`, whose second dash the old pattern did not allow).
hits=""
while IFS= read -r seg; do
  [ -z "${seg// /}" ] && continue
  v="$(verb_of "$seg")"
  # `git rm` stages a removal and keeps the history that makes it recoverable;
  # 3a governs the destructive git verbs, and `sharpen` retires a rule this way.
  # Asked of the segment, because asking it of the whole command exempted
  # everything downstream of a `git`: `git status && rm -rf ~/dev` reached none
  # of this section.
  [ "$v" = "git" ] && continue
  # Case-insensitive, because the filesystem this runs on is. macOS resolves
  # `RM` on PATH to the same binary as `rm`, so `RM -rf` really deletes and was
  # matching nothing here. Costs a false positive only on a command whose name
  # differs from a delete verb by case alone, which is not a thing.
  if grep -qixE "$delete_verbs" <<<"$v" \
    || grep -qE '(^|[[:space:]])--?(delete|exec|execdir|ok)([[:space:]]|$)' <<<"$seg"; then
    hits="$hits$seg"$'\n'
  fi
done < <(segments "$cmd")

# Inline interpreter code: `python3 -c "import shutil; shutil.rmtree(...)"`, or
# the same program handed over as a heredoc body. Neither has a verb position to
# read, so the delete word is matched loosely — and only inside the segment that
# actually runs the interpreter.
#
# It used to be asked of the whole command, because the splitter cut inline code
# into pieces and the interpreter and the deletion landed in different ones. The
# splitter is quote-aware now and keeps them together, so the wider test bought
# nothing and cost a great deal: any command containing both an interpreter and
# the word `rm` anywhere — a test payload, a path, another segment entirely —
# was refused. Four times in one day, to the author of the check.
while IFS= read -r seg; do
  [ -z "${seg// /}" ] && continue
  v="$(verb_of "$seg")"
  grep -qxE "$interpreters" <<<"$v" || continue
  grep -qE '(^|[[:space:]])-[a-z]*[ce]([[:space:]"'"'"']|$)' <<<"$seg" || grep -q '<<' <<<"$seg" || continue
  grep -qiE "$delete_words" <<<"$seg" && hits="$hits$seg"$'\n'
done < <(segments "$cmd")

if [ -n "$hits" ]; then
  targets="$(printf '%s' "$hits" \
    | tr -d '"'"'" \
    | grep -oE '[^[:space:]]+' \
    | grep -viE '^('"$delete_verbs"'|rmtree|rmsync|remove_tree|removedirs|remove|find|xargs|env|command|sudo|doas|nohup|time|nice|exec|builtin|'"$interpreters"'|import|from|os|shutil|fs|glob|do|done|then|else|fi|-[a-z-]*|[0-9]*>>?.*|[0-9]*<.*|&&|\|\||\{\}|\+|\\;)$' || true)"

  if [ -z "$targets" ]; then
    deny "Could not determine what this delete targets; denying by default. Use explicit paths under the session scratchpad."
  fi

  while IFS= read -r t; do
    [ -z "$t" ] && continue
    case "$t" in
      /*) resolved="$t" ;;
      *) resolved="$project_root/$t" ;;
    esac
    # Physical resolution needs the directory to exist, and a scratchpad has to
    # be deletable from before anything created it. The previous spelling put
    # two substitutions side by side, so the `||` read the exit status of
    # `basename` — which always succeeds — and a failed `cd` silently produced
    # `/x`. Outside the scratchpad by construction, so every delete inside a
    # scratchpad that did not exist yet was refused, and only on a machine where
    # it did not: locally the directory is always there and the corpus was green.
    #
    # The literal path cannot stand in for the resolved one. `$SCRATCH/../../..`
    # passes a prefix test unresolved and fails it resolved, which is the entire
    # reason for resolving. So `..` is collapsed textually instead.
    if dir="$(cd "$(dirname "$resolved")" 2>/dev/null && pwd -P)"; then
      resolved="$dir/$(basename "$resolved")"
    else
      resolved="$(normalize "$resolved")"
    fi
    # The separator is the whole test. A bare prefix comparison accepts every
    # sibling whose name merely starts with the same string: with a scratchpad at
    # `/private/tmp/claude-501`, a delete of `/private/tmp/claude-501-evil/x`
    # passed, and so did one that arrived there through `..`. One character
    # different from the boundary and outside it entirely — which is the exact
    # class of mistake this section exists to refuse.
    if [ "$resolved" != "$scratchpad_root" ] && [[ "$resolved" != "$scratchpad_root"/* ]]; then
      deny "Destructive delete ($t) targets a path outside the session scratchpad ($scratchpad_root); only temp files created this session may be deleted this way."
    fi
  done <<<"$targets"
fi

# What section 3b still does not catch, stated rather than implied:
#
#   * A deletion inside a script file. `node clean.js` calling `fs.rmSync` is
#     invisible here — the guard is handed a command, not a filesystem, and
#     reading the file would deny `node methodology/build.mjs` for containing the
#     word. The only honest closure is that a script run is a script trusted.
#   * A verb nobody has named yet. `delete_verbs` is a list and a list cannot be
#     completed; the words above cover the tools that exist today on this machine
#     and the trash family that was the next guess.
#   * Destruction that is not deletion: `> important.txt`, `dd of=`, `tee`,
#     `mv` over something. Denying those means denying every write in the project.
#
# So: narrowed, not closed. The verb list is the part that cannot be finished —
# which is why the three fixes above were structural instead, closing the paths
# that skipped the check entirely rather than adding more words to it.

# --- 4. The one operation this library reserves for a person -----------------
#
# `permissions-check.sh --reconcile` records every deny rule a project is
# currently missing as one it declined on purpose, and the startup warning about
# them then stops — for good, and quietly. Nothing else reachable from here
# removes a warning instead of leaving a mess somebody can see, and the reporter
# it silences was built so a model cannot even read the finding (`systemMessage`
# only, never `additionalContext`) for exactly that reason.
#
# Then `orrery:doctor` began printing that command fully resolved, into output a
# model reads by construction. What kept it a human's after that was one
# sentence in a skill file: an audit deleted the sentence with a mutant and
# every suite stayed green.
#
# The guard is the right layer here and the deny-list is not. A deny rule
# matches by prefix, and this command arrives at a version-pinned absolute path
# that changes on every plugin update. More than that, section 3c's tombstone
# above says what a hook costs when it enforces an instruction the owner gave —
# it refuses the owner too. Not here: this hook fires on the agent's Bash tool
# and on nothing else, so a person typing the same line in their own terminal
# never reaches it. The rule is "never on the user's behalf", and "through this
# hook" is precisely that set.
#
# Judged at the verb, the way 3a and 3a-bis both had to be. This rule is written
# about in this repository far more often than it is ever run, and a match
# against the whole line refuses the sentence describing it. `--report` and the
# plain hook mode are read-only, are what the doctor delegates to, and are not
# judged at all.
while IFS= read -r seg; do
  # The flag first: it is one cheap match and almost never present, so `verb_of`
  # — an awk process per segment — runs only where it could change an answer.
  grep -qE '(^|[[:space:]])--reconcile([[:space:]]|$)' <<<"$seg" || continue
  v="$(verb_of "$seg")"
  # An interpreter is asked separately, and without the `-c` test section 3b
  # uses: `bash script.sh` and `bash -c "script.sh"` both run it, and neither
  # leaves the script in the verb position.
  # Matched without regard to case, for the reason section 1 carries: on a
  # case-insensitive filesystem `Permissions-Check.sh` runs this exact file, and
  # the check that reserves this operation for a person was walked past by one
  # capital letter. What is being protected here is a decision, not a file.
  grep -qixF permissions-check.sh <<<"$v" \
    || { grep -qxE "$interpreters" <<<"$v" && grep -qiF permissions-check.sh <<<"$seg"; } \
    || continue
  deny "permissions-check.sh --reconcile records every deny rule this project is currently missing as one it declined on purpose, and permanently silences the startup warning about them. That is a decision about the project's own permissions, so it is typed by the person whose project it is, in their own terminal — never run on their behalf. This hook only ever sees the agent's Bash tool, so reaching it here is the one spelling that cannot have been theirs. Print the command for them if that is what was asked. The read-only modes are refused by nothing: --report lists the same rules, and the plain hook mode is what runs at startup."
done < <(segments "$cmd")

exit 0
