---
rule: a command that exited 0 proves only what it tested — before reporting, say the claim out loud and check the command actually asked that question
scope: process
canon: 3
evidence: "two false statements in one session: a commit was reported as pushed on the strength of `git commit` succeeding, and two cached plugin versions were reported as in use because a marker path existed, when that path is a directory of per-PID lock entries and both were empty. Both reached the person reading the report as finished findings, one of them inside a filed issue, and had to be corrected rather than amended"
---

A green command is evidence for the question it asked and for nothing beside
it. Before stating a result, say the claim in words, then look at the command
that is supposed to support it and check the two are about the same thing.
Existence is not occupancy; a commit is not a push; a file being present is not
it being non-empty; a process running is not it doing the work.

**Why:** the substitution is invisible from inside, because the command *did*
succeed — there is no error, no truncation, nothing that looks like a gap. What
is missing is a step that leaves no trace when skipped: reading the claim back
against the check. Canon §3 says run the proving command and read its output,
and both failures behind this rule obeyed that literally. A command ran, its
output was read, and it proved a neighbouring fact. So "did I verify this" is
the wrong self-question and answers yes; "does this command answer *this*
sentence" is the one that catches it.

It is worst where the proxy is nearly always right. A marker path usually does
mean the thing is held, a successful commit is usually followed by a successful
push — so the shortcut is reinforced every time it works and fails only in the
case that matters. Habit is the mechanism, not haste: the second claim here was
made carefully, with a command, in a session already being careful about
evidence.

**How to apply:** write the sentence you are about to report, then name the
command under it. If the sentence contains a word the command never evaluated —
*held*, *pushed*, *empty*, *running*, *all* — that word is unverified and either
gets its own command or leaves the sentence. Prefer checks that answer the claim
directly: count the entries rather than test the directory, read `git status`
against the remote rather than infer from the last command, ask the thing itself
rather than its marker. When a report has already gone out, correct it plainly
and say what the command actually proved.

**Related:** Canon §3 is the general form, and this is one of several ways to
satisfy it literally and still be wrong. The others share the shape: output
truncated by `head` or a line limit read as a statement about the whole set, and
a decision about what to do read as an observation of what is. In each the
answer is real and the question is not the one being reported on.
