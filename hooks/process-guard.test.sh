#!/usr/bin/env bash
# Runs `hooks/process-cases.tsv` against `hooks/process-guard.sh`.
#
#   hooks/process-guard.test.sh            run the corpus, report failures
#   hooks/process-guard.test.sh --mutate   also run the mutation pass
#   hooks/process-guard.test.sh --mutate --changed
#                                          only the decision lines this change
#                                          touched — the pre-commit mode
#
# The loops are shared with the other two guard suites in
# `hooks/guard-test-lib.sh`. What is stated here is what makes this guard
# different, and one of the three differences is an inversion:
#
#   * the payload is a Bash command, like the Bash guard's — or an edit tool's
#     path, for the settings files (`@edit`, `@write`, `@notebook` in the corpus);
#   * the decision lines include a `sed` extraction, not only greps;
#   * **it fails open**, where both other guards fail closed.
#
# That last one is why `report_probes` is not called: its wording asserts a
# guard refuses when it cannot run, and here the required behaviour is the
# opposite. Copying the Bash guard's fail-closed default would mean a session
# without `jq` cannot run any command at all, in exchange for enforcing
# bookkeeping — and the first thing anyone would do is remove the hook, taking
# the delete guard's protection with it. The probes below pin the inversion so
# that a later edit toward "consistency" goes red instead of shipping.
#
# ## The mutant runs beside a copy of waiver.sh, and that is load-bearing
#
# The guard finds `waiver.sh` through `dirname "$0"`. Mutants used to be written
# to a bare path in $TMPDIR, so no mutant had `waiver.sh` beside it, the
# recording failed for every one of them, and probe 3 went red on a **byte-
# identical copy of the guard**. Every mutant was killed by its own location:
# `survived=0` was structurally guaranteed and the pass could never report a
# survivor. That is the "gate that had never matched anything" shape this
# repository has shipped twice, found here by an independent audit rather than
# by the pass itself.
#
# So the mutant goes in a directory that carries `waiver.sh` too, and probe 0
# below pins the fix: an unmutated copy in the mutant's own location must still
# record. If that probe ever fails, the mutation numbers underneath it mean
# nothing.
set -uo pipefail

# The probes build a git repository for the pull-request gate's state, and this
# suite runs as a pre-commit gate, where git exports GIT_DIR into the hook: an
# inherited one wins over `git -C`, and the fixture would be written into the
# repository being committed.
while IFS='=' read -r _var _; do unset "$_var"; done < <(env | grep '^GIT_')

here="$(cd "$(dirname "$0")" && pwd -P)"
guard="$here/process-guard.sh"
CASES="$here/process-cases.tsv"
# The decision lines. `command -v jq` and `[ -n "$cmd" ]` are gone from the
# guard rather than from this list: the pass showed neither could be killed,
# because with jq absent the extraction yields an empty string and the
# `-n "$matched"` test reaches the same fail-open by one path instead of three.
# Anchored at the start of a stripped line so a comment *mentioning* a decision
# is not selected as one. `grep -oE` appears in the paragraph above the line it
# describes, and blanking that comment reported a meaningless survivor.
# The pattern pieces are decision lines too. They were not in this list, so a
# commit that changed four of them quoted `survived=0` as evidence and the pass
# had in fact mutated four unrelated lines — a review caught that the numbers
# were about something else entirely. Blanking any of these leaves the variable
# unset under `set -u`, the guard exits non-zero, and every `deny` case in the
# corpus goes red, which is a real kill rather than an artifact.
MUTANTS_RE='^[[:space:]]*(if )?grep -q|^[[:space:]]*if \[ -z "\$reason" \]|^(assign|pos|ghflags|gitflags|cfg|cfgpath|target|settings_msg)=|^[[:space:]]*(scan|pr|prmatch|since|gitdir|log|state|top|rec|base|last|waived|first|pushmatch|def|cur|head|work)=|^[[:space:]]*(\{ ! git|\|\| \{ \[ -n "\$base"|&& ! \{ git|if record_missing|if \[ -n "\$log" \]|if \[ -n "\$first" \]|if \[ "\$u" = 1|\|\| ! git|-u\||-d\||--all\||\[ "\$(src|dst)" !=|\[ -n "\$remote"|\[ "\$\{#refs|src="\$\{src#|case "\$dst"|git -C "\$top" show-ref|w="\$\{w#)|^if \[ -n "\$pushmatch" \]|^[[:space:]]*fp="\$\(fingerprint\)"|^if \[ -n "\$prmatch" \]|^[[:space:]]*if \[ -n "\$top" \]|^[[:space:]]*if \[ -n "\$log" \]|^[[:space:]]*if \[ -z "\$waived" \]|^[[:space:]]*waive "|^[[:space:]]*\[ ! -f "\$state" \]|^[[:space:]]*\$2 == fp|^[[:space:]]*\$6 == "ran"|^[[:space:]]*hd \{|^[[:space:]]*if \(match|^[[:space:]]*(if \(\$6 == "call"\)|else if \(\$6 ==|END \{ for \(id in call\))|^[[:space:]]*v="\$\(audit |^[[:space:]]*\[ "\$v" != |^[[:space:]]*\[ (-n "\$waived"|-z "\$log") \] \|\| audited'

tmp="${TMPDIR:-/tmp}/orrery-process-guard-test.$$"
mutdir="$tmp.mut"
fakebin="$tmp.bin"
# Every waiver the guard records during this run lands in the fixture
# repository below and not in this one's own log. A suite that writes to the
# file it is testing leaves evidence of skips that never happened.
unset ORRERY_WAIVER_LOG
trap 'rm -rf "$tmp" "$tmp".*' EXIT
mkdir -p "$fakebin" "$mutdir"
cp "$here/waiver.sh" "$here/orrery-config.sh" "$mutdir/"
ln -s "$(command -v cat)" "$fakebin/cat"
ln -s "$(command -v bash)" "$fakebin/bash"

# shellcheck source=hooks/guard-test-lib.sh
. "$here/guard-test-lib.sh"

payload() { # $1 = command, $2 = tool_use_id or `@push`, $3 = cwd (default: none, the launch directory)
  local u="${2:-toolu_test}" d="${3:-}"
  # `@edit <path>`, `@write <path>`, `@notebook <path>`: an edit tool's payload,
  # carrying the path where that tool carries it and no command at all;
  # `@nopath`, one carrying neither.
  case "$1" in
    @nopath) jq -n '{session_id:"test-session",tool_input:{content:"x"}}'; return ;;
    "@edit "*|"@write "*) jq -n --arg p "${1#* }" '{session_id:"test-session",tool_input:{file_path:$p,content:"x"}}'; return ;;
    "@notebook "*) jq -n --arg p "${1#* }" '{session_id:"test-session",tool_input:{notebook_path:$p,new_source:"x"}}'; return ;;
  esac
  [ "$u" != @push ] || { u=toolu_test; d="$push"; }
  jq -n --arg c "$1" --arg u "$u" --arg d "$d" \
    '{session_id:"test-session",tool_use_id:$u,tool_input:{command:$c}} + (if $d == "" then {} else {cwd:$d} end)'
}

# The pull-request gate reads the session's call log and keeps its state beside
# it, in the main checkout's `.orrery/local/`. Neither may be this repository's:
# a session here has a log and CI has none, so reading it made the corpus mean
# different things in the two places. The corpus runs in a fixture repository
# with no log and no record of the work — every `gh pr create` in it is refused
# for the record, which is what pins the matcher — and the probes below build
# the log and the record they need, on a branch of their own.
unset ORRERY_CALL_LOG
gh='{"tracker":"github"}'
# The three fixtures, built by one function so each parallel mutant can have
# its own set made the same way rather than copied: a `cp -R` copy let three
# mutants live that a freshly built set kills.
fixtures() { # $1 = path prefix — sets repo, repo2 and push
  repo="$1.repo"
  mkdir -p "$repo"
  git init -q -b main "$repo"
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name process-guard-test
  git -C "$repo" commit -q --allow-empty -m init
  mkdir -p "$repo/.orrery"; printf '%s' "$gh" > "$repo/.orrery/config.json"
  export CLAUDE_PROJECT_DIR="$repo"
  repo2="$1.repo2"; mkdir -p "$repo2/.orrery"; git init -q -b main "$repo2"; : > "$repo2/.orrery/local"
  printf '%s' "$gh" > "$repo2/.orrery/config.json"
  # Without a tracker the gated act is a branch's first push. `feat` is checked
  # out and already on the remote, `solo` is not, `main` is the default branch.
  push="$1.push"; git init -q -b main "$push"
  git -C "$push" config user.email test@example.invalid; git -C "$push" config user.name process-guard-test
  git -C "$push" commit -q --allow-empty -m init; git -C "$push" remote add origin "$1.nowhere"
  git -C "$push" branch solo; git -C "$push" checkout -q -b feat; git -C "$push" tag v1
  git -C "$push" update-ref refs/remotes/origin/main main; git -C "$push" update-ref refs/remotes/origin/feat feat
  git -C "$repo2" config user.email test@example.invalid; git -C "$repo2" config user.name process-guard-test
}
base="$tmp"
fixtures "$base"
fp="$(printf '%s' test-session | shasum -a 256 2>/dev/null | cut -c1-8)"
[ -n "$fp" ] || fp="$(printf '%s' test-session | sha256sum | cut -c1-8)"
# Fixture times, generated rather than written: a literal date in a shipped file
# is residue to `sanitize-scan.sh`. Only their order matters.
d="$(date -u +%Y)-01-01T00:00:0"
row() { printf '%s\t%s\t%s\t%s\tno\t%s\t%s\n' "$1" "$fp" "$2" "$3" "$4" "$5"; }

pass=0 fail=0
ok()  { pass=$((pass + 1)); printf '\033[32m✓\033[0m %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '\033[31m✗\033[0m %s — %s\n' "$1" "$2"; }

# What a corpus of commands cannot express. Three properties, and the first two
# are the inversion: this guard must let through what it cannot read.
probes() { # $1 = guard path — prints how many it gets wrong
  local fails=0 out log
  # Unparseable input passes through. The Bash guard denies here on purpose;
  # this one must not, or a malformed payload stops all work.
  out="$(printf 'not json at all' | bash "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" && fails=$((fails + 1))

  # No jq, same direction.
  out="$(payload 'gh pr create --fill' \
    | PATH="$fakebin" "$fakebin/bash" "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" && fails=$((fails + 1))
  # And for an edit tool on a settings file: the fail-open holds there too.
  out="$(payload '@write /repo/.orrery/config.json' \
    | PATH="$fakebin" "$fakebin/bash" "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" && fails=$((fails + 1))

  # The waiver is recorded before the command is allowed. An escape that
  # permits without recording is the silence this whole mechanism exists to
  # end, and it would look identical from the session's side.
  log="$repo/.orrery/local/waivers.tsv"
  mkdir -p "$repo/.orrery/local"; : > "$log"
  payload 'ORRERY_WAIVE="mid-incident, owner said so" gh pr create --fill' \
    | bash "$1" >/dev/null 2>&1 || true
  grep -q 'gh pr create	mid-incident, owner said so' "$log" 2>/dev/null || fails=$((fails + 1))
  rm -f "$log"

  # The inverse, which is the claim the header actually makes: a recording that
  # CANNOT be written denies rather than permitting silently. This was
  # `|| true` followed by `exit 0`, so an unwritable log granted the exemption
  # and left nothing at all — a third state the file's own header says does not
  # exist. The second repository's `.orrery/local` is a file, so nothing can be
  # written under it.
  out="$(payload 'ORRERY_WAIVE="cannot be written" gh pr create --fill' toolu_test "$repo2" \
    | bash "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" || fails=$((fails + 1))

  # --- the record half. No record, with an auditor that would pass the other
  # half: refused, and the refusal names the way to write one.
  local calls="$repo/.orrery/local/calls.tsv" state="$repo/.orrery/local/pr-gate.tsv" pr='gh pr create --fill'
  local work rec
  rm -f "$state"; : > "$calls"; row ${d}1Z Agent auditor ran toolu_r0 >> "$calls"
  out="$(payload "$pr" toolu_r1 | bash "$1" 2>/dev/null || true)"
  grep -q 'record.sh write' <<<"$out" || fails=$((fails + 1))
  # On disk but not committed is still refused: the pull request carries HEAD.
  git -C "$repo" checkout -q -B withrec
  work="withrec"; rec="$repo/.orrery/work/$work/retrospective.md"
  mkdir -p "$(dirname "$rec")"; printf '# Retrospective — %s\n' "$work" > "$rec"
  out="$(payload "$pr" toolu_r2 | bash "$1" 2>/dev/null || true)"
  grep -q 'record.sh write' <<<"$out" || fails=$((fails + 1))
  # Where the project ignores its work, on disk is all there can be.
  printf '.orrery/work/\n' > "$repo/.gitignore"
  out="$(payload "$pr" toolu_r3 | bash "$1" 2>/dev/null || true)"
  grep -q 'record.sh write' <<<"$out" && fails=$((fails + 1))
  rm -f "$repo/.gitignore"
  git -C "$repo" add .orrery/work && git -C "$repo" commit -q -m rec
  # The same name again after that record merged: the old record does not count.
  git -C "$repo" update-ref refs/remotes/origin/HEAD HEAD
  out="$(payload "$pr" toolu_r4 | bash "$1" 2>/dev/null || true)"
  grep -q 'record.sh write' <<<"$out" || fails=$((fails + 1))
  git -C "$repo" update-ref -d refs/remotes/origin/HEAD
  rm -f "$state" "$calls"

  # --- the auditor half, with the record committed. Each probe states the log
  # it is read against.
  # No log: passes, as it does in a host that has not logged yet.
  out="$(payload "$pr" | bash "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" && fails=$((fails + 1))
  # A log with no auditor in it: refused.
  : > "$calls"
  row ${d}1Z Bash - call toolu_b >> "$calls"
  out="$(payload "$pr" | bash "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" || fails=$((fails + 1))
  # Another session's auditor does not count for this one.
  printf '%s\tffffffff\tAgent\tauditor\tno\tran\ttoolu_x\n' "${d}2Z" >> "$calls"
  out="$(payload "$pr" | bash "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" || fails=$((fails + 1))
  # This session's auditor, launched in the background: spawned and running,
  # no verdict yet — refused, and the refusal says it is owed one.
  row ${d}3Z Agent orrery:auditor call toolu_a >> "$calls"
  row ${d}3Z Agent orrery:auditor ran toolu_a >> "$calls"
  out="$(payload "$pr" | bash "$1" 2>/dev/null || true)"
  grep -q 'none has arrived' <<<"$out" || fails=$((fails + 1))
  # Its verdict BLOCKING: refused, by name.
  row ${d}3Z Agent orrery:auditor fail a1 >> "$calls"
  out="$(payload "$pr" | bash "$1" 2>/dev/null || true)"
  grep -q 'ruled BLOCKING' <<<"$out" || fails=$((fails + 1))
  # A later audit, in the foreground — call, verdict, ran, one second for all
  # three — that passes, in a host's namespaced spelling: through, and the pull
  # request is remembered.
  row ${d}3Z Agent orrery:auditor call toolu_f >> "$calls"
  row ${d}3Z Agent orrery:auditor pass a2 >> "$calls"
  row ${d}3Z Agent orrery:auditor ran toolu_f >> "$calls"
  out="$(payload "$pr" toolu_p1 | bash "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" && fails=$((fails + 1))
  grep -q 'toolu_p1' "$state" 2>/dev/null || fails=$((fails + 1))
  # That create never ran — no `ran` row — so it opened nothing, and the same
  # audit still covers the next attempt.
  out="$(payload "$pr" toolu_p2 | bash "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" && fails=$((fails + 1))
  # Once a create has run, the audit before it is spent.
  row ${d}4Z Bash - ran toolu_p2 >> "$calls"
  [ ! -f "$state" ] || sed -i.bak "s/^[^$(printf '\t')]*\(	$fp	toolu_p2\)$/${d}4Z\1/" "$state" && rm -f "$state.bak"
  out="$(payload "$pr" toolu_p3 | bash "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" || fails=$((fails + 1))
  # A pass, then a new audit spawned that has not ruled: the old pass does not
  # cover it. Then its verdict unreadable: refused as that. Another session's
  # pass after it changes nothing here.
  rm -f "$state"; : > "$calls"
  row ${d}5Z Agent auditor call toolu_c1 >> "$calls"; row ${d}5Z Agent auditor ran toolu_c1 >> "$calls"
  row ${d}6Z Agent auditor pass a3 >> "$calls"
  row ${d}7Z Agent auditor call toolu_c2 >> "$calls"; row ${d}7Z Agent auditor ran toolu_c2 >> "$calls"
  payload "$pr" | bash "$1" 2>/dev/null | grep -q 'none has arrived' || fails=$((fails + 1))
  row ${d}8Z Agent auditor unread a4 >> "$calls"
  printf '%s\tffffffff\tAgent\tauditor\tno\tpass\ta5\n' "${d}9Z" >> "$calls"
  payload "$pr" | bash "$1" 2>/dev/null | grep -q 'none of CLEAN' || fails=$((fails + 1))
  # A spawn that never ran — refused by another guard — owes no verdict.
  row ${d}9Z Agent auditor call toolu_c3 >> "$calls"; row ${d}9Z Agent auditor pass a6 >> "$calls"
  row ${d}9Z Agent auditor call toolu_c4 >> "$calls"
  payload "$pr" | bash "$1" 2>/dev/null | grep -q '"deny"' && fails=$((fails + 1))
  rm -f "$state"
  # An escaped pipe in a search pattern is text, not a pull request the spent audit refuses.
  payload "grep -n 'push\\|gh pr create' f" | bash "$1" 2>/dev/null | grep -q '"deny"' && fails=$((fails + 1))
  # A waiver passes, and is a row.
  log="$repo/.orrery/local/waivers.tsv"; : > "$log"
  out="$(payload "ORRERY_WAIVE=\"owner: ship it now\" $pr" | bash "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" && fails=$((fails + 1))
  grep -q 'gh pr create	owner: ship it now' "$log" 2>/dev/null || fails=$((fails + 1))
  # A heredoc line is text: it neither refuses nor records.
  : > "$log"
  out="$(payload "cat > doc.md <<'EOF'
ORRERY_WAIVE=\"forged\" gh pr create --fill
EOF" | bash "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" && fails=$((fails + 1))
  [ -s "$log" ] && fails=$((fails + 1))
  # An upgrade: the state still in git's directory, where a create ran after the
  # last auditor. That audit is spent there and must stay spent here — without
  # the carry-over the first pull request after an upgrade is ungated.
  rm -f "$state"; : > "$calls"
  row ${d}1Z Agent auditor ran toolu_u1 >> "$calls"; row ${d}1Z Agent auditor pass u1 >> "$calls"
  row ${d}2Z Bash - ran toolu_u2 >> "$calls"
  printf '%s\t%s\ttoolu_u2\n' "${d}2Z" "$fp" > "$repo/.git/orrery-pr-gate"
  out="$(payload "$pr" toolu_u3 | bash "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" || fails=$((fails + 1))
  rm -f "$repo/.git/orrery-pr-gate"
  # A project that switched the log off has switched this gate off with it.
  rm -f "$state"; mkdir -p "$repo/.orrery"; printf '{"tracker":"github","callLog":false}' > "$repo/.orrery/config.json"
  out="$(payload "$pr" toolu_p5 | bash "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" && fails=$((fails + 1))
  # And a waiver there is still a row, though the auditor half never runs.
  git -C "$repo" checkout -q main
  : > "$log"
  out="$(payload "ORRERY_WAIVE=\"owner: no log here\" $pr" toolu_p6 | bash "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" && fails=$((fails + 1))
  grep -q 'owner: no log here' "$log" 2>/dev/null || fails=$((fails + 1))
  rm -f "$log" "$calls" "$state"; printf '%s' "$gh" > "$repo/.orrery/config.json"
  git -C "$repo" branch -q -D withrec

  # --- without a tracker: the first push of `solo`, with its record committed.
  # The audit counts from the branch's first reflog entry, so one run before it
  # is not enough, and neither is another session's.
  calls="$push/.orrery/local/calls.tsv" log="$push/.orrery/local/waivers.tsv"
  local later; later="$(($(date -u +%Y) + 1))-01-01T00:00:00Z"
  git -C "$push" checkout -q solo; mkdir -p "$push/.orrery/local" "$push/.orrery/work/solo"
  : > "$push/.orrery/work/solo/retrospective.md"
  git -C "$push" add .orrery/work; git -C "$push" commit -q -m rec
  # Pushed from `feat`: on the main checkout `solo` is its own work all the same.
  git -C "$push" checkout -q feat
  : > "$calls"; row ${d}1Z Agent auditor ran toolu_a >> "$calls"; row ${d}1Z Agent auditor pass a1 >> "$calls"
  payload 'git push -u origin solo' @push | bash "$1" 2>/dev/null | grep -q '"deny"' || fails=$((fails + 1))
  printf '%s\tffffffff\tAgent\tauditor\tno\tpass\ta2\n' "$later" >> "$calls"
  payload 'git push -u origin solo' @push | bash "$1" 2>/dev/null | grep -q '"deny"' || fails=$((fails + 1))
  # The push shares the verdict rule: spawned and running is not yet a pass.
  row "$later" Agent auditor call toolu_b >> "$calls"; row "$later" Agent auditor ran toolu_b >> "$calls"
  payload 'git push -u origin solo' @push | bash "$1" 2>/dev/null | grep -q 'none has arrived' || fails=$((fails + 1))
  row "$later" Agent auditor pass a3 >> "$calls"
  payload 'git push -u origin solo' @push | bash "$1" 2>/dev/null | grep -q '"deny"' && fails=$((fails + 1))
  # A waiver passes with no audit at all, and is a row.
  : > "$calls"; : > "$log"
  payload 'ORRERY_WAIVE="owner: push it" git push origin solo' @push | bash "$1" 2>/dev/null \
    | grep -q '"deny"' && fails=$((fails + 1))
  grep -q 'git push	owner: push it' "$log" 2>/dev/null || fails=$((fails + 1))
  # Two pushes nothing pinned while a probe that failed for every mutant hid
  # them: a bare push of the checked-out branch, and one from a linked worktree,
  # where the work is not named after the branch. No audit, so both refuse.
  : > "$calls"; git -C "$push" checkout -q solo
  payload 'git push' @push | bash "$1" 2>/dev/null | grep -q '"deny"' || fails=$((fails + 1))
  git -C "$push" checkout -q feat; git -C "$push" worktree add -q "$push.wt" solo
  payload 'git push origin solo' toolu_test "$push.wt" | bash "$1" 2>/dev/null | grep -q '"deny"' || fails=$((fails + 1))
  git -C "$push" worktree remove --force "$push.wt"
  git -C "$push" checkout -q feat; git -C "$push" branch -q -f solo main; rm -rf "$push/.orrery"

  echo "$fails"
}

# Probe 0, which has to pass before any number below it means anything. The
# mutants run from `$mutdir`, and the guard finds `waiver.sh` through
# `dirname "$0"` — so if that directory does not carry one, every mutant fails
# the recording probe for its location rather than for its mutation, and
# `survived=0` is guaranteed no matter what the guard does.
cp "$guard" "$mutdir/process-guard.sh"
n0="$(probes "$mutdir/process-guard.sh")"

n="$(probes "$guard")"
if [ "$n" -eq 0 ]; then
  ok "passes through what it cannot read, and records before it permits"
else
  bad "passes through what it cannot read, and records before it permits" \
      "$n probes wrong"
fi

if [ "$n0" -eq 0 ]; then
  ok "an unmutated copy in the mutant's own location behaves identically"
else
  bad "an unmutated copy in the mutant's own location behaves identically" \
      "$n0 probes wrong there — every mutation number below is meaningless"
fi

total="$(grep -cE '^(deny|allow)	' "$CASES")"
fails="$(VERBOSE=1 corpus "$guard")"
if [ "$fails" -eq 0 ]; then ok "$total corpus cases"; else bad "$total corpus cases" "$fails failing"; fi

# The corpus feeds payloads to the script directly, so it cannot see whether the
# plugin routes a tool to it at all. A matcher reverted to `^Bash$` would leave
# every edit-tool case green and the settings files open to Write again.
for t in Bash Edit Write MultiEdit NotebookEdit; do
  if jq -e --arg t "$t" '[.hooks.PreToolUse[] | select(any(.hooks[]; .command | test("process-guard\\.sh"))) | .matcher as $m | $t | test($m)] | any' "$here/hooks.json" >/dev/null 2>&1; then
    ok "hooks.json routes $t to the guard"
  else bad "hooks.json routes $t to the guard" "no process-guard matcher matches it"; fi
done

# The refusal is read by a session that has to act on it, so it has to name the
# way out. A deny that only says no gets worked around rather than followed.
out="$({ payload 'gh pr create --fill' | bash "$guard"; payload 'git worktree add ../x' | bash "$guard"; } 2>/dev/null)"
for want in 'record.sh write' '--what' 'record.sh close' 'ORRERY_WAIVE=' "the person's to rule on" 'EnterWorktree' 'isolation'; do
  if grep -q -- "$want" <<<"$out"; then ok "the refusal names $want"
  else bad "the refusal names $want" "not in the message"; fi
done

printf '\n%s checks, %s failing\n' "$((pass + fail))" "$fail"

if [ "${1:-}" != "--mutate" ]; then
  [ "$fail" -eq 0 ] || exit 1
  exit 0
fi

[ "$fail" -eq 0 ] || { echo "corpus is red; fix it before mutating" >&2; exit 1; }

# `--changed`, the bash guard's pre-commit mode, and for the same reason: the
# full pass is 67 mutants one at a time, about 27 s each on CI — 21.5 minutes
# that used to run on every commit and every pull request. Only the decision
# lines this change touched, unless the corpus lost a line or the suite or the
# harness changed, when the full pass runs. CI runs the full pass on a pull
# request that touches any of them.
# Not `repo`: in this suite that name is the fixture the probes commit into, and
# the bash guard's spelling of this block, copied here, pointed every probe at
# the repository being tested — it switched the branch, deleted `.gitignore`
# and removed `origin/main` before it was caught.
if [ "${2:-}" = --changed ]; then
  self="$(cd "$here/.." && pwd -P)"
  removed="$(git -C "$self" diff HEAD --numstat -- hooks/process-cases.tsv | awk '{ s += $2 } END { print s + 0 }')"
  if [ "$removed" -gt 0 ] || ! git -C "$self" diff --quiet HEAD -- hooks/process-guard.test.sh hooks/guard-test-lib.sh; then
    echo "the corpus lost a line, or the suite or the harness changed — the full pass runs"
  else
    MUTATE_LINES="$(git -C "$self" diff --no-color HEAD -U0 -- hooks/process-guard.sh | changed_lines | tr '\n' ' ')"
    export MUTATE_LINES
  fi
fi

echo
# The probes write a call log, a gate file and commits into the fixtures, so
# mutants side by side would read each other's state. Each gets its own copy of
# all three instead, made in its own subshell, and the pass runs one per core —
# one at a time it was 67 mutants at about 27 s each on CI.
mutant_env() { # $1 = the line being mutated
  # `$base`, never `$tmp`: inside the harness's `mutation_pass` that name is its
  # own local, the mutant's path, and the first draft read `$tmp.repo2` from
  # there — a path that did not exist, so every mutant that reached the probes
  # was killed by its surroundings.
  fixtures "$base.j$1" >/dev/null 2>&1
}
case "$repo" in "$tmp".*) ;; *) echo "the probes' repository is not a fixture: $repo" >&2; exit 1 ;; esac
MUTATE_JOBS="${MUTATE_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"
mutation_pass "$guard" "$mutdir/process-guard.sh"
