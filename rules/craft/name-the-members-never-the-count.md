---
rule: write the members or the command that counts them, never the number
scope: craft
evidence: "one revision pass found six stale counts in two documents, every one of them spelled as a word, while the checker that verifies counts was green. Among them: 'the four phases' of a tool with five, and 'two of the fifteen scripts have no test' where seventeen scripts had four untested. Each had been read by every session since it went wrong"
---

A count in prose is a claim that decays on its own. Write the members, or name
the command that counts them, and the sentence stays true through the change
that would have falsified it.

The failure has a signature: the number is **spelled as a word**, sitting next
to the thing it counts — "the other eleven", "the four phases", "all eight
gates run clean". Digits get caught, because a checker can match `[0-9]+
skills`; words in the middle of a sentence do not, and neither does a version
named in prose away from anything version-shaped.

**Why:** a counter check that greps for `<number> <noun>` is what makes digit
counts trustworthy. That coverage is what makes the word form dangerous rather
than merely untidy — the gate is green, so the document reads as verified, and
the reader takes the number on the checker's authority rather than the author's.
A stale digit is an error; a stale word is an error wearing a passing test.

The obvious alternative — teach the checker every English numeral — does not
close it. "The four phases" carries no noun the checker owns, "the other
eleven" names nothing at all, and a version in a sentence is not a version
string. Every one of the six found in that pass would have survived a wider
regex. What removes the class is not writing the number.

**How to apply:** name them — "`build`, `plan`, `push`, `cancel` and `release`"
beats "the five phases", and it fails visibly when a sixth arrives. Or point at
what counts: "count them in the script rather than here". Where a number is
genuinely load-bearing, put it beside the command that produced it, so the next
reader can re-run it. When you do delete a stale count, delete the number rather
than incrementing it: incrementing fixes today and schedules the same bug.

**Related:** `rules/process/a-command-proves-only-the-question-it-asked.md` — a
green checker proves what it matched, not what you meant it to cover, and this
is that rule seen from the document's side.
