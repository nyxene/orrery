---
rule: "content that rests on a single domain expert's judgment must be editable data, not hardcoded logic"
scope: craft
evidence: "a project's sole reviewing domain expert became unavailable for an indeterminate period; set as policy before any correction was blocked behind a code deploy"
---

Any content that rests on a single domain expert's confirmation — not a documented, externally-verifiable convention — must be built as externally editable data (config, JSON, DB-seeded rows), never inlined into business or rendering logic. A future correction from that expert should be a data edit, not a code change or redeploy of logic.

**Why:** A domain expert who reviews and confirms judgment calls can become unavailable for an unpredictable stretch, but the product still needs to keep shipping. If their calls are baked into code, every correction once they're back requires a code change and a deploy; if the calls live in data, the correction is cheap and doesn't touch logic at all. This also forces a useful distinction: content independently verified against a stable, citable external source doesn't need this treatment — the soft spots are specifically single-person judgment calls or product-preference choices, not settled conventions.

**How to apply:** For any value or ruleset an expert would need to sign off on, ask "does this trace back to one person's say-so rather than a citable convention?" If yes, model it as a config/data record (profile, roster, lookup table) with a clear amendment path — an admin UI, a seed file, or at minimum a single well-documented data file — not a literal embedded in application logic. This generalizes beyond any one domain: a legal app's attorney-reviewed clause wording, a medical app's physician-reviewed dosage thresholds, or a nutrition app's dietitian-reviewed substitution table are the same shape of problem.

**Related:** `rules/craft/third-party-content-splits-into-idea-vs-expression.md` — the other soft spot in research-derived content, protected expression rather than single-person judgment.
