---
name: feedback
description: Report friction with the tooling itself — a guard that refused something reasonable, a skill that fired wrongly, a rule whose advice was wrong. Invoke on "feedback", "report this", "the guard is wrong", "this skill misfired", or the moment you notice yourself working around Orrery rather than with it. Files to the product tracker, and only on an explicit word.
argument-hint: "[what misbehaved, in one line]"
---

# Feedback — The Report Nobody Else Can Write

The library learns from incidents. `learn` catches the ones that happen *to a
project*; this catches the ones that happen *to the tooling* — and those are
invisible from here, because the person who hits them is in a session nobody
else will ever read.

A guard that refuses something reasonable costs a workaround and gets one. The
workaround is silent. Nothing about it reaches whoever could widen the guard,
and the next person writes the same workaround. That is the gap this closes.

## When to invoke

- A guard denied something that was fine, and you worked around it.
- A skill fired when it should not have, or did not fire when it should have.
- A rule's advice was wrong in this context — not disagreeable, *wrong*.
- A hook errored, a script failed on this OS, a documented path did not resolve.
- **You noticed yourself working around Orrery rather than with it.** This is
  the strongest signal there is and the easiest one to let pass.

## When not to

- **The tooling behaved correctly and you disliked it.** A refusal you disagree
  with is a conversation, not a defect. Say so directly instead.
- **A problem in the host project.** That is an issue in the host's own tracker.
- **Something you can fix here and now.** Fix it. A report is for what you
  cannot reach from where you are.

## Step 1 — collect, mechanically

Do not ask the user for anything a command can answer:

```bash
# the version, which decides whether the finding is already fixed
jq -r '.version' "${CLAUDE_PLUGIN_ROOT:-.}/.claude-plugin/plugin.json" 2>/dev/null
uname -sr
```

Add, from the session rather than from the user: which skill, hook, agent or
rule was involved, what fired, and what was expected instead. You were there.
Asking the user to reconstruct it spends their attention on something you
already have (Canon §7).

## Step 2 — sanitize, before anything is drafted

The report goes to a public tracker. Everything below leaves this repository
permanently, and no revert reaches a cache or an index.

**Never include:** the host project's name, its paths, its code, its business
context, credentials, customer data, or a session URL.

**Write the shape instead of the value.** `a path under the project root`, not
the path. `the deploy credential, in the environment`, not the variable's
contents. `the guard refused a compound command whose second segment was a
deletion`, not the command with the real directory in it.

Reproduce with a *neutral* case wherever one exists. `rm -rf ./build` carries no
information about anyone; the real command usually does. A reproduction that has
been generalized is worth more than one that has been redacted, because a
redaction still shows the shape of what was taken out.

## Step 3 — draft

Four sections, and none of them is optional:

**What happened.** What you were doing, what fired, what it did.

**What should have happened instead.** If you are not sure, say you are not
sure — a report that guesses at the fix is worse than one that describes the
symptom precisely.

**What it cost.** Time, a wrong commit, a workaround now living in the host
project, or nothing but annoyance. State it plainly. This is what decides
whether it gets fixed and how soon, and an inflated cost is found out the moment
someone tries to reproduce it.

**Version and OS.** From step 1.

## Step 4 — show it, then wait

**Print the draft in full and stop.** Filing to a public tracker is an outward
action: it needs the user's explicit word in the current exchange, and a plan to
file, a prior "yes, report things like this", or their having invoked this skill
are none of them (Canon §1).

Say plainly that this goes to a public tracker and is permanent.

On their word:

```bash
gh issue create --repo nyxene/orrery \
  --label tooling-feedback \
  --title "<one line, the symptom>" \
  --body-file <the draft>
```

Use `--body-file`. A body passed inline goes through the shell, where the guard
reads its contents as a command it is being asked to run — quoting a removal verb
inside the narrative is enough to have the whole call refused.

Report the issue number back.

## Step 5 — when there is no `gh`, or no network

Do not fail. Print the draft with the URL and say the report was not sent:

```
https://github.com/nyxene/orrery/issues/new?template=friction.yml
```

A skill that loses the user's report because the network was down has done worse
than not existing — they will not write it twice.

## What this is not

`learn` files a rule into the project when an incident will recur *there*.
`debt` records mess left behind in the code. This one leaves the repository, and
that is the whole difference: it is the only skill whose output another person
reads.
