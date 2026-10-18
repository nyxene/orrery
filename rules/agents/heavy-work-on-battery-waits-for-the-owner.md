---
rule: on battery, heavy work waits for the owner — ask before a full build, a mutation pass, a long test loop or a fan-out of agents, and if they are away do the light work and say what waited
scope: agents
evidence: "a laptop went from 99% to 33% in about two hours of its owner's ordinary day while agent sessions ran builds, test loops and long verification passes on battery"
---

Before heavy work, check the power source — `pmset -g batt` on macOS, the
platform's own check elsewhere. On battery, put the heavy work to whoever
directs the work first: a full build, a mutation pass, a long test loop, a
fan-out of agents. If they are away, do not wait idle and do not go ahead: do
the light work, keep the heavy work for mains power or their word, and say in
the report what waited.

**Why:** heavy work on battery is paid for twice — in charge and in the
machine's being unusable for the rest of the day — and nothing in a session
sees either. The obvious alternative, asking every time, collides with Canon §7:
a question nobody is there to answer blocks the work, and the canon says not to
block. Deferring only the heavy part is the reading of both: nothing waits that
could have gone on, and nothing expensive happens that was not agreed.

**How to apply:** treat as heavy anything that runs for minutes on every core —
a full build, a mutation pass, a long or looped test run, more than one or two
agents at once. A single test file, a lint, a read is light. When the go-ahead
on battery is given, it covers the work named, not the session.

**Related:** `rules/agents/a-subagent-leaves-nothing-running.md` is the other
half. `rules/agents/confirm-scope-before-parallel-agents.md` already asks before
a fan-out; on battery, its cost is part of the question.
