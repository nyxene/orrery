---
rule: propose agent count, model tier, and scope, and wait for confirmation before spawning parallel research or planning agents
scope: agents
evidence: "cost multiplies with agent count in a parallel fan-out, so the number and the tier are spent before anyone sees them; set as policy before it bit"
---

Before spawning any parallel research or planning agents — multiple `Agent` calls in one message, or a `Workflow` fan-out — propose the number of agents, the model tier for each, and the estimated scope of work, then wait for explicit confirmation before launching.

**Why:** the person directing the work wants control over the cost and scope of multi-agent work before it's committed, not after the fact. This applies specifically to *parallel* research/planning fan-outs, where cost multiplies with agent count, not to a single sequential agent call whose cost is already obvious.

**How to apply:** any time a task calls for launching 2+ agents concurrently (Explore, general-purpose, etc.) or a Workflow with parallel/pipeline stages, stop and present the plan — agent count, model, scope — as text or a structured question, and get explicit go-ahead first. Single, individually-obvious agent delegations (e.g. one Explore call to find a file) don't need this.

**Related:** `rules/process/only-an-explicit-go-ahead-starts-work.md` — both put the decision to spend in the hands of the person paying for it, before the spending starts rather than after.
