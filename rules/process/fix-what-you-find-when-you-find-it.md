---
rule: a defect you find is fixed in the same change, at whatever size it turns out to be — the only thing deferred is code outside this repository
scope: process
evidence: "a cheap, adjacent review finding was reflex-filed as debt instead of folded into the same PR; the same reflex later auto-filed a correctness-critical finding, deferring an output known to be wrong; a third time, a tool reporting a released file as free to change was found mid-task and offered as an issue rather than fixed"
---

Something that is **wrong** — a wrong answer, a check that cannot fire, a claim
the code does not keep, a guard that passes what it names — is fixed in the
change you are already making, the moment you find it: **inside the issue and
the pull request you are already in**, as its own commit if that reads better.
Not carried out to a new issue, not offered as one, not ranked against the task
you were doing.

**An issue is a record, never a deferral.** These are two different uses of one
word and confusing them is what this rule is for. Work happens under an issue —
everything that reaches the default branch is recorded in one — and that is the opposite of
filing something to avoid doing it. Fixing now and having a record are not
alternatives; a defect found inside a task belongs to that task's issue, and
only work that genuinely is not this task's earns one of its own.

**Size is not a reason to defer.** "This needs the whole thing rewritten" is a
statement about the fix, not about whether to make it. Say what it turned into
and keep going.

**The only exception is ownership, not cost.** Code outside this repository that
you do not control — a dependency, a third-party integration, someone else's
service — cannot be fixed here, so that one is reported. Everything inside is
yours and gets fixed.

Two things this does not license. **Dead code is still flagged rather than
deleted** (Canon §2): it is not telling anyone anything false, so it is not a
defect. And an *improvement* — code you would have written differently, naming
you dislike, a refactor you can see — is not a defect either, and Canon §2
still refuses it.

**Why:** the reflex being corrected is the safe-looking one. Filing an issue
reads as diligence, so it never feels like the failure it is: the defect stays
live, the person who would have to decide is handed work instead of an outcome,
and the moment when the whole context was in front of someone is gone. Every
recurrence has been a session choosing the tidy-looking option — including one
where the session named the defect's class correctly, knew what that class had
already cost, and proposed an issue anyway.

**How to apply:** when you notice it, you are already the cheapest person who
will ever fix it — you have the file open and the cause in hand. Fix it, prove
it with a command, and say in the report what you found and what it turned into.
Do not ask permission for the fix itself; the go-ahead for the task covers
defects found inside it. Ask only when the fix is genuinely outside the
repository, and then report rather than ask. If it changed the size of the work
substantially, that is a fact for the report, not a reason to stop.

**Related:** the rule that every merge is recorded in an issue is the other
half — it says a record must exist, this one says the record is not where the
work goes to wait. The rule that every task also closes two debt issues governs
the pool of things already filed; this one governs what is allowed to enter it,
and a defect you found today is not one of them. Canon §2 draws the other boundary —
a defect is not a drive-by refactor, and a refactor is not a defect.
