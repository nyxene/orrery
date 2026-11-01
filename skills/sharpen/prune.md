# The prune pass — a rule layer only grows unless something shrinks it

Part of `sharpen`, run when `rules-loader.sh` warns. It lives beside the skill
rather than in it, so the skill fits what Claude Code keeps of it after
compaction.

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

## Four verdicts, and every rule gets exactly one

| Verdict | When |
|---|---|
| **Keep** | The incident can recur, the rule is the only thing preventing it, and nothing else says the same |
| **Merge** | A neighbour states nearly the same law. One file absorbs the other's incident into its origin and sharpens the wording — two rules saying nearly the same thing is how a rule set stops being read |
| **Absorb** | A gate could enforce it. Write the guard case or the check, then the file goes — a rule a machine can enforce is a rule that will eventually be forgotten instead |
| **Retire** | The incident cannot recur: the tool changed, the practice changed, or the behaviour is baked into a skill's own text now |

**Retirement is deletion, not an archive.** A retired-rules directory is a
second layer with the same growth problem and no reader at all. Git has the
history, and the rule's own file is the only place anyone ever looked.

## What is never a reason to retire

- **Nobody has hit it lately.** That is the rule working.
- **It reads as obvious.** It reads as obvious *because* the incident is in the
  past. Check the cost field before believing this one.
- **It is inconvenient.** A rule you keep arguing with is a rule whose incident
  you have not read.

## How the batch lands

**Every verdict, in one message, before anything is touched.** Name each rule,
its verdict, and the one-line reason. Deleting a rule discards evidence somebody
paid for, and that is the owner's call rather than the pass's.

Apply only what is approved, then re-run the loader against that scope to
confirm the warning is gone — or that it is not, which is also an answer.

## Retiring a rule

The same mechanics whether the rule was absorbed by a fix (`sharpen`'s main
mechanism) or retired by this pass.

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
