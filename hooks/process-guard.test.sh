#!/usr/bin/env bash
# Runs `hooks/process-cases.tsv` against `hooks/process-guard.sh`.
#
#   hooks/process-guard.test.sh            run the corpus, report failures
#   hooks/process-guard.test.sh --mutate   also run the mutation pass
#
# The loops are shared with the other two guard suites in
# `hooks/guard-test-lib.sh`. What is stated here is what makes this guard
# different, and one of the three differences is an inversion:
#
#   * the payload is a Bash command, like the Bash guard's;
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
MUTANTS_RE='^[[:space:]]*(if )?grep -q|^matched=|^\[ -n "\$matched" \]|^[[:space:]]*if \[ -z "\$reason" \]|^(assign|pos|ghflags|close|api|xargsform)=|^[[:space:]]*(scan|pr|prmatch|since|gitdir|log|state)=|^[[:space:]]*fp="\$\(fingerprint\)"|^if \[ -n "\$prmatch" \]|^[[:space:]]*if \[ -n "\$log" \]|^[[:space:]]*elif ! awk|^[[:space:]]*waive "|^[[:space:]]*if grep -q .ORRERY_WAIVE|^[[:space:]]*\[ ! -f "\$state" \]|^[[:space:]]*\$2 == fp|^[[:space:]]*\$6 == "ran"|^[[:space:]]*hd \{|^[[:space:]]*if \(match'

tmp="${TMPDIR:-/tmp}/orrery-process-guard-test.$$"
mutdir="$tmp.mut"
fakebin="$tmp.bin"
# Every waiver the guard records during this run goes here and not into the
# repository's own log. A suite that writes to the file it is testing leaves
# evidence of skips that never happened.
export ORRERY_WAIVER_LOG="$tmp.waivers"
trap 'rm -rf "$tmp" "$tmp.repo" "$mutdir" "$fakebin" "$ORRERY_WAIVER_LOG"' EXIT
mkdir -p "$fakebin" "$mutdir"
cp "$here/waiver.sh" "$mutdir/waiver.sh"
ln -s "$(command -v cat)" "$fakebin/cat"
ln -s "$(command -v bash)" "$fakebin/bash"

# shellcheck source=hooks/guard-test-lib.sh
. "$here/guard-test-lib.sh"

payload() { # $1 = command, $2 = tool_use_id
  jq -n --arg c "$1" --arg u "${2:-toolu_test}" \
    '{session_id:"test-session",tool_use_id:$u,tool_input:{command:$c}}'
}

# The pull-request gate reads the session's call log and keeps its state in
# git's common directory. Neither may be this repository's: a session here has
# ORRERY_CALL_LOG set and CI does not, so an inherited one made the corpus mean
# different things in the two places. The corpus runs with no log at all —
# every `gh pr create` in it passes, as it does in a host that keeps none — and
# the probes below build the log they need.
unset ORRERY_CALL_LOG
repo="$tmp.repo"
mkdir -p "$repo"
git init -q -b main "$repo"
git -C "$repo" config user.email test@example.invalid
git -C "$repo" config user.name process-guard-test
export CLAUDE_PROJECT_DIR="$repo"
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
  out="$(payload 'gh issue close 42' \
    | PATH="$fakebin" "$fakebin/bash" "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" && fails=$((fails + 1))

  # The waiver is recorded before the command is allowed. An escape that
  # permits without recording is the silence this whole mechanism exists to
  # end, and it would look identical from the session's side.
  log="$tmp.probe-waivers"
  : > "$log"
  payload 'ORRERY_WAIVE="mid-incident, owner said so" gh issue close 42' \
    | ORRERY_WAIVER_LOG="$log" bash "$1" >/dev/null 2>&1 || true
  grep -q 'mid-incident, owner said so' "$log" 2>/dev/null || fails=$((fails + 1))
  # And the issue number rides with it, or a row cannot be reconciled against
  # the issue it belongs to.
  grep -q '#42' "$log" 2>/dev/null || fails=$((fails + 1))
  rm -f "$log"

  # The number, from a URL whose *repository name* carries digits. The corpus
  # cannot reach this: it asserts deny or allow, and a row recording the wrong
  # issue is an allow either way — deleting the extraction left it green. Two
  # real repository names would have recorded `#3` and `#2` for issue 42 and
  # issue 306, because the general form stops at the first digit run in the
  # argument and the `issues/` branch sat behind it, unreachable.
  : > "$log"
  payload 'ORRERY_WAIVE="link from the browser" gh issue close https://github.com/o/web3-app/issues/42' \
    | ORRERY_WAIVER_LOG="$log" bash "$1" >/dev/null 2>&1 || true
  grep -q '#42' "$log" 2>/dev/null || fails=$((fails + 1))
  grep -q '#3	' "$log" 2>/dev/null && fails=$((fails + 1))
  rm -f "$log"

  # The inverse, which is the claim the header actually makes: a recording that
  # CANNOT be written denies rather than permitting silently. This was
  # `|| true` followed by `exit 0`, so an unwritable log granted the exemption
  # and left nothing at all — a third state the file's own header says does not
  # exist. The path below is unwritable because `/dev/null` is not a directory.
  out="$(payload 'ORRERY_WAIVE="cannot be written" gh issue close 42' \
    | ORRERY_WAIVER_LOG=/dev/null/nope/waivers.tsv bash "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" || fails=$((fails + 1))

  # --- the pull-request gate. Each probe states the log it is read against.
  local calls="$tmp.calls" state="$repo/.git/orrery-pr-gate" pr='gh pr create --fill'
  rm -f "$state"
  # No log: passes, as it does in a host that keeps none.
  out="$(payload "$pr" | bash "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" && fails=$((fails + 1))
  # A log with no auditor in it: refused.
  : > "$calls"
  row ${d}1Z Bash - call toolu_b >> "$calls"
  out="$(payload "$pr" | ORRERY_CALL_LOG="$calls" bash "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" || fails=$((fails + 1))
  # Another session's auditor does not count for this one.
  printf '%s\tffffffff\tAgent\tauditor\tno\tran\ttoolu_x\n' "${d}2Z" >> "$calls"
  out="$(payload "$pr" | ORRERY_CALL_LOG="$calls" bash "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" || fails=$((fails + 1))
  # This session's auditor, in a host's namespaced spelling: passes, and the
  # pull request is remembered.
  row ${d}3Z Agent orrery:auditor ran toolu_a >> "$calls"
  out="$(payload "$pr" toolu_p1 | ORRERY_CALL_LOG="$calls" bash "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" && fails=$((fails + 1))
  grep -q 'toolu_p1' "$state" 2>/dev/null || fails=$((fails + 1))
  # That create never ran — no `ran` row — so it opened nothing, and the same
  # audit still covers the next attempt.
  out="$(payload "$pr" toolu_p2 | ORRERY_CALL_LOG="$calls" bash "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" && fails=$((fails + 1))
  # Once a create has run, the audit before it is spent.
  row ${d}4Z Bash - ran toolu_p2 >> "$calls"
  [ ! -f "$state" ] || sed -i.bak "s/^[^$(printf '\t')]*\(	$fp	toolu_p2\)$/${d}4Z\1/" "$state" && rm -f "$state.bak"
  out="$(payload "$pr" toolu_p3 | ORRERY_CALL_LOG="$calls" bash "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" || fails=$((fails + 1))
  # An escaped pipe in a search pattern is text, not a pull request the spent audit refuses.
  payload "grep -n 'push\\|gh pr create' f" | ORRERY_CALL_LOG="$calls" bash "$1" 2>/dev/null | grep -q '"deny"' && fails=$((fails + 1))
  # A waiver passes, and is a row.
  log="$tmp.probe-waivers"; : > "$log"
  out="$(payload "ORRERY_WAIVE=\"owner: ship it now\" $pr" | ORRERY_CALL_LOG="$calls" \
    ORRERY_WAIVER_LOG="$log" bash "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" && fails=$((fails + 1))
  grep -q 'gh pr create	owner: ship it now' "$log" 2>/dev/null || fails=$((fails + 1))
  # A heredoc line is text: it neither refuses nor records.
  : > "$log"
  out="$(payload "cat > doc.md <<'EOF'
ORRERY_WAIVE=\"forged\" gh pr create --fill
EOF" | ORRERY_CALL_LOG="$calls" ORRERY_WAIVER_LOG="$log" bash "$1" 2>/dev/null || true)"
  grep -q '"deny"' <<<"$out" && fails=$((fails + 1))
  [ -s "$log" ] && fails=$((fails + 1))
  # A close riding behind a create is still the close's to answer for.
  row ${d}9Z Agent auditor ran toolu_a2 >> "$calls"
  out="$(payload "$pr && gh issue close 42" toolu_p4 | ORRERY_CALL_LOG="$calls" bash "$1" 2>/dev/null || true)"
  grep -q 'retrospective' <<<"$out" || fails=$((fails + 1))
  rm -f "$log" "$calls" "$state"

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

# The refusal is read by a session that has to act on it, so it has to name the
# way out. A deny that only says no gets worked around rather than followed.
out="$(payload 'gh issue close 42' | bash "$guard" 2>/dev/null)"
# `--waive` is the way past that survives a host running the server-side
# workflow; `ORRERY_WAIVE` alone records a row the server cannot see.
for want in 'close-issue.sh' '--what' '--waive' 'ORRERY_WAIVE=' "the person's to rule on"; do
  if grep -q -- "$want" <<<"$out"; then ok "the refusal names $want"
  else bad "the refusal names $want" "not in the message"; fi
done

printf '\n%s checks, %s failing\n' "$((pass + fail))" "$fail"

if [ "${1:-}" != "--mutate" ]; then
  [ "$fail" -eq 0 ] || exit 1
  exit 0
fi

[ "$fail" -eq 0 ] || { echo "corpus is red; fix it before mutating" >&2; exit 1; }
echo
# One at a time whatever the environment says: the probes share a repository,
# a call log and the gate file.
MUTATE_JOBS=1 mutation_pass "$guard" "$mutdir/process-guard.sh"
