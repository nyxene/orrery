---
name: handoff
description: Carry session residue across a context reset. Invoke when you learn something the next session would otherwise rediscover the hard way — a dead end, a half-applied change, a decision the diff does not show — and when picking work back up. Writes .orrery/work/<work>/handoff.md in the work's own tree.
argument-hint: "[resume] — omit to write a handoff; 'resume' to pick one up"
---

# Handoff — What the Next Session Cannot Reconstruct

A session ends and everything in it is gone. The plan still says what to do,
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

**`.orrery/work/<work>/handoff.md`, in the work's own tree** — `<work>` is the
worktree's name, or the branch on the main checkout. One file per
piece of work, replaced each time, and deleted when the work closes:
`skills/build/record.sh write --final` and every `record.sh close` remove it.

| Why | |
|---|---|
| Costs nothing until needed | Nothing loads it; `resume` reads it deliberately |
| Cannot go stale unnoticed | Closing the work deletes it, so a handoff that exists is for open work |
| Scoped automatically | It sits beside the work's record, in the tree the work happens in |
| Travels with the branch | Committed with the work by default, it survives the machine and reaches whoever picks the branch up |
| Needs no tracker | It is a file, so a project with no tracker, or one at work that uses none, has the same handoff |

It is committed like the rest of `.orrery/work/` unless the project ignores that
directory in its own `.gitignore` — then it is in no branch, and a hook copies it,
each time it is written, to the main checkout's `.orrery/local/work/`, where it
outlives its worktree. Committed, it is never merged: the record deletes
it before the final push.

### Finding it

`resume` runs in a session that has no context by construction, so this cannot
be left to memory. In order, stopping at the first that answers:

1. **This tree.** `ls .orrery/work/*/handoff.md` from where the session stands.
2. **The worktrees.** `ls .claude/worktrees/*/.orrery/work/*/handoff.md` from the
   main checkout. One result is the answer; several mean you have to pick, so
   print each with its work's name rather than guessing.
3. **The archive.** `ls .orrery/local/work/*/handoff.md` from the main checkout,
   where the project ignores `.orrery/work/`. One whose worktree is gone is
   history, not work to resume: say so, and resume it only on the owner's word.
4. **Ask.** Cheaper than resuming the wrong work.

**Nothing to hand off?** The test is whether the work closes. Name what is
outstanding and what would finish it; if you cannot, there was no work to hand
off and the session should end with nothing. Not every session leaves residue,
and one that leaves none should leave none.

## Mode 1 — write (default)

Write `.orrery/work/<work>/handoff.md` with exactly these four, nothing else,
**30 lines is the ceiling**:

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
The resuming session has lost the context that would tell it which skill
fits.

State behaviour, not coordinates: `SkillConfig should accept an optional
schedule field`, never `open src/types.ts, line 42`. The note may sit for days
while the code moves underneath it, and a line number is the first thing to rot.

### Redact before writing

The file is committed and pushed with the work — remote, permanent in history,
and readable by anyone who can read the repository. Section 1 asks for concrete state, and concrete
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

Carrying it forward means reading it first. Read the file before rewriting it
and copy its dead ends across.
A second handoff written without looking at the first silently drops the one
section the skill exists to preserve.

That exception, and the flagged follow-up below, are deliberate. Carrying
*everything* forward is precisely
how a handoff turns into a 100-line document that nobody opens.

**If the tried-and-failed list passes four entries, stop and say so.** Four
failures is evidence the approach is wrong, not that the next variant will
work. `architect` and `diagnose` stop at three failed *fixes* of one cause;
four *approaches* is the looser bound because each one was a different idea.
Raise it rather than adding a fifth line.

### Never write

- The roadmap. That is the plan, or the issue where the project keeps one.
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

1. Read the file found above. There is only ever one per piece of work; git
   history holds the earlier ones, and they stay unread.

2. **Verify before trusting it.** A handoff describes a past state, and the
   world moved: the branch may be gone, the PR may have merged, someone may
   have fixed it. Check the actual state — `git log`, `gh pr list` where there is a tracker, the file
   itself — before acting on a single line of it.

   A stale handoff followed confidently is worse than no handoff, because it
   carries authority it no longer earns. Canon §3 applies here exactly as it
   does to test results.

3. State what you found: what still holds, what has been overtaken, what you
   are doing next. Then start.

## A flagged follow-up comes back until it is closed

Some things are not residue and not a dead end: they are an open item somebody
explicitly flagged and nobody closed. Those get raised **again**, in every
session where they are relevant, without waiting to be asked — and they keep
being raised until the item is closed or the flag is withdrawn.

The failure this prevents is quiet: an item mentioned once, agreed to be
important, and never spoken of again. Nothing errors. It simply stops existing,
and the person who flagged it assumes it is in hand.

Beside the dead ends, this is the only thing that survives a handoff being
rewritten. It rides at the end of section 1 as `Still flagged: <item> — …` (its issue
number where one exists), one line each. Everything else in the note replaces; a flagged open follow-up carries forward the way a dead
end does, for the same reason — it costs one line and its absence costs the
item.

## When to write nothing

If the next session can reconstruct everything from the plan and the diff,
write nothing. Not every session leaves residue, and a handoff with no dead end
in it is a handoff with no payload.

The tell that one has gone wrong is the phrase **"carried over"**. By the second
time it appears, the note has become a document that accretes instead of a note
that replaces.
