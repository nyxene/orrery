---
rule: reopen umbrella issues that auto-close after a non-final pr merges
scope: git
evidence: "an umbrella issue auto-closed when its first PR merged despite no closing keyword anywhere in the PR; caught and reopened immediately, but the closed state would have misled anyone scanning open issues"
---

`gh issue develop <N> --checkout ...` creates a GitHub "linked branch" association
between the branch and issue #N. When the PR from that branch merges, GitHub
auto-closes issue #N — even if the PR title, body, and commit message use a
neutral reference like `Refs #N` instead of a closing keyword (`Closes`/`Fixes`/
`Resolves`). For an umbrella issue that spans many PR-sized phases, the very
first PR under it can close the whole issue before the work is anywhere near
done.

**Why:** the auto-close is a GitHub platform behavior tied to the linked-branch
feature itself, not to commit-message keyword parsing. Avoiding closing
keywords in the PR does not prevent it — the link alone is enough to trigger
closure on merge.

**How to apply:** for any issue that will span more than one PR, check
`gh issue view <N> --json state` after each non-final PR merges. If it
auto-closed, reopen it immediately with `gh issue reopen <N> --comment "..."`
explaining which PR closed it and what's still outstanding. Only let it close
for real on the PR that finishes the issue's full scope — use a real
`Closes #N` there and let it stay closed.
