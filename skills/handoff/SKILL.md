---
name: handoff
description: Carry session residue across a context reset. Invoke when you learn something the next session would otherwise rediscover the hard way — a dead end, a half-applied change, a decision the diff does not show — and when picking work back up. Writes to the task's GitHub issue, not to a file.
argument-hint: "[resume] — omit to write a handoff; 'resume' to pick one up"
---

# Handoff — What the Next Session Cannot Reconstruct

A session ends and everything in it is gone. The issue still says what to do,
the diff still shows what changed, git still has the history. What vanishes is
the part that lived only in the conversation: **the approach you already tried
that did not work.**

That is the whole payload. Failed approaches evaporate on a context reset, and
the next session walks into the same wall at full speed, with full confidence,
because nothing tells it the wall is there.

**You are usually invoked by the reset itself.** `hooks/handoff-prompt.sh` stops
the first compaction of a session and asks for this, because for a long time
nothing triggered it at all: the trigger lived in this file's `description`,
which is read by someone already looking for it, and the session that most needs
a handoff is the one with no room left to notice. The hook fires once, so the
answer it gets is the only one. A person can still invoke this directly at any
time, and `resume` is always invoked by hand.

## Where it goes

**A comment on the task's GitHub issue.** Not a file.

| Why | |
|---|---|
| Costs nothing until needed | Nothing loads it; `resume` fetches it deliberately |
| Cannot go stale unnoticed | The issue closes, the note becomes history by construction |
| Scoped automatically | The residue sits with the work it belongs to |
| Chronology is free | The comment thread is the chain, in order, with dates |
| Actually backed up | Unlike a gitignored file living in one copy on one disk |

A repo file fails both ways: gitignored it is invisible and unbacked, tracked
it is a planning doc that never expires and accretes until nobody reads it.

### Finding the issue

Both modes need an issue number, and `resume` runs in a session that has no
context by construction — so this cannot be left to memory.

In order, stopping at the first that answers:

1. **The branch.** `gh issue develop` names branches after their issue, so
   `git branch --show-current` usually carries the number.
2. **The open PR.** `gh pr view --json body,number` — the body's `Closes #N`
   names it.
3. **The marker.** `gh issue list --state open --search '"<!-- orrery-handoff -->" in:comments'`
   finds every issue carrying a handoff. One result is the answer; several mean
   you have to pick, so print titles rather than guessing.
4. **Ask.** Cheaper than resuming the wrong task.

**No issue for this work?** Then the fix is an issue, not a file — but the issue
states **the work**, and the handoff is a comment on it. An issue whose whole
content is a handoff is a diary entry in a work tracker, and a tracker that
collects those stops being read for the same reason a rule set that only grows
does.

The test is whether it closes. Name what the outstanding work is and what would
finish it; if you cannot, there was no work to hand off and the session should
end with nothing. Not every session leaves residue, and one that leaves none
should leave none.

Not in a GitHub repo at all? Say so plainly rather than inventing a home — a
durable fact belongs in memory, and everything else can be lost.

## Mode 1 — write (default)

Start the comment with the marker line so it can be found later:

```
<!-- orrery-handoff -->
```

Then exactly these four, nothing else, **30 lines is the ceiling**:

**1. Stopped at.** Where the work actually is. Not "worked on the parser" —
"parser handles nested groups; the escape-sequence branch at `lex.rs:88` is
written but untested."

**2. Already tried, does not work.** One line each, each with *why*. This is
the section that justifies the skill existing.

**3. Decided, not visible in the diff.** A choice whose reasoning would
otherwise have to be re-derived. If it is durable rather than task-scoped, it
is a `learn` rule instead.

**4. Next step.** One concrete action, precise enough to start on without
re-reading anything — and the skill that action starts with, where one applies.
The resuming session has lost the context that would tell it which of the ten
fits.

State behaviour, not coordinates: `SkillConfig should accept an optional
schedule field`, never `open src/types.ts, line 42`. The note may sit for days
while the code moves underneath it, and a line number is the first thing to rot.

### Redact before posting

The comment lands on a GitHub issue — remote, permanent, and readable by anyone
who can read the repository. Section 1 asks for concrete state, and concrete
state is exactly where a token, a connection string or a customer's data gets
pasted without anyone deciding to.

Write the shape instead of the value: `DATABASE_URL, in .env.local` rather than
the URL; `the key was rejected with 401` rather than the key. The next session
needs to know which credential was involved. It never needs the credential.

### Replace, except one section

The newest handoff is authoritative; older ones are history. Everything gets
rewritten each time — **except "already tried", which carries forward.** A dead
end stays dead, and re-walking it is exactly the cost this exists to prevent.
It is also cheap: a dead end is one line.

Carrying it forward means reading it first. Fetch the previous handoff before
writing a new one — same command `resume` uses — and copy its dead ends across.
A second handoff written without looking at the first silently drops the one
section the skill exists to preserve.

That single exception is deliberate. Carrying *everything* forward is precisely
how a handoff turns into a 100-line document that nobody opens.

**If the tried-and-failed list passes four entries, stop and say so.** Four
failures is evidence the approach is wrong, not that the next variant will
work. `architect` and `diagnose` stop at three failed *fixes* of one cause;
four *approaches* is the looser bound because each one was a different idea.
Raise it rather than adding a fifth line.

### Never write

- The roadmap. That is the issue and the milestone.
- What was accomplished. That is the diff and the log.
- Rules or lessons. Those are `learn`, and they outlive this task.
- Anything carried over "just in case". If it matters and is durable, it goes
  to memory or a rule; if it is neither, let it go.

### When to write

**When you learn something worth carrying — not only at the end.** The end of a
session is the least reliable moment there is: budget spent, context already
compacted, and sessions frequently just stop. A handoff written at the moment
of the dead end survives; one planned for later often is not written at all.

## Mode 2 — `resume`

1. Fetch: `gh issue view <N> --comments`, take the **latest** comment carrying
   the marker. Earlier ones are history and stay unread.

2. **Verify before trusting it.** A handoff describes a past state, and the
   world moved: the branch may be gone, the PR may have merged, someone may
   have fixed it. Check the actual state — `git log`, `gh pr list`, the file
   itself — before acting on a single line of it.

   A stale handoff followed confidently is worse than no handoff, because it
   carries authority it no longer earns. Canon §3 applies here exactly as it
   does to test results.

3. State what you found: what still holds, what has been overtaken, what you
   are doing next. Then start.

## When to write nothing

If the next session can reconstruct everything from the issue and the diff,
write nothing. Not every session leaves residue, and a handoff with no dead end
in it is a handoff with no payload.

The tell that one has gone wrong is the phrase **"carried over"**. By the second
time it appears, the note has become a document that accretes instead of a note
that replaces.
