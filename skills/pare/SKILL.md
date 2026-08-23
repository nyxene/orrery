---
name: pare
description: Take the smallest solution that actually works. Invoke when writing, adding, refactoring, or designing anything, and whenever a proposal has grown a layer nobody asked for. Not a licence to skim — understanding is never what gets shortened. Not for deciding how much review a change earns (use `plan`); this governs the size of the solution, never the size of the check on it.
argument-hint: "[what you are about to build]"
---

# Pare — The Smallest Thing That Works

**Canon §4 owns the ladder. This is how each rung is applied.** Where the two
disagree, Canon is right and this file is stale.

The most expensive code is the code that did not need to exist. It is never
deleted, because deleting it requires understanding it, and understanding it
costs more than leaving it.

## The ladder

Stop at the first rung that holds. Do not survey the rest.

1. **Does this need to exist?** A need that has not happened yet is a guess.
   Say you skipped it and move on.
2. **Does this codebase already have it?** A helper, a type, an existing
   pattern. Re-implementing what lives three files over is the single most
   common form of waste, and it is invisible in review.
3. **Does the standard library do it?**
4. **Does the platform do it?** A date input over a date-picker library, CSS
   over JavaScript, a database constraint over application code.
5. **Does an already-installed dependency do it?** Never add a new one for
   something a few lines cover.
6. **Can it be one line?** Then it is one line.
7. **Only now**: the minimum that works.

Two rungs both hold? Take the higher one and stop deliberating. The first
solution that works is the right one.

## The ladder shortens the solution, never the reading

This is the part that gets dropped, and dropping it is how a small diff becomes
a confident wrong answer.

Read the whole flow first — every file the change touches, how the data
actually moves, who calls what. *Then* climb. A minimal change in the wrong
place is not lazy; it is a second bug wearing the costume of restraint.

## The lazy fix is the root-cause fix

Canon §5 requires it. This is the part that makes it cheap rather than virtuous:
one guard in the shared function is a **smaller** diff than a guard in each of
six callers.

Fixing the symptom is not the fast option. It is the option that ships five more
of the same bug.

## Rules

- **No abstraction with one implementation.** No interface with a single
  implementer, no factory producing one thing, no configuration for a value
  that has never changed.
- **No scaffolding for later.** Later is perfectly capable of scaffolding
  itself, and it will know more than you do now.
- **No error handling for impossible states.** Handling what cannot happen
  makes it harder to see what can.
- **Deletion beats addition.** The best version of a diff is often a smaller
  one than the one you started with.
- **Boring beats clever.** Clever is what somebody decodes at 03:00.
- **Fewest files.** Every new file is a thing to find later.
- **Match the surrounding code**, including where you would have done it
  differently. A file written in two dialects is worse than one written in the
  dialect you dislike.

## Never pare away

These are not complexity. Cutting them is not laziness, it is damage:

- Validation at a trust boundary
- Error handling that prevents data loss
- Security measures
- Accessibility basics
- Anything explicitly asked for — and if the user insists on the larger
  version after hearing the smaller one, build the larger one without
  relitigating it

## When you cut a real corner

Some simplifications carry a known ceiling: a global lock, a linear scan that
becomes quadratic, a heuristic that is right most of the time. Those are fine —
they are choices, not accidents.

File them with `debt` at the moment you make the choice, naming the ceiling and
what would raise it. Not at the end of the task: by then the reason is gone,
and a shortcut whose reason is gone is indistinguishable from a mistake.

## Output

Code first. Then at most three lines: what you skipped, and what would make it
worth adding.

If the justification runs longer than the code, delete the justification.
Every paragraph defending a simplification is complexity smuggled back in as
prose.

The exception is explanation that was asked for — a report, a walkthrough, a
rationale. That is the deliverable, not padding, and it gets written in full.
