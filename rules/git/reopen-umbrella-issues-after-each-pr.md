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

**How to apply — prevent it first.** An umbrella is never the source of a
branch. `gh issue develop <N>` is what creates the link, so run it against the
**leaf issue** the pull request actually finishes; if the work has no leaf issue
yet, file one, which `every-merge-is-recorded-in-an-issue` already requires the
pull request to name. Referencing the parent in the body (`Refs #N`) is fine and
always was — what closes it is the branch link and a closing keyword, not a
mention. This moves the cost from once per merge, forever, to once per branch,
and it removes the failure instead of catching it. The paragraph below is what
to do for an umbrella that already carries a link.

**And detect it where prevention came too late:** for any issue that will span more than one PR, check
`gh issue view <N> --json state` after each non-final PR merges. If it
auto-closed, reopen it immediately with `gh issue reopen <N> --comment "..."`
explaining which PR closed it and what's still outstanding. Only let it close
for real on the PR that finishes the issue's full scope — and post the phase
retrospective first, per
`rules/git/closing-an-umbrella-posts-the-phase-retrospective.md`. A bare
`Closes #N` that closes it with none is reopened by the close gate in CI.
