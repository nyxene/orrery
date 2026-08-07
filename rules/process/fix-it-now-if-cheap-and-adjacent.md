---
rule: fix a review finding immediately if it's cheap and adjacent, or correctness-critical; otherwise file debt and ask
scope: process
evidence: "a cheap, adjacent review finding was reflex-filed as debt instead of folded into the same PR; the same reflex later auto-filed a correctness-critical finding, deferring an output known to be wrong"
---

For a review or audit finding that isn't the PR's primary target, fix it immediately in the same PR if it's cheap and doesn't reach into a genuinely different area of functionality, OR if it's necessary for the shipped feature to work correctly at all, regardless of size. Otherwise, file it as debt and ask directly whether to fix it now, in a follow-up, or after the original PR merges — don't just let it sit. If the fix would be genuinely large, that size is itself a planning-quality signal worth raising, independent of filing the issue.

**Why:** a blanket "file everything as debt" habit is too conservative for findings that cost nothing to fix on the spot, and it's actively wrong for correctness-critical findings — deferring a wrong output (e.g. a rule evaluated under the wrong configuration, producing a wrong verdict) ships a known bug to every affected user in the meantime. A long finding list creates its own pressure to batch-file everything without individually testing each one against the rule.

**How to apply:** at the audit/fix-loop stage of the build skill (or any manual review), triage every surviving minor finding through this test before defaulting to debt. Don't ask permission on the "fix immediately" branch — just do it and mention it in the report. Only the "different functionality, not correctness-critical" branch needs sign-off before proceeding, and only the "large fix" branch needs the planning-quality question surfaced. Re-run this test per finding, every time — treating "audit finding" as a reflex trigger for "debt issue" is the exact failure this rule exists to stop.
