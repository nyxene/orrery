---
name: frame
description: Turn a vague idea into a stated goal by asking, before any planning starts. Invoke when the request is a wish rather than a task — "something for X", "I want it better", "we should probably" — or when you notice you are about to guess what someone meant. Ends with one sentence they agree with, written into the work's item.
argument-hint: "[the rough idea, however vague]"
---

# Frame — Find the Goal Before Planning It

Planning a misunderstood goal produces an excellent plan for the wrong thing,
and it fails late — after the work, when the cost is highest. This skill spends
a few questions up front to avoid that.

Not brainstorming. Brainstorming diverges — many ideas, no judgement. This
converges: one goal, stated, agreed.

## The one rule that carries the skill

**One question per turn.** Two only when they are genuinely the same question.

A batch of five gets five shallow answers, because the person starts optimizing
for finishing the list rather than for thinking. One question gets a real one,
and the real one usually changes what you would have asked next — which is the
entire point of asking in sequence.

## Every question ships with your recommended answer

Not a survey — the answer you would pick, and why, with its alternatives shown.

A choice makes them decide. A recommendation lets them **ratify**, which is
cheaper still, and it puts your model of the problem on the table so they can
correct the model rather than just the answer.

It also disciplines you. An agent obliged to attach a recommendation to every
question discovers, while composing it, which questions it had no business
asking.

Use `AskUserQuestion`, 2-4 genuinely distinct options with the recommended one
first. Three shades of the same answer is not a choice, and a rejected option is
still information — "neither, actually what I want is…" is often the most useful
sentence in the exchange.

## Ask only what only they can answer

Canon §6 stands here. **If a question has a right answer, it is not a question
for them.** Facts are yours to find — the code, the manifest, the history, a
search. Decisions are theirs: the problem, the priority, the taste, the risk
they accept.

**Skip the question exploration already settled.** An unnecessary question costs
the same attention as a necessary one, and asking what you could have read
spends their attention on your homework.

## The order is derived, not fixed

Five things need establishing. The order they get asked in comes from what
depends on what, not from this list.

1. **The problem, not the requested solution.** People describe solutions.
   Under every solution is a want, and it is frequently served better by
   something else.
2. **Whose problem it is.** "Users" is not an answer. Which ones, doing what.
3. **What done looks like.** Something observable. If nobody could tell whether
   it happened, it cannot be built.
4. **What is explicitly out.** The cheapest question in the set, and the one
   that prevents the most rework.
5. **Which constraints are real.** Deadline, budget, compatibility — and which
   are assumed rather than actual.

Ask what nothing else is waiting on. Each answer settles some of the rest and
makes others moot — drop those rather than asking them anyway. A fixed order
asks question 4 after the answer to question 2 already killed it.

### The why-ladder

When they answer with a solution, ask what it would let them do. Repeat.

> "I want a dashboard." → what would you do with it?
> "See which jobs failed." → and then?
> "Rerun them." → so the goal is rerunning failed jobs, and a dashboard is one
> way to reach it.

Stop climbing when the next answer is obviously terminal. Two or three rungs is
usually the whole ladder; more than that and you are interrogating.

## Stop condition

You can state the goal in one sentence, and they agree with it.

That sentence *is* the deliverable. Say it back and get a yes before going
further — a goal you inferred but never confirmed is still a guess, just a
better-dressed one.

**If they are away, do not block on the yes** (Canon §7). Away means the
session runs without them, or a question has gone unanswered. Take your own
reading, write it as the goal, and mark it unagreed (below), so the first person
to read the item sees it is a guess and whose. A reading taken in their absence
is a goal, not consent to build (Canon §1).

## The cap

If seven or so questions have not produced a goal, stop asking. Say plainly
what is still unclear and what you would assume in order to proceed. Endless
questioning is its own failure — it feels diligent and reads as stalling.

## Then hand off

Once the goal is agreed, or taken in their absence:

1. **Write it into the work's item**, `.orrery/work/<work>/item.md`, in the
   work's own tree — `<work>` is the worktree's name, or the branch on the main
   checkout. Two sections, in the form `skills/plan/item-format.md` gives:
   - `## Goal` — the sentence. If they were away, add the line
     `Not agreed: the owner was away; this is the reading taken.`
   - `## Out of scope` — what was ruled out, and where each piece went.

   Create the file if the work has none, and leave every other section to
   `plan`. The conversation is lost at the next reset; the item is not, and
   `plan` keeps the Goal and Out of scope it finds there rather than
   re-deriving them.
2. Offer 2-3 approaches with real trade-offs, carrying your recommendation the
   same way every question above did. If they are away, take your
   recommendation and say so in the item, under the Goal.
3. Hand to `plan`. It prices the work itself — a reversible change of one file
   plus its tests, whose approach is obvious, takes its `inline` route and
   spends no checker — so there is no judgement to make here about whether the
   work is "big enough".

The thinking behind the sentence matters as much as the sentence. Whatever of
it the plan will need — a constraint they named, a reading they rejected —
goes into the item with the Goal, not only into the conversation.

## The one guardrail

Keep the goal theirs until it is agreed. Proposing a solution first anchors
them, and from then on they answer about your idea rather than their problem —
which produces agreement that means nothing.
