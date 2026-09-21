#!/usr/bin/env bash
# Does this pull request name the issue it belongs to?
#
#   install/ci/names-an-issue.sh <title> <body>     exit 0 when it does, 1 when not
#
# Called from .github/workflows/gates.yml on pull_request, and shipped for a host
# to copy in beside `install/ci/pr-names-an-issue.yml`. It lives in a file rather
# than inline in the workflow for one reason: a check written inside a YAML
# `run:` block is a check nothing can run. This repository has shipped two gates
# that had never matched anything — one used `find -mindepth 1 ... -o -mindepth 2`,
# an empty range for every input, and one used `grep -P` on a BSD grep that does
# not have it. Both reported clean for months. A file here gets a suite beside it.
#
# What it cannot check: whether the number names the *right* issue, or an issue
# that exists at all. That stays a reviewer's job. This refuses the case that has
# actually happened — no number anywhere.
set -uo pipefail

title="${1-}"
body="${2-}"

# `#12` must not match inside `abc#12` or `v1#12`: a bare word ending in a hash
# number is a code fragment, not a reference. Leading `(^|[^A-Za-z0-9_])` is the
# whole of that, and ERE only — see the `grep -P` half of the note above.
if printf '%s\n%s' "$title" "$body" | grep -qE '(^|[^A-Za-z0-9_])#[0-9]+'; then
  echo "ok — this pull request names an issue"
  exit 0
fi

cat >&2 <<'MSG'
This pull request names no issue.

Everything merged into the default branch is recorded in an issue: it is how
that branch stays traceable, and it is not a way of deferring work. Fixing now
and filing the record are not alternatives — see
rules/git/every-merge-is-recorded-in-an-issue.md.

Put '#<number>' in the title or the body. If no issue exists yet, file one
describing what this change does and why, then reference it. Retroactive by
minutes is fine; absent is not.
MSG
exit 1
