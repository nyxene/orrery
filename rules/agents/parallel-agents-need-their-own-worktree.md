---
rule: every parallel agent that writes files and touches git needs isolation:'worktree', even when the task briefs don't share a single file
scope: agents
evidence: "two parallel agents whose briefs shared no files still collided on concurrent branch creation in one shared working tree; recovery cost a manual triage session, and no work was lost only because the stuck agent paused instead of guessing"
---

Set `isolation: 'worktree'` on every `Workflow` `agent()` call inside a `parallel()` (or concurrent pipeline stage) that mutates files — unconditionally, not just when the task briefs look likely to touch the same files.

**Why:** two parallel implementation agents (one on a UI layer, one on backend wiring) didn't share a single file in their briefs, and still collided — because without `isolation: 'worktree'`, both ran `git checkout -b <own-branch>` in the same shared primary working directory. The second `checkout -b` doesn't discard the first agent's uncommitted changes; it carries them onto the new branch, so the second agent inherited the first agent's in-progress diff sitting on its own branch mid-edit. The collision is about two concurrent `git checkout -b` calls sharing one working tree, not about file-content overlap — so "do the file lists overlap?" is the wrong question to ask when deciding whether to isolate.

**How to apply:** when a Workflow script has multiple `agent()` calls in the same `parallel()` array (or concurrent pipeline stage) that each do their own `git checkout -b` / branch / commit / push flow, set `isolation: 'worktree'` on all of them by default. Skip it only for read-only agents or agents that don't touch git state at all. The isolation cost (a few hundred milliseconds of setup plus disk per agent) is trivial next to a mid-session collision recovery. Worth reinforcing: a stuck agent that notices a collision and pauses to report instead of guessing or pushing through it is the right failure behavior.

**Where there is no `Workflow` tool**, the build skill falls back to plain parallel `Agent` calls in one message, and `isolation` is a `Workflow` option that fallback does not have — so the collision this rule prevents is *unguarded* on exactly that path. Either give each agent its own worktree explicitly (`git worktree add` before the batch, and brief each agent with its own directory), or run the file-mutating agents in sequence. Parallel writers sharing one working tree is the thing itself, not a risk factor for it.

**Related:** `rules/git/check-worktrees-before-switching.md` — the same shared-working-tree hazard, seen from the branch-switching side.
