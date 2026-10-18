---
name: learn
description: Turn an incident into a rule. Invoke the moment something breaks in a way that will recur, or the user corrects how you work — while the cause is still known. Writes a provenance-carrying rule into this project's own rules layer; nothing leaves the repository unless the project has declared an incident inbox.
argument-hint: "[what happened, in one line]"
---

# Learn — Turn an Incident Into a Rule

This is what keeps a project's rule layer alive. Almost every rule got there
because something actually went wrong, and that is the whole difference between
an earned rule set and a list of best practices — it survives only if rules are
filed at the moment of the incident.

**A few are declared policy instead, and they say so.** A rule set before it
bit carries `cost: none — set as policy before it bit`, and that line is the
marker: nobody has paid for this one yet. Such a rule earns its place on the
risk it names rather than on an incident, which is a higher bar and a rarer
one — reserve it for a harm nobody wants to meet once. If you cannot name the
harm in a sentence, you are writing best practice and the answer is no.

The distinction decides how a rule loses an argument. An earned rule wins on
its cost; a declared one wins only on the risk, so when the risk turns out to
be imaginary it goes, and nothing is lost.

**File it now, not later.** An hour later you have the lesson but not the
evidence. A week later you have neither, and the rule reads like something
copied off the internet — which is exactly how it gets dismissed as stale.

## When to invoke

- Something broke, and the cause was a way of working rather than a one-off typo.
- The user corrected how you work and meant it to last — said "always" or "from
  now on", or repeated a correction already made. One correction of one output
  is a preference, not a rule: `sharpen` calls it noise for the same reason, and
  filing it writes a rule against the user.
- A tool, harness, or framework behaved contrary to a reasonable expectation.
- You caught yourself about to repeat a mistake you have made before — that
  means the rule does not exist yet, or does not say what it needs to.
- **Something was proposed and refused.** See below — this is the one case where
  a rule prevents work rather than a defect.

## A refusal is a rule

Debt tracking records what was deferred. Nothing records what was **refused**,
and that is the gap an agent falls into every session: with no memory, it
proposes the same abstraction, the same config flag, the same extra layer — and
from its fresh context the proposal is reasonable every time.

A refusal is a law like any other, and it is filed the same way. What makes it
worth keeping is the **test attached to it**: not "we said no to X", but the
question the next case gets asked.

> `rule: issue-tracker support is limited to trackers a typical engineer would
> recognise and could plausibly have chosen` — where the alternative is a rule
> saying only that one specific tracker was turned down, which decides nothing.

Two conditions keep the set from rotting:

- **Refusals only, never deferrals.** "Not now, we are busy" is a schedule, and
  it will be wrong within a month. If the reason is not durable, it is not a
  rule.
- **Never record "already built".** A thing declined because it exists is a
  feature, not a refusal, and filing it teaches the next search that a solved
  problem was rejected.

A refusal that turns out to be wrong is deleted, not argued with. It was
evidence about a past decision, never a veto over the person directing the work.

## When NOT to invoke

- **A fact about one codebase.** "This API returns 204 on empty" is
  documentation, not a rule.
- **Something a script can enforce.** If a linter, type-checker, or CI gate can
  catch it, add the gate. A rule that a machine could enforce is a rule that
  will be forgotten.
- **Mess left behind.** A shortcut you took, duplication you introduced, a
  stale comment — that is debt, not a rule. Rules are lessons about *how to
  work*; debt is *what we left in the code*.
- **A one-off.** If it cannot recur, there is nothing to prevent.
- **Friction with Orrery itself** — a guard that refused something reasonable, a
  skill that fired wrongly, a rule whose advice was wrong. That is `feedback`,
  which reports upward to the tooling's own tracker. `feedback` already cedes
  the other direction: a rule goes here when the incident will recur *in this
  project*. The distinction is where the fix has to land, not how it felt.

## Procedure

**1. State the law.** One sentence, in the imperative or as a claim. If you
cannot state it without naming a specific file or ticket, it is not a rule yet
— keep generalizing until it holds beyond the incident that produced it.

**2. Check it does not already exist.** Read the filenames in the plugin's
`rules/` and this project's `.claude/rules/`; they state their own contents, so
scanning is cheap. If a rule already covers this, **update it** — add the new
incident to its provenance and sharpen the wording. Two rules saying nearly the
same thing is how a rule set stops being read.

**Name the scanned set in the commit.** A one-line trailer — `Scanned:
rules/process/ (12 files)` — on the commit that adds a rule. The scan is already
mandatory above and is the step that silently does not happen: nothing
distinguishes "I read the directory and this is genuinely new" from "I wrote a
file". Writing down what was read makes the difference visible to whoever finds
the near-duplicate later, and costs one line.

**A promoted rule leaves the local layer.** When a rule is sanitized and shipped
in the library itself, take the local copy out — the law now arrives with the
plugin, and keeping both means one of them drifts and neither reader knows which
is authoritative.

**3. Pick the scope directory.**

| Directory | Holds |
|---|---|
| `agents/` | Orchestration, subagents, workflows, model choice |
| `git/` | Branching, commits, PRs, merging |
| `process/` | Consent, planning, debt, reporting, working with the user |
| `craft/` | Framework and tooling lessons that hold in any project |

**There is no `domain` scope, and this table used to offer one.** A lesson true
only of one project's subject matter belongs in that project, not in a library
installed into all of them — the rules loader has no case that can emit it, so a
file filed under `domain/` exists and never loads: no error, no rule.

So the test is not craft-versus-domain, it is whether this is a rule at all.
Would it still be true and useful in a project that has nothing to do with this
one's subject? If no, it is a fact about one codebase — see *A fact about one
codebase* above — and it belongs in that codebase's own notes.

**4. Name the file as the law itself**: kebab-case, lowercase, `.md`, 3-8
words, and the filename states the rule rather than its subject.

**5. Write it with provenance.**

```yaml
---
rule: <the law, one lowercase line>
scope: agents | git | process | craft
learned: YYYY-MM-DD
origin: "<the issue, PR, or incident — never invented>"
cost: <what it actually broke, or "none — set as policy before it bit">
---
```

Then the body, in three parts:

1. The rule stated plainly, 2-4 sentences.
2. `**Why:**` — the mechanism, and specifically **why the obvious alternative
   fails**. A rule whose reasoning is obvious will be re-derived and overridden
   by whoever hits the same fork.
3. `**How to apply:**` — what to actually do, concretely.

Close with `**Related:**` naming neighbouring rules in prose.

**Never invent a date or an issue number.** If the incident carries none,
describe the situation. A fabricated origin is worse than no origin: it makes
every other rule's provenance untrustworthy.

**6. Write it into this project's own rules layer** —
`.claude/rules/<scope>/<name>.md` in the host repository — and commit it. The
rules loader reads that layer alongside the plugin's shipped rules from the
next session on. Never write into the plugin cache: it is overwritten on every
update, and a rule filed there disappears silently.

Your incidents are your own. Nothing this skill writes leaves the repository,
and there is no telemetry.

**7. If — and only if — this project declares an incident inbox.** A project's
`CLAUDE.md` may declare `Incident inbox: <owner>/<repo>` (the library
maintainers' own projects do). When the declaration exists AND `gh` can reach
that repository, also file the full version there as an issue labeled
`incident`: the law, the complete provenance, the narrative. When either
condition fails — no declaration, no access — this step does not exist; do not
ask, do not warn, do not attempt it.

A lesson that holds beyond this project is worth sharing with the library
either way: open an issue or PR on the plugin's public repository — sanitized,
voluntarily, by hand.

## The cost field earns its place

It is tempting to leave `cost` vague. Do not. "One agent stalled mid-run; no
work lost" tells a future reader how hard to weigh this rule against a
competing concern. "Caused problems" tells them nothing, and a rule that cannot
be weighed will lose every argument it enters.
