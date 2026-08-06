---
name: sharpen
description: Improve the library itself from accumulated evidence. Invoke periodically, or at the end of a session that went badly — reads corrections and friction from recent sessions, finds the patterns, and proposes changes to canon, skills, agents, rules or guards, one at a time.
argument-hint: "[optional: an area to weight more heavily]"
---

# Sharpen — Improve the Tools From Evidence

`learn` handles one incident becoming one rule. This handles the other
direction: many incidents becoming a change to the tools, so the incident stops
happening rather than being documented every time it does.

Run it periodically, or right after a session that went badly while the
friction is still legible.

## What this looks at

1. **This conversation** — corrections, friction, things repeated.
2. **Recent session transcripts** — `~/.claude/projects/<project>/*.jsonl`.
   Extract **user messages only**; assistant output and tool results are noise
   here and enormous. Filter for feedback signals: corrections ("no", "don't",
   "actually", "wrong", "instead"), friction ("again", "I already said"),
   explicit asks ("next time", "I wish", "should"), and approval ("exactly",
   "yes, that"). Approval matters — it tells you what to protect.
3. **The rule set itself** — clusters are the real signal. See below.
4. **What the last run promised.** Every accepted change from the previous
   sharpen: did it actually land? Canon §3 applies to this skill too, and a
   self-improvement loop that never audits itself drifts fastest of all.

## The mechanism that matters most

**A rule that keeps recurring is a defect in a skill, not a missing rule.**

Three rules that all say "check X before doing Y" mean the skill that should
have made X automatic is broken. Filing a fourth rule is the wrong move — it is
documenting the same failure a fourth time and calling it learning.

So: cluster the rules by what they are actually guarding against. Where a
cluster forms, the fix belongs in the skill, the agent, or the guard — and once
it lands, **retire the rules the fix absorbed**.

This is not optional tidying. A rule set that only grows stops being read, and
an unread rule protects nothing. Retiring absorbed rules is what keeps the rest
worth reading.

**Retire with `git rm`, not `rm`.** The Bash guard allows `rm` only inside the
session scratchpad, and a rule file is not in the scratchpad — so plain `rm`
on one is denied, deliberately.
`git rm rules/<scope>/<name>.md` is the sanctioned path — it stages the removal
and keeps the history that makes the retirement recoverable.

**Record the retirement where the absorption happened.** The commit that lands
the fix names each rule it retired and where that rule's force now lives. A rule
file deleted without that is a lesson deleted: six months on, the set says four
things were retired and nothing about what class of thing keeps failing, which
is the only part that transfers.

That commit is the record, so it has to carry the reasoning rather than the
filename alone — `git log --diff-filter=D -- rules/` is how a future session
asks what used to be here and why it stopped being true.

## Where a fix belongs

The same decision `learn` makes, applied to fixes:

| Symptom | Fix goes in |
|---|---|
| Must hold always, in every session | `CANON.md` — and something else should probably come out |
| Holds sometimes, needs its reasoning explained | `rules/` |
| A procedure worth invoking deliberately | `skills/` |
| Belongs to one role's judgement | `agents/` |
| Cannot be trusted to discipline at all | `hooks/` |

Prefer the lowest row that works. A guard that makes a mistake impossible beats
a rule asking someone to remember, every time.

**Growing CANON is expensive.** It loads in every session of every project, so
each added line taxes all of them. A change that adds to CANON should either
remove something or state why it earns its place.

## Procedure

**1. Pick the scope** — ask, do not assume:
- this conversation only
- recent sessions plus this one
- the library itself, with no conversation analysis (a standalone health pass)

**2. Gather.** For the transcript scan, spawn a background agent; it is a lot of
reading and its findings compress well. Have it return categorized findings
with a quote and a date for each, never raw dumps.

**On a standalone health pass there are no transcripts, and the evidence is the
library itself.** Six checks, each producing findings with a count instead of a
quote.

**Run `skills/sharpen/check-claims.sh` first.** It does the mechanical part of
three of them — paths that no longer resolve, counters that have gone stale,
versions that have split, rules missing the frontmatter the loader reads, labels
declared but never created. Doing those by hand is how they get skipped: in one
audit round each was run manually, from memory, three separate times. What it
reports is fact, not candidate; go to the reading below with its output already
in hand, and spend the attention on what it cannot see.

- **Rule clusters.** Group the rules by what they guard against. Two rules
  guarding one thing is a candidate; three is a skill defect.
- **Unreachable material.** Anything defined and consumed by nobody: a section
  of an agent no skill can reach, a field nothing reads, an artifact nothing
  writes. A skill invoked only by a person is *reachable* — that is what a skill
  is — so judge a skill by whether the person can find it, and an agent's
  sections by whether any skill routes to them.
- **Dangling references.** Every file, label, mode, tool and artifact a skill
  assumes exists. Check each one exists. `check-claims.sh` covers files and
  labels; modes, tools and artifacts are named in prose and are yours to read.
- **Disagreements.** The same fact stated in two files, then compared.
  `check-claims.sh` covers the countable ones. A disagreement in *meaning* — two
  skills that would route the same work differently — is invisible to it.
- **Host fingerprints**, per `rules/craft/library-skills-declare-taxonomy-rather-than-hardcode-it.md`.
  Grep case-insensitively; that is how the last one survived a sweep.
- **A cold read.** Walk three real tasks through the library as written and note
  the exact line where the instruction runs out. Spawn this one as an agent and
  forbid it the git history — the author cannot tell "this is clear" from "this
  is clear to me because I remember the deleted sentence", and a reader with no
  history can.

A health pass reports what it did *not* check as well. A sweep claiming
completeness it does not have is worse than a narrow one, because the gap it
leaves is now believed to be covered.

**3. Promote only what repeats — from transcripts.** One correction is noise:
the user changed their mind, or the situation was unusual. **The same friction
twice is a candidate.** Say how many times each was seen; that count is what
makes the proposal arguable rather than a matter of taste.

This bar is about *behaviour*, and it does not apply to a health pass. A
dangling reference seen once is not noise, it is a defect — the six checks
produce facts about the library, and a fact needs no second sighting.

**4. Check the last run landed** before proposing anything new. A change
accepted and never applied is worth more than a new idea — it is already agreed.

**5. Show the whole ranked list, then apply one at a time.** These are two
different things and conflating them is what makes this skill expensive.

Present every candidate in one pass, ranked, each carrying a strength — `Strong`
/ `Worth exploring` / `Speculative` — the evidence with dates and counts, and
one line on what breaks if it is not done. Close with the one you would take
first. That is a single decision for the owner instead of N, and seeing the list
whole is what lets them rank it differently than you did.

Then draft, agree and apply **one change at a time**. A batch of twelve edits
gets rubber-stamped or refused wholesale, and either way nothing was decided.

**6. Log the outcome** — append to the host's own sharpen log, at the location
its CLAUDE.md declares; create it on first use. Record date, proposal,
decision, and for a modification, what changed. **Read it in step 1, before
gathering anything** — it is listed last because it is written last, and read
first because a proposal already refused is not worth re-costing.

The file may not exist yet; on the first run, create it. Absent is the first
run, never a signal that the log was cleared.

The log is what stops the skill re-proposing what was already refused. It also
teaches style: if softened wording keeps getting accepted where absolute wording
gets rejected, propose softer wording for anything non-critical.

## When the pass is over

A health pass ends when all six checks have run and their findings are ranked —
not when the list is empty, which it never is.

Applying ends differently: **one change, then stop and report.** Each landed
change moves the library the next finding was measured against, and a list
carried on past the first fix is a list about a repository that no longer
exists. Re-run the checks rather than working down a stale ranking.

## The prune pass — a rule layer only grows unless something shrinks it

Every incident files a rule and nothing retires one. That is a ratchet, and it
ends in a layer nobody finishes reading — which costs more than any single rule
in it was ever worth, and fails silently: nothing errors, the wall of text just
gets skimmed.

**The trigger is a count, not a calendar.** `rules-loader.sh` warns when a scope
it is loading holds more than ten rules. A quarterly reminder is a thing
somebody has to hold, and that is the failure this library exists to end.

Run it on **one scope**, the one that warned. A pass over every scope at once
produces a batch too large to review, and an unreviewed batch of deletions is
the one outcome this must never produce.

### Four verdicts, and every rule gets exactly one

| Verdict | When |
|---|---|
| **Keep** | The incident can recur, the rule is the only thing preventing it, and nothing else says the same |
| **Merge** | A neighbour states nearly the same law. One file absorbs the other's incident into its origin and sharpens the wording — two rules saying nearly the same thing is how a rule set stops being read |
| **Absorb** | A gate could enforce it. Write the guard case or the check, then the file goes — a rule a machine can enforce is a rule that will eventually be forgotten instead |
| **Retire** | The incident cannot recur: the tool changed, the practice changed, or the behaviour is baked into a skill's own text now |

**Retirement is deletion, not an archive.** A retired-rules directory is a
second layer with the same growth problem and no reader at all. Git has the
history, and the rule's own file is the only place anyone ever looked.

### What is never a reason to retire

- **Nobody has hit it lately.** That is the rule working.
- **It reads as obvious.** It reads as obvious *because* the incident is in the
  past. Check the cost field before believing this one.
- **It is inconvenient.** A rule you keep arguing with is a rule whose incident
  you have not read.

### How the batch lands

**Every verdict, in one message, before anything is touched.** Name each rule,
its verdict, and the one-line reason. Deleting a rule discards evidence somebody
paid for, and that is the owner's call rather than the pass's.

Apply only what is approved, then re-run the loader against that scope to
confirm the warning is gone — or that it is not, which is also an answer.

## Two things that are not evidence

**A changed mind.** Users are allowed to want something different than they did
last week, and recording that as friction produces a rule against the user.

**Importance felt at the moment of proposing.** Everything seems important while
it is costing you something. The count from step 3 is the check on that, which
is why the count is stated rather than implied.
