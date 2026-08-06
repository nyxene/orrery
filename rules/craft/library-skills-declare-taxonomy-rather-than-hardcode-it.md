---
rule: a skill shipped in a library names what the host project must declare, and never bakes one project's labels, paths or issue numbers into itself
scope: craft
evidence: "a library skill queried an issue label spelled the way one host project spelled it; in any other host the query returns an empty list, indistinguishable from a clean backlog — caught in audit before first install, so it cost nothing"
---

A library skill states the distinction it owns and delegates the vocabulary. It
declares what the host project must supply — labels, paths, commands — in the
library's install declaration, reads that declaration at runtime, and hard-codes
none of it.

**Why:** a baked-in taxonomy is correct in exactly one project and wrong in
every other, and it is wrong *silently*. `gh issue list --label tech-debt`
against a project that labels debt `type/debt` does not error — it returns an
empty list, which is indistinguishable from a clean backlog. The skill then
reports success. This is worse than a crash by the usual margin: a crash names
its own cause, and this reports the opposite of what happened.

The same divergence is invisible from inside the library, because nothing there
runs the query. It surfaces on the first real install, by which time the skill
has been trusted for however long it sat unexecuted.

One skill carried this for months: a label spelling from a single host, plus
nine of that host's scope labels, two of its issue numbers as reference
examples, and a `priority: <level>` spelling — all from one project, inside a
library whose whole purpose is installing into any of them.

**How to apply:** when writing or reviewing a library skill, grep it — **case
insensitively**, which is how a capitalised host name survived the first sweep —
for the host's fingerprints:

| Fingerprint | Verdict |
|---|---|
| Literal label strings, package names, toolchain commands | Move to the project's declaration |
| The host's subject matter used as the only example | Generalise; state the mechanism, not the field |
| The host's business facts ("this is commercial software being sold") | Delete. State the consequence unconditionally instead |
| A path | Fine **if** it is a stated default with an override, named in the install declaration |
| An issue number as **provenance** for a rule or an incident | Fine. That is the library's whole thesis |
| An issue number as a **reference example of a category** | A fingerprint. Describe the category instead |
| A model name outside the one line that pins the current assignment | A fingerprint of *time* rather than of a project, and it rots on the next release |

Where a query can return empty, say which reading is more likely: **an empty
result means the labels are wrong before it means the work is done.**

A skill may still hard-code the *distinction* — what counts as debt, what counts
as a rule. That part is the same everywhere and is why the skill exists.
