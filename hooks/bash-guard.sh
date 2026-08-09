#!/usr/bin/env bash
# PreToolUse guard for the Bash tool. Reads the proposed command from stdin
# (Claude Code hook JSON) and blocks it if it matches one of three banned
# categories: system-path / working-dir escapes, secret file access, or
# destructive operations outside the session scratchpad.
#
# `hooks/cases.tsv` is the corpus that pins this file, and `hooks/guard-test.sh` runs
# it. Change nothing here without running `hooks/guard-test.sh --mutate` after: a
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
# The scratchpad prefix is the one path here that differs per OS.
if [ "$(uname)" = "Darwin" ]; then
  scratchpad_root="/private/tmp/claude-$(id -u)"
else
  scratchpad_root="/tmp/claude-$(id -u)"
fi

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
      # Redirects split wherever they appear, quoted or not, but the two places
      # mean different things.
      #
      # Outside quotes a redirect is followed by a filename, never by a command.
      # Reading that filename as a verb refused `cat >> hooks/cases.tsv` for
      # leading with a verb called cases.tsv. Those segments are marked with \001
      # and judged as paths by the sections below: under a system directory the
      # redirect is a write, anywhere else it is an ordinary output file.
      #
      # Inside quotes a redirect is a write performed by an awk or perl program,
      # and its target keeps being judged as a verb. The corpus case using
      # awk -v with a system path and a BEGIN block that prints into it rests on
      # exactly that, and it went green to red the moment redirects were made
      # quote-aware along with everything else — the corpus doing its job.
      #
      # No apostrophe may appear anywhere in this awk program. One in a comment
      # ends the single-quoted argument, turns the rest into shell words, and the
      # guard stops parsing — which took every Bash call down until it was found.
      if (c == "<" || c == ">") {
        out = out "\n" ((inS || inD) ? "" : "\001")
        continue
      }
      if (!inS && !inD && index("(){};&|", c) > 0) { out = out "\n"; continue }
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
      if (t == "env" || t == "command" || t == "sudo" || t == "doas" ||
          t == "nohup" || t == "time" || t == "nice" || t == "ionice" ||
          t == "exec" || t == "builtin" || t == "xargs" || t == "stdbuf" ||
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
# anything, so the two are judged apart rather than the name being trusted.
# Sections 1b and 3b both ask this and used to carry a copy of the list each —
# two sources for one contract, kept in step by nothing but attention.
interpreters='node|python|python2|python3|ruby|perl|php|osascript|bash|sh|zsh|deno|bun'

# --- 1. System-path / working-directory escape ---------------------------

# 1a. Secrets and machine config: no access at all, read included — the risk here
#     is exfiltration, and `cat` is as dangerous as `rm`.
if grep -qE '(^|[[:space:]"'"'"'=])(/etc|/private/etc|/private/var/root|/var/root|/var/db)(/|[[:space:]"'"'"']|$)' <<<"$lower"; then
  deny "Access to a system config directory (/etc, /private/etc, /var/root, /var/db) is not allowed."
fi

# 1b. System trees: reading them is ordinary work — a PATH entry, a library
#     lookup, a shebang — and denying that blocks normal commands for nothing.
#     Writing to them is never wanted.
#
#     The test is deny-by-default: a system path may be touched only by a command
#     on the read list. An allowlist of *destructive* verbs cannot be completed —
#     `touch`, `rsync`, `tar -C`, `ditto`, `find -delete` and `python -c` are all
#     mutations, and any list of them is one tool short of the next attempt.
#
#     The read list is not complete either, and never will be. The difference is
#     which way each list fails: an unlisted reader costs one refused command,
#     visible immediately and fixed by adding a word. An unlisted mutator costs a
#     system directory. That asymmetry is the whole argument, and it is why an
#     unrecognised verb is refused rather than guessed at.
#
#     That argument holds only while the refusal is *visible*. One denial covered
#     both halves — a write and a word nobody has listed yet — so the reader of a
#     denial could not tell which it had hit, and the cheap failure looked exactly
#     like the policy one. An agent that reads "this is forbidden" where the truth
#     is "this word is missing from a list" does not add the word: it finds another
#     route or reports the task blocked, and the miss goes unreported forever. So
#     the two are denied separately, and the list-gap denial names the verb it did
#     not recognise and says what to do with it.
#     `/system` and `/library` are macOS; `/bin`, `/lib`, `/lib64` and `/boot`
#     make the same test hold on Linux. `/opt` stays out deliberately — Homebrew
#     on ARM macs lives there, and denying `brew` is a false positive, not safety.
sys_re='(/system|/library|/usr|/sbin|/bin|/lib|/lib64|/boot)'

# Parts of `~/Library` are the user's own working data — application support,
# caches, logs, preferences, fonts. Ordinary work writes there constantly and
# none of it is a system tree, so those leave before the match.
#
# The rest of `~/Library` does NOT leave, and exempting the whole tree was a
# defect introduced while removing false positives: it opened `~/Library/
# Keychains`, `~/Library/Cookies`, `~/Library/Messages` and `~/Library/
# LaunchAgents` in one line. The first three are secrets that neither 1a nor
# section 2 covers, and writing the fourth installs something that runs at login.
# What stays matched keeps the read-only treatment: `ls ~/Library/LaunchAgents`
# is fine, and writing there is not.
sys_src="$(sed -E 's@(~|\$home)/library/(application support|application-support|caches|logs|preferences|fonts|saved application state|webkit)@ userlib @g' <<<"$lower")"

# A leading `/usr/bin/python3` is how a command is *run*, not a path it operates
# on. Reduce it to its basename so the invocation stops reading as a mutation of
# /usr — `/bin/rm -rf /usr/local/lib` still trips, on its argument.
sys_src="$(sed -E 's@(^|[;&|`(])[[:space:]]*/(usr/local/bin|usr/bin|bin|usr/sbin|sbin)/@\1@g' <<<"$sys_src")"

# `PATH=/usr/local/bin cmd` mentions a system path without touching it. Only a
# *leading* assignment is a shell prefix; `awk -v f=/usr/lib/x` is an argument,
# and stripping that one is what let the indirect redirect through.
stripped="$(sed -E 's@(^|[;&|`(])[[:space:]]*(([a-z_][a-z0-9_]*=[^[:space:]]*[[:space:]]+)+)@\1@g' <<<"$sys_src")"

if grep -qE "(^|[^a-z0-9_./-])$sys_re(/|[^a-z0-9_-]|\$)" <<<"$stripped"; then
  # A write this section recognises exactly, as against a verb it does not
  # recognise at all. Both are refused; they are not the same news.
  sys_write=0
  sys_verb=""

  # A redirect into a system path used to be matched here, against the whole
  # command. The splitter now marks redirect targets and the loop below judges
  # each one as a path, which is the same decision made where the target is
  # actually known — so this line stopped being able to fail on its own and the
  # mutation pass reported it as a survivor. Removed rather than pinned: a check
  # no case can distinguish from its neighbour is a second source of one answer.

  # Flags that turn a reader into a writer.
  grep -qE '(^|[[:space:]])--?(delete|exec|execdir|ok)([[:space:]]|$)' <<<"$stripped" && sys_write=1
  grep -qE '(^|[[:space:]])sed[[:space:]]+(-[a-z]*i|--in-place)' <<<"$stripped" && sys_write=1
  # An awk program redirecting into a computed name (`awk -v f=/usr/lib/x
  # 'BEGIN{print "p" > f}'`) needs no rule of its own: `segments()` splits on `>`
  # too, so the write target becomes a segment and is judged as any other verb.
  # A heuristic for it was tried here and the mutation pass showed it caught
  # nothing this did not, while costing a false positive on `awk '$1 > 5'`.

  # `gh` operates on GitHub and `git` writes only under .git and the work tree:
  # a system path in their arguments is message or issue text, not a write
  # target. Judging them by verb denied a `gh issue create` and then a
  # `git commit` whose texts merely mentioned /System — twice in one day.
  # Everything added here writes nothing at all: it prints to stdout or it prints
  # nothing. Tools that inspect but can also write on a flag — `lipo -output`,
  # `pkgutil --expand`, `dtrace -o` — stay off deliberately; they are the ones the
  # list-gap denial below is for.
  readers='ls|cat|head|tail|less|more|grep|egrep|fgrep|rg|ag|fd|find|file|stat|readlink|realpath|which|type|wc|diff|du|df|awk|sed|sort|uniq|cut|tr|echo|printf|test|dirname|basename|strings|nm|otool|ldd|codesign|shasum|md5|pwd|xxd|od|tree|jq|export|cd|source|open|man|column|gh|git|lsof|ps|hexdump|objdump|readelf|dwarfdump|nl|comm|paste|rev|fold|cksum|md5sum|sha1sum|sha256sum'

  while IFS= read -r seg; do
    # A segment the splitter marked as a redirect target: a path, never a verb.
    # Under a system directory it is a write; anywhere else it is an ordinary
    # output file and there is nothing here to judge.
    if [ "${seg:0:1}" = $'\001' ]; then
      grep -qE "(^|[^a-z0-9_-])$sys_re/" <<<"${seg:1}" && sys_write=1
      continue
    fi
    verb="$(verb_of "$seg")"
    [ -z "$verb" ] && continue
    grep -qxE "$readers" <<<"$verb" && continue
    if grep -qxE "$interpreters" <<<"$verb"; then
      # `-c` and `-e` are not the only ways to hand an interpreter a program.
      # `python3 - <<PY` is inline code too, and it used to be refused only by
      # accident: the body's lines each became a segment and the first word of
      # one of them was an unrecognised verb. Once the body correctly stops being
      # segmented, that accident stops happening — so the heredoc has to be named
      # for what it is.
      grep -qE '(^|[[:space:]])-[a-z]*[ce]([[:space:]]|$)' <<<"$seg" && sys_write=1
      grep -q '<<' <<<"$seg" && sys_write=1
      continue
    fi
    # Verbs whose whole job is to write. Without this they reach the list-gap
    # denial, which asks the reader to consider adding the verb to the reader
    # list — the right repair for `pkgutil` and the wrong one for `touch`. Both
    # answers are still deny, so no case can pin this line; it decides which of
    # the two denials is told, and telling an agent to allowlist `tar` is how a
    # message meant to close a hole opens one.
    case "$verb" in
      touch|tar|rsync|ln|tee|mv|install|dd|mkdir|chmod|chown|chgrp|chflags|xattr|patch|truncate|unzip|cpio|rm|rmdir|unlink|shred|srm)
        sys_write=1; continue ;;
    esac
    # `cp` reads its sources and writes exactly one destination: the last word.
    # Not anchored to the start: a destination can be reached through a prefix
    # (`~/Library/LaunchAgents/`), and anchoring is what let that one past.
    if [ "$verb" = "cp" ] || [ "$verb" = "ditto" ]; then
      grep -qE "(^|[^a-z0-9_-])$sys_re/" <<<"$(awk '{print $NF}' <<<"$seg")" && sys_write=1
      continue
    fi
    sys_verb="${sys_verb:-$verb}"
    # Segmented from `sys_src`, not from `stripped`. The leading-assignment strip
    # that produces `stripped` exists for the trigger tests above — it stops
    # `PATH=/usr/local/bin cmd` from reading as a write — but its value pattern
    # runs to the next space, so `n=$(jq -r ...)` had `n=$(jq` removed as a
    # prefix and the verb went with it: the next token, a quoted jq filter, was
    # reported as an unrecognised command. Nothing is lost by using `sys_src`
    # here, because `verb_of` already skips assignment tokens itself, and
    # `segments` opens `$(` so the substitution becomes its own segment with its
    # real verb at the head.
  done < <(segments "$sys_src")

  if [ "$sys_write" -eq 1 ]; then
    deny "Only reading is allowed under a system directory (/System, /Library, /usr, /sbin, /bin), and this command writes there: it leads with a verb whose job is writing (touch, tar, mv, ln, ...), redirects into a system path, carries a flag that turns a reader into a writer (-delete, -exec, sed -i), runs inline interpreter code, or copies to a destination under one. This is the policy and not a gap in a list, so there is no spelling of it that passes. If the write is genuinely required, that is the user's call to make, not something to route around."
  elif [ -n "$sys_verb" ]; then
    deny "Refused by a list, not by a policy: '$sys_verb' is not on the reader list in section 1b of hooks/bash-guard.sh, and a verb this guard does not recognise is refused rather than guessed at when a system path (/System, /Library, /usr, /sbin, /bin) is in the command. Reading under those paths is allowed and ordinary — that list is incomplete by construction and always will be, and every miss is designed to cost exactly one refused command and nothing more. So if '$sys_verb' only reads: add it to the readers list in hooks/bash-guard.sh, with a case in hooks/cases.tsv, or say out loud that the guard is missing '$sys_verb' and let the user decide. Do NOT reach for another way to run it, and do NOT report the task as blocked — a refusal that gets quietly routed around is the one failure this message exists to prevent, because it turns a one-word fix into a hole nobody hears about. If '$sys_verb' can write anywhere under those paths, the refusal stands and is correct."
  fi
fi

# Credential and personal-data stores under the home folder: no access at all,
# read included. The `~/Library` entries are as sensitive as `~/.ssh` and are
# reached by ordinary tools rather than by anything that looks like an attack —
# `cat ~/Library/Keychains/login.keychain-db` is one `cat`.
if grep -qE '(^|[[:space:]])(~|\$HOME)/\.(ssh|aws|gnupg|kube|docker|npmrc|netrc|git-credentials)([/[:space:]]|$)' <<<"$cmd" \
  || grep -qiE '(^|[[:space:]"'"'"'=])(~|\$HOME)/library/(keychains|cookies|messages|mail|safari|accounts|suggestions|autosave information)([/[:space:]"'"'"']|$)' <<<"$cmd"; then
  deny "Access to a credential or personal-data store under the home folder (~/.ssh, ~/.aws, ~/Library/Keychains, ~/Library/Cookies, ~/Library/Messages, ...) is not allowed."
fi

if grep -qE '(^|[;&|[:space:]])cd[[:space:]]+"?(/[^[:space:]"]*)"?' <<<"$cmd"; then
  target="$(grep -oE 'cd[[:space:]]+"?/[^[:space:]"]*' <<<"$cmd" | head -1 | sed -E 's/^cd[[:space:]]+"?//')"
  if [ -n "$target" ] \
    && [[ "$target" != "$project_root"* ]] \
    && [[ "$target" != "$scratchpad_root"* ]]; then
    deny "cd to an absolute path outside the project ($project_root) or the session scratchpad is not allowed: $target"
  fi
fi

# --- 2. Secrets: read/print .env, credentials, keys, tokens, certs -------
secret_pattern='(^|[/[:space:]"'"'"'])((\.env(\.[a-zA-Z0-9_-]+)?)|credentials\.json|id_rsa|id_ed25519|id_ecdsa|\.pem|\.p12|\.pfx|\.jks|\.keystore|\.npmrc|\.netrc|\.git-credentials)([/[:space:]"'"'"']|$)'
if grep -qE "$secret_pattern" <<<"$lower" \
  && ! grep -qE '\.env\.(example|sample|template)([/[:space:]"'"'"']|$)' <<<"$lower"; then
  deny "Reading or printing secret files (.env, credentials.json, private keys, certs, tokens) is not allowed."
fi

# --- 3. Destructive operations --------------------------------------------
# 3a. Never allowed, no exceptions (not scoped to a single file/temp dir).
#
# Every pattern below reads the subcommand as the word after `git`, and git's
# global options sit exactly there: `git -C ~/dev clean -fdx` is `git clean` with
# a target, and it walked past all of them. So the option run is folded into the
# patterns rather than the subcommand being matched anywhere in the line —
# matching it anywhere would deny `git commit -m "clean up -f"`.
gitpre='git([[:space:]]+(-c[[:space:]]*[^[:space:]]+|-C[[:space:]]*[^[:space:]]+|--git-dir[= ][^[:space:]]+|--work-tree[= ][^[:space:]]+|--no-pager|--paginate|--bare))*'
if grep -qE "$gitpre"'[[:space:]]+reset[[:space:]]+.*--hard' <<<"$lower" \
  || grep -qE "$gitpre"'[[:space:]]+push[[:space:]]+.*(--force([^-]|$)|--force-with-lease|-f([[:space:]]|$))' <<<"$lower" \
  || grep -qE "$gitpre"'[[:space:]]+clean[[:space:]]+.*-[a-z]*f' <<<"$lower" \
  || grep -qE "$gitpre"'[[:space:]]+filter-branch' <<<"$lower" \
  || grep -qE "$gitpre"'[[:space:]]+(checkout|restore)[[:space:]]+([^|;&]*[[:space:]])?\.([[:space:]]|$)' <<<"$lower" \
  || grep -qE "$gitpre"'[[:space:]]+branch[[:space:]]+([^|;&]*[[:space:]])?-[a-zA-Z]*D' <<<"$cmd" \
  || grep -qE "$gitpre"'[[:space:]]+(update-ref|symbolic-ref)[[:space:]]+([^|;&]*[[:space:]])?(-d([[:space:]]|$)|--delete)' <<<"$lower" \
  || grep -qE '\bdrop[[:space:]]+(table|database|schema)\b' <<<"$lower" \
  || grep -qE '\btruncate[[:space:]]+table\b' <<<"$lower"; then
  deny "Destructive git/DB operation (reset --hard, push --force, clean -f, checkout/restore ., branch -D, update-ref -d, DROP/TRUNCATE, ...) is always denied."
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
#     Unlike 1b this stays a list of destructive verbs, and the asymmetry is
#     deliberate rather than the other half of an unfinished fix. 1b can demand a
#     known reader because its trigger is a system path, where reading is the
#     whole of the legitimate use. Here the trigger would have to be the project
#     and the home directory — everywhere real work happens — and deny-by-default
#     across those refuses nearly everything. So an incomplete list is accepted
#     here, and kept honest by looking for the verb *anywhere* in a segment
#     rather than only at its head: that is what let `bash -c "rm -rf ~/dev"`,
#     `xargs rm` and `perl -e 'unlink ...'` walk past the old check.
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
  # The splitter marks redirect targets; here they are just filenames, and the
  # marker must not become part of one.
  seg="${seg#$'\001'}"
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
  seg="${seg#$'\001'}"
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
    | grep -viE '^('"$delete_verbs"'|rmtree|rmsync|remove_tree|removedirs|remove|find|xargs|env|command|sudo|doas|nohup|time|nice|exec|builtin|'"$interpreters"'|import|from|os|shutil|fs|glob|-[a-z-]*|[0-9]*>>?.*|[0-9]*<.*|&&|\|\||\{\}|\+|\\;)$' || true)"

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

exit 0
