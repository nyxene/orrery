---
rule: when a tool refuses, make it print why before deciding why — and probe the path that failed, not the one that is easy to run
scope: craft
canon: 3
evidence: "four wrong conclusions about one platform sandbox in a single session. A credential directory was opened on the theory that a deny rule was blocking a tool, and a written justification for the weakening shipped with it — the error message had named a different file all along. The narrowing that followed was verified with calls typed at a prompt, while the path that actually failed was the same tool invoked inside a gate. Rewriting that gate to print its error produced the real cause on the first run. Cost was three changes to one settings line, two of them reversing each other, and a justification for a weakening that did not exist merged twice"
---

A tool that refuses usually says why. Read that before forming a theory, and
build the theory out of what it said. When the message is swallowed —
`2>/dev/null`, a `|| true`, an `if` that treats every failure as one known
cause — the first fix is to stop swallowing it, not to guess harder.

The second half matters as much: **measure the path that failed.** A probe you
can type at the prompt is not the same execution as the one inside a script, a
gate, or a hook, and a tool can behave differently in each.

**Why:** reasoning about a third party's behaviour produces evidence about your
model of it, not about it. The obvious alternative — read the code, form a
theory, act — feels faster and is, right up until the theory is wrong, at which
point every step taken on top of it has to be unwound. The failure is
self-concealing: a wrong theory that predicts the observed symptom is
indistinguishable from a right one until something else contradicts it. And the
convenient probe is the most dangerous kind, because it *does* produce a
measurement, so it feels like the rule was followed.

This extends Canon §3 from what you report to what you do. §3 governs claims
made to someone; this governs an action taken on a belief. The cost lands
differently: a wrong claim is corrected in the next message, a wrong action is
committed, merged, and built upon.

**How to apply:** before acting on why a tool refused, print its actual error —
remove the redirect, widen the capture, run it directly. Then reproduce the
failure through the same route the real caller uses. If a claim about the
platform is load-bearing, fetch the platform's own documentation and quote it;
a sentence in your own notes is a claim, not a source. And when a plan rests on
one asserted fact, check that fact first, not last — the check is minutes and
the plan may be hours.

**Related:** `rules/process/a-command-proves-only-the-question-it-asked.md` is
the reporting half of this — it governs what a green result licenses you to say,
where this governs what a theory licenses you to do.
`rules/craft/gates-must-run-where-nobody-works.md` is the same shape one level
up: an environment nobody exercises is one nobody has measured.
