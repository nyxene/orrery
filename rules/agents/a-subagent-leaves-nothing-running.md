---
rule: a subagent leaves nothing running — its brief says to stop what it starts, children included, and its report names whatever still runs, read from the process table
scope: agents
evidence: "a laptop drained 30–50% of its battery per hour while its owner worked; about twenty orphaned processes left by subagents' test runs — shell, socket helpers, jq, tail, cat — and a preview server were found and stopped by hand, each left by a run that had reported success"
---

A subagent's brief tells it to stop every process it starts — a server, a
watcher, a test loop, a preview — and to wait for or kill the children of
anything it runs, before it reports. Its report names what still runs, which
should be nothing. A worktree's processes end with the worktree's work.

**Why:** the canon says the same to every session, and a subagent never reads
it — the canon loads at session start, and a spawned agent gets the brief and
nothing else. So the duty reaches an agent only through the words someone wrote
for it, which is the one place this rule loads: the agents scope, at the spawn.
The obvious alternative, trusting the agent's own account, fails in exactly the
case that matters. A test that starts a shell, `jq` and a helper process and
returns a green result has no reason to mention the helpers; orphans of that
shape are what a battery drain is made of.

**How to apply:**

- Every brief that may start a process carries one line: stop what you start,
  children included, before you report; name anything you could not stop.
- Whoever receives the report checks the process table rather than the report:
  `ps -Ao pid,ppid,etime,command` filtered by the worktree path or the commands
  the agent ran, and `lsof -a -d cwd +D <worktree>` for anything still sitting
  in the worktree. What the agent missed is stopped then, and named in the final
  report.
- A worktree whose work is done is not removed with a process still in it.

**Related:** `rules/agents/heavy-work-on-battery-waits-for-the-owner.md` is the
other half of the same complaint. `rules/agents/parallel-agents-need-their-own-worktree.md`
is why there is a worktree to clean up after.
