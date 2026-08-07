---
rule: check git worktree list for running background agents before switching branches or committing, and stage only current-task files
scope: git
evidence: "a background workflow running in a separate worktree on another branch could have been disrupted by an unchecked branch switch or a blanket stage; set as policy before it bit"
---

Before switching git branches or creating a commit: (1) confirm no background
agent is actively running in another worktree that the switch or commit could
disrupt or race with; (2) stage only files relevant to the current task —
never a blanket `git add -A` / `git add .` that could sweep in another task's
changes.

**Why:** multiple worktrees and agents can be active concurrently — for
example a background workflow running in a scratchpad worktree on a different
branch. Switching branches or committing without checking risks stepping on
that in-progress work, or polluting the current commit with unrelated files
from a task the agent didn't ask about.

**How to apply:** run `git worktree list` (and `git status`) before any branch
switch or commit. If another worktree shows uncommitted or in-progress
changes tied to a running agent, don't touch it — just note it and proceed
only in the current worktree. When staging, add specific files by name for
the task at hand rather than a broad add.

**Related:** `rules/agents/parallel-agents-need-their-own-worktree.md` — the
same shared-working-tree hazard, seen from the agent-launching side.
