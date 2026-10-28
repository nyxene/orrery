---
rule: where the project has a tracker, nothing reaches the default branch without an issue behind it — the pull request names the issue, and work found mid-task joins that issue rather than starting a new one
scope: git
tracker: github
evidence: "a merge carrying a renamed rule file, an amended canon and two consumer-visible changes went in with nothing in the tracker recording it; the law had been enforced by one person repeating it, because it was written in no file"
---

Every change that reaches the default branch has an issue behind it, and its
pull request names that issue by number. No exception for a one-line fix, a
correction, a rename or a documentation change: the size of the diff has nothing
to do with whether anyone can find out later why it happened.

This binds where `.orrery/config.json` declares `"tracker": "github"`. Without
a tracker the record of what reached the default branch is the work's
`.orrery/work/<work>/`, committed with it — or, where the project ignores
that directory, its copy in the main checkout's `.orrery/local/work/`.

**Work found mid-task joins the issue you are already under.** A defect you hit
while doing something else is fixed in the same pull request — its own commit if
that makes the change easier to read — and stays under that issue. Starting a
new issue for it is deferral wearing a record's clothes. A new issue is for work
that genuinely is not this task.

**Filing is not deferring.** The record and the fix are different things. The
issue says what happened and why; when the work happens is a separate question,
and the answer to it is almost always *now*.

**Why:** the default branch is the only history anyone reads later, and a commit
message answers *what changed* while an issue answers *what was wrong and what
was decided*. Without one, the reasoning survives only in a session transcript
nobody will find. A rule that lives only in someone's attention is a rule that
is already failing.

**How to apply:** before opening a pull request, know its issue number. If the
work started without one — a fix noticed mid-session, an instruction typed
straight into the terminal — file the issue then, describing what the change
does and why, and reference it. Retroactive by minutes is fine; absent is not.
`Closes #N` in the body when the pull request finishes the issue, a plain `#N`
when it does not. Put a check in CI that refuses a pull request naming no number
at all, so this stops depending on anyone remembering.

**Related:** the rule that a defect you find is fixed when you find it is the
other half of the pair — this one says the record must exist, that one says the
record is not where work goes to wait.
