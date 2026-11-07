# The work's item — what a plan is

A plan is not a document beside the work. It is the work's **item**:
`.orrery/work/<work>/item.md`, in the work's own tree, beside its handoff and
its record. `frame` may already have written its Goal and Out of scope;
`plan` drafts into it and keeps both; `build` reads it. Nothing else is a
plan's home — not a folder of the project's, not a tracker. Where a tracker
adapter is configured, what it mirrors of the item is the adapter's business, never a skill's.

## What it records, and what it leaves out

It records what an implementer needs in order to decide nothing again: every
decision with the alternative it beat, every task's acceptance criteria and the
command that checks it, signatures, assertions and spec values where a task
turns on one.

It leaves out code. A function body, a full test, a patch: each is a second
implementation that nobody reviews as code, and it drifts from the first the
moment the build starts. A signature, an assertion or a value is a decision; a
body is not.

## The sections, in order

```
# <title>

Route: inline | pair | consensus. Mode: standard | DELIBERATE. Attempt: <n>
Parent: <feature>                      (a task of a feature only)

## Goal                  one sentence the owner agreed to, or marked Not agreed
## Out of scope          what this work will not touch, and where it went
## Decided               decision | the alternative it beat | why
## Tasks                 what · acceptance · the checking command · depends on
## Assumptions           assumption | VERIFIED / REASONABLE / FRAGILE | evidence
## Spike results         the fact, and the command that produced it
## Ruling                each checker's verdict, and how each finding was answered
## Consequences and follow-ups
## Ship when             the condition, as commands where it can be
## Open questions        precise questions, answered at build and logged
## Not yet specified     what is coming but cannot yet be phrased
```

What each must hold, by route and mode:

- **Always:** tasks with acceptance criteria and per-task dependencies, and the
  **Assumptions** table. The checkers verify that table rather than rebuilding
  it, which is where the time goes. **VERIFIED means a command was run, its
  output was read, and the command is written beside the assumption.** Without
  one the entry is REASONABLE at best — a rating applied to a prediction after
  reading the code is Canon §3 suspended at exactly the point where it decides a
  design. FRAGILE that the design rests on is the trigger for `plan`'s §Spike,
  not a label to ship.
- **`consensus` only,** inside *Decided*: principles (3-5), decision drivers
  (top 3), options (2+, or what invalidated the rest), and a pre-mortem of three
  concrete failure scenarios, each naming what would have had to be true. On
  `pair` the approach is known by definition — demanding alternatives there
  manufactures the token ones the critic is supposed to reject.
- **DELIBERATE only:** a test plan spanning unit, integration, end-to-end and
  observability.
- **When a spike ran:** its result as a fact, with its command. A plan that
  turns on an unread number and carries no command is redrafted, not checked.
- **`inline`** writes no item beyond a Goal and one line naming the decision and
  why the route was inline.

The ADR a plan used to carry lives here: Decision, the alternative and why are
*Decided*; Drivers are *Decided* on `consensus`; Consequences and Follow-ups
have their own section.

## Attempts

`Attempt:` counts drafts of this work's plan. A new draft after the critic's
two-iteration cap increments it; `plan` reads it before drafting and never
writes attempt 3 — two plans for one work means planning is not what the work
is short of, and the next move is a spike or a build. A parent's item is never
an attempt for its tasks.

## A feature of several tasks

One work is one branch, landed as one pull request where the code host has
one. A feature larger than that is planned in one work named after the
feature, which writes:

- `.orrery/work/<feature>/item.md` — the feature's goal, scope and decisions;
- one `.orrery/work/<task>/item.md` per task, **self-contained**: its goal, the
  decisions it rests on copied in rather than referenced, its criteria and
  checks, and `Parent: <feature>` as provenance only.

The planning work ends at its own landing — `auditor`, record — and builds
no task. Each task's work is then created with exactly the task's name, so its
record lands beside its item.

**Where the project ignores `.orrery/work/`**, items are in no branch, and the
planning work cannot hand them to later ones. There a feature is planned one
task at a time: each task's work plans and builds its own item.

Where records are tracked, when the last task merges, its work writes the feature's record, summed from
its children's records, with `record.sh write --body-file <path> --work
<feature>`. That replaces the planning work's record at
`<feature>/retrospective.md`, so it counts the planning work's measured stages
as one of its children — read them before writing, and never count the summed
record itself. Where records are ignored there is no planning work and no
parent record: each task's record is the whole account of its part.
