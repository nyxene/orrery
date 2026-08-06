---
rule: never sweep system folders or resources outside the user's own directories
scope: process
evidence: "a full-filesystem sweep during data reconstruction walked directories outside the user's own space and tripped permission prompts nobody had agreed to"
---

Never read, search, or otherwise touch system folders or resources outside the user's own directories — no broad `find /` sweeps, no system config dirs outside the user's own space. The assistant's own config/session directory is always fine to access. A general development directory is fine too, but only with a concrete, stated reason for that specific access, never as a default place to poke around.

**Why:** a full-filesystem sweep looks like the fastest way to locate something you can't place, but it walks directories the user never agreed to expose and trips permission prompts they didn't expect — the search *radius*, not the search *intent*, is what causes the surprise.

**How to apply:** when a task needs something outside the current project directory, go straight to the specific known-likely location first (e.g. the assistant's own per-project session/transcript path) instead of searching broadly from `/` or `$HOME`. If a search must range over a general dev directory, state the reason in the same turn (e.g. "checking a sibling project for X") rather than doing it silently. Never search or read outside the assistant's own config directory, the general dev directory, or the current project without a stated reason first.

**Related:** `rules/process/only-an-explicit-go-ahead-starts-work.md` — both are about not taking action the user hasn't implicitly or explicitly cleared.
