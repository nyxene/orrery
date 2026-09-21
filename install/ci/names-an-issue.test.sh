#!/usr/bin/env bash
# Tests install/ci/names-an-issue.sh — the CI check that refuses a pull request with
# no issue behind it.
#
#   install/ci/names-an-issue.test.sh
#
# Small, and worth having anyway: the two gates this repository found dead had
# both been read by every session since they went wrong, because a check that
# matches nothing and a check that matches everything print the same clean line.
# The pair that matters here is the refusal — a gate that never refuses is not a
# gate, and only a case proves it does.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
check="$here/names-an-issue.sh"

pass=0 fail=0
fail_names=()
ok()  { pass=$((pass + 1)); printf '\033[32m✓\033[0m %s\n' "$1"; }
bad() { fail=$((fail + 1)); fail_names+=("$1"); printf '\033[31m✗\033[0m %s — %s\n' "$1" "$2"; }

accepts() { # $1 = name, $2 = title, $3 = body
  if "$check" "$2" "$3" >/dev/null 2>&1; then ok "$1"; else bad "$1" "expected exit 0"; fi
}
refuses() { # $1 = name, $2 = title, $3 = body
  if "$check" "$2" "$3" >/dev/null 2>&1; then bad "$1" "expected exit 1"; else ok "$1"; fi
}

# Every fixture number here is five digits, deliberately. `tools/sanitize-scan.sh`
# refuses a tracker reference of one to four digits in anything that ships, and
# it is right to: those point at issues a consumer cannot open. Five digits are
# outside that range and outside this tracker's, so they name nothing and cannot
# come to name anything. The gate under test matches `#[0-9]+`, so digit count
# changes none of what these cases prove. Do not "tidy" them back to small
# numbers: the release door refuses the whole tree over one of them.

printf 'install/ci/names-an-issue.sh\n\n'

accepts "Closes #N in the body"            "fix(x): a thing"      "Closes #99230"
accepts "a bare reference in the body"     "fix(x): a thing"      "Part of #99054, not finishing it"
accepts "the number in the title alone"    "fix(x): a thing (#99012)" ""
accepts "a reference mid-sentence"         "docs: notes"          "which #99007 already described"
accepts "a multi-digit number"             "fix"                  "Closes #12345"

refuses "no number anywhere"               "fix(x): a thing"      "A body with reasoning and no reference."
refuses "an empty body and title"          ""                     ""
refuses "a hash with no digits"            "fix(x)"               "see the # section below"

# The boundary the leading class is for: a hash glued to a word is a code
# fragment — a CSS id, a shell comment, a fragment URL — not a reference.
refuses "a hash inside a word is not a reference" "fix" "the selector div#99004 in the sheet"
accepts "but the same number after a space is"    "fix" "the selector div #99004 in the sheet"

# A body arrives from `github.event.pull_request.body`, which is whatever a
# person typed. It reaches the script as one argument and is never expanded.
refuses "a body of shell metacharacters is data" "fix" '$(touch /tmp/pwned); `id`; rm -rf .'
accepts "and the same body with a number passes" "fix" '$(id) — Closes #99001'

printf '\n%s cases, %s failing\n' "$((pass + fail))" "$fail"
if [ "$fail" -gt 0 ]; then
  printf 'failed: %s\n' "${fail_names[*]}"
  exit 1
fi
