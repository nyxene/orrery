---
name: sharpen
description: Improve the library itself from accumulated evidence. Invoke periodically, or at the end of a session that went badly — reads corrections and friction from past sessions, finds the patterns, and proposes changes to canon, skills, agents, rules or guards, one at a time.
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
2. **Session transcripts — all of them** — `~/.claude/projects/<project>/*.jsonl`.
   Extract **user messages only**; assistant output and tool results are noise
   here and enormous. Filter for feedback signals: corrections ("no", "don't",
   "actually", "wrong", "instead"), friction ("again", "I already said"),
   explicit asks ("next time", "I wish", "should"), and approval ("exactly",
   "yes, that"). Approval matters — it tells you what to protect.

   **Every file, or say how many you read.** This step said "recent" once and
   named no number: a pass took the newest six of nineteen, and every count it
   produced was low by roughly a factor of three — enough to change the ranking
   and to miss the strongest evidence in the corpus. Nothing had escalated; the
   corpus was older than the reader. Step 3's bar is a count, and a count from
   an unstated denominator is not a measurement. If the whole set is genuinely
   too large, that is a number to report, not a decision to make quietly.
3. **The call log.** `.orrery/local/calls.tsv` in the main checkout, written by
   `hooks/call-log.sh`, holding no content at all: timestamp, session
   fingerprint, tool, subagent type, whether the spawn was named, the event —
   `call` or `ran` — and the harness's id for the call. It is on unless
   `.orrery/config.json` says `"callLog": false`; switched off is not a finding.

   **Read the pair, not the row.** `ran` is written only when a tool succeeds, so
   a `call` with no `ran` under the same id did not run — refused by a guard, by
   the permission classifier or by the person, or errored, or interrupted, and
   the log cannot tell those apart. Count rows and every number doubles. Lines
   written before the event field arrived have five fields and no event; read an
   empty sixth field as `call`.

   It answers what a transcript answers badly and what a skill cannot answer
   about itself. Group by the session fingerprint and read the shape:

   - **Commands ran against a plan and no checker was ever spawned.** The case
     this log exists for. `plan` requires a spike where an answer cannot be read,
     and says in prose that a spike does not replace the review — prose that
     nothing enforces. Each such session is one time it did not hold.
   - **How often a checker runs at all**, as a fraction of the sessions that
     produced a plan. A ratio, not a count: the denominator is what makes it
     mean anything.

     **The denominator is the hard half, and it is not in this log.** Drafting
     is not an agent — `plan` writes in the session that invoked it — so no
     spawn marks a session as having planned, and the log records no content
     that could. Until something does, count the plan documents written in the
     window and say that is what you counted. A ratio whose denominator came
     from a different source than its numerator is worth stating as two numbers
     rather than one fraction.
   - **How many agents a piece of work cost**, which is the number the route
     table is spending and has never been able to see.

   A skill cannot record the run in which it ignored its own instructions — the
   same omission removes the behaviour and the evidence of it. That is why this
   is read here rather than reported by the skill it is about.

   On a handful of sessions this is noise with a shape, not statistics. Say "in
   this project, after that change, the ratio moved" and never "the change
   works".

   **And the waiver log** — `.orrery/local/waivers.tsv`, beside it — where every deliberate skip of a gate is a row with its
   reason. Read the reasons, not only the count: a waiver whose reason is an
   agent's own judgement rather than the owner's words is the skip the gate
   exists to stop.

4. **The rule set itself** — clusters are the real signal. See below.
5. **What the last run promised.** Every accepted change from the previous
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

**1. Read the sharpen log, then pick the scope.** The log first, before
gathering anything — step 6 says why. Then the scope: ask, do not assume:
- this conversation only
- past sessions plus this one — all of them, per the list above
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

**And a candidate is not a finding until the other side is read.** Step 2 takes
user messages only, which is right for *detecting* friction and not enough to
*establish* it: a complaint is what the owner perceived, not proof of what the
agent did. Before ranking a candidate, open the assistant turns around at least
two of its occurrences and confirm they are what the complaint says. The reading
is targeted at known timestamps, not a second sweep.

The one finding that ever got this treatment lost four of its six. Two were the
owner misremembering, one was a question that had genuinely never been answered,
and one rested on a premise that was false — leaving a single occurrence, which
this same bar calls noise. An unaudited count carries the authority of a
measurement and the content of an impression, and it is spent on the scarcest
thing there is.

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

**A correction is not a change.** That rule is about decisions. Where the
project states something about itself that the disk contradicts, there is
nothing to decide — the fix is what the file already says — so corrections go
as one batch and the batch is one item on the list. Anything whose fix could
reasonably be written two ways is a change, and goes alone.

**6. Log the outcome** — append to the host's own sharpen log, at the location
its `.orrery/config.json` declares as `sharpenLog` (default `.orrery/sharpen-log.md`,
inside Orrery's own folder); create it on first use. Record date, proposal,
decision, and for a modification, what changed. **Read it in step 1, before
gathering anything** — it is listed last because it is written last, and read
first because a proposal already refused is not worth re-costing.

The file may not exist yet; on the first run, create it. Absent is the first
run, never a signal that the log was cleared — but look for one at
`docs/sharpen-log.md` first, where it lived before: if the project declared no
`sharpenLog` and that file is there, `git mv` it to `.orrery/sharpen-log.md` in
this pass, and read it as the history it is.

The log is what stops the skill re-proposing what was already refused. It also
teaches style: if softened wording keeps getting accepted where absolute wording
gets rejected, propose softer wording for anything non-critical.

## When the pass is over

A health pass ends when all six checks have run and their findings are ranked —
not when the list is empty, which it never is.

Applying ends differently: **one change, then stop and report.** Each landed
change moves the library the next finding was measured against, and a list
carried on past the first fix is a list about a repository that no longer
exists. Re-run the checks rather than working down a stale ranking. A batch of
corrections is the one change, by the carve-out above — it moves nothing that a
finding was measured against.

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
