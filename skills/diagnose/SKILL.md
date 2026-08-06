---
name: diagnose
description: Find the cause of a bug or a performance regression, starting from a command that can prove it is gone. Invoke on "diagnose", "debug this", "why is this failing", "it's slow now", or any report that something is broken, throwing, hanging, or wrong. Not for proving a fix afterwards — that is `verify`.
argument-hint: "[the symptom, in the words it was reported in]"
---

# Diagnose — The Loop Before the Theory

This skill spends its first move building a command that goes red on the bug,
and it will not let you read code to build a theory before that command exists.

Reading first feels faster and is where debugging sessions die. A theory formed
from reading has nothing to disagree with it, so it survives every subsequent
observation by quietly reshaping itself — and the session ends with four
plausible explanations and no way to choose between them.

## The gate

**No red command, no hypothesis.** Before any theory about the cause, you have
run a command that fails *on this bug*, and you can paste its invocation and its
failing output.

It has to clear `verify`'s four conditions — red-capable, deterministic, fast,
runnable unattended — with one inversion: there, red-capable means it *would*
fail if the claim were false; here it means it **fails now**, and you have the
failing output in front of you.

If you catch yourself opening files to work out what might be wrong, stop. That
is the failure this skill exists to prevent, and it is the one that feels most
like progress.

## When no loop exists yet

Build one, cheapest first. Stop at the first rung that goes red.

1. **A test that already fails.** Run the suite before assuming there isn't one.
2. **A new test at the level the symptom appears.** Not the level you suspect —
   the level it was reported at.
3. **A script through the real entry point.** A `curl`, a CLI invocation, the
   actual command the user ran.
4. **A script driving the code path directly**, when the entry point is too
   expensive or needs credentials you should not be handling.
5. **An assertion over output.** Run the thing, grep its logs for the symptom,
   exit non-zero when it appears. Crude, and it counts.
6. **A scripted human loop**, only when a person genuinely has to click. Write
   the prompts out and capture the answers as values, so iteration seven costs
   them the same three keystrokes as iteration one. A human asked to
   "try it again and tell me what you see" is being asked to re-explain the
   setup every round.

The loop is the deliverable of this phase. Say which rung you landed on.

## Minimise before theorising

Cut the reproduction down until nothing more can be removed and it still goes
red. Fewer inputs, fewer steps, less data, one thread.

Every element you remove is a cause eliminated for free, without a hypothesis
and without an argument. What is left when you cannot cut further is usually the
answer, or one file away from it.

## One hypothesis, written down, before digging

State it in a sentence and commit to it in writing. An unstated hypothesis
reshapes itself to fit whatever turns up next, and you lose the ability to be
wrong — which is the only thing that makes the investigation converge.

Then test it against the code, citing `file:line` for each step of the argument.
Canon §5 applies: you are looking for the mechanism, not the line where the
symptom surfaced.

Where the mechanism is genuinely unclear after a real attempt, spawn `architect`
— diagnosing to a root cause with `file:line` behind every step is what that
role is for, and it reads the code fresh. Its brief names the mode, as every
brief does: this is a diagnosis, not a plan review, so there is no antithesis
to argue and no DELIBERATE additions to carry. That is a cheaper move than a fourth
hypothesis of your own.

## Fix it, at the size the cause turns out to be

The cause decides the shape of the change, and the loop already told you where
it is:

- **Local and obvious** — fix it here, and add the regression test in the same
  change.
- **Shared by callers** — Canon §5 governs: one guard where they all route
  through, not one per caller. This is usually still small.
- **Structural** — the fix changes an interface, a boundary, or several files.
  That is no longer a bug fix. Stop, and hand it to `plan`; the routing there
  will decide how many checkers it earns.

The regression test comes from the loop you already built. If the loop was a
throwaway script rather than a test, this is where it becomes one — a bug that
was reproducible once and is not pinned will return unannounced.

## Instrument rather than speculate

When reading cannot settle the hypothesis, add a probe. A log line, a counter, a
timing bracket, a breakpoint condition — something that makes the loop print
what you need.

Two rounds of "maybe it's…" cost more than one probe. Remove every probe before
you finish; a probe left behind is a change nobody planned.

## Three failed fixes means the model is wrong

After the third fix that does not work, stop producing variants. Three failures
is evidence the model of the problem is wrong, not that the fix needs another
tweak. Go back to the loop and re-read what it actually reports.

`architect` stops at three failed recommendations for the same reason. `handoff`
raises its hand at four entries on the tried-and-failed list — a different unit,
a different count, the same principle: repeated failure is evidence about the
model, not about the next variant.

## Finish

- The regression test is **seen failing, then passing**. A test written after
  the fix and green on its first run has proven nothing about the bug.
- Probes and scratch scripts are removed. The loop stays if it is a test.
- The fix is proved with `verify`, not asserted here.
- A shortcut taken to get there is filed with `debt` at the moment it is taken.
- If the cause was a way of working rather than this code, it is a `learn` rule.
