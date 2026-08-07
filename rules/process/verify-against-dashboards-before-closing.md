---
rule: before declaring an epic done, re-check its design doc's resolved open questions and any existing dashboard against actual shipped code
scope: process
canon: 3
evidence: "an epic was nearly recommended for closure while a published feature-map dashboard already flagged it incomplete; the real gap — a decision resolved on paper but never implemented — was found only after the discrepancy was chased down"
---

This expands Canon §3 (Evidence before claims).

Before recommending an epic or issue be closed, re-check the design doc's Open Questions / resolved-decisions section against actually shipped code — not just its named-phase checklist — and treat any existing dashboard, handoff note, or other tracked artifact that already flags the item as incomplete as a lead to chase down, never something to silently override.

**Why:** a phase-by-phase read only proves that each named phase's own PR shipped something; it says nothing about a product decision that was resolved on paper in the design doc's Open Questions but never actually implemented, because no phase's PR claims that piece. A plausible-looking checklist match is not the same evidence as checking the resolved decision against the code.

**How to apply:**
1. Re-read the design doc's Open Questions / resolved-decisions section, not just its phase list — a resolved decision needs its own shipped-code check, the same as a phase does.
2. If a dashboard, handoff note, or other tracked artifact already flags the item as incomplete or "not re-scoped," treat that as a lead to chase down with fresh evidence, not something to silently override.
3. When a discrepancy surfaces between your read and an existing artifact, resolve it with a targeted code search before acting, and say so explicitly rather than picking whichever answer is more convenient in the moment.
