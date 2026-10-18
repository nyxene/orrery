---
name: feedback
description: Report friction with the tooling itself — a guard that refused something reasonable, a skill that fired wrongly, a rule whose advice was wrong. Invoke on "feedback", "report this", "the guard is wrong", "this skill misfired", or the moment you notice yourself working around Orrery rather than with it. Hands you a prefilled link to the product tracker and files nothing itself.
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

- A guard denied something that was fine. Report it rather than working around
  it — the refusal is the person's to overrule, and a walk-around hides the
  defect this report exists to fix.
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

The report goes to the product's tracker, which people outside this project
read. Everything below leaves this repository permanently, and no revert
reaches a cache or an index.

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

## Step 4 — hand over a link, and never file it yourself

**This skill creates nothing.** No `gh issue create`, no API call, no write of
any kind into any tracker. It prints the draft, builds a URL with that draft
already in the form, and stops. The person submits it, in their own browser, or
it does not get submitted.

That is structural, not caution. This skill is installed in projects that are
not the tracker's, so a command here that writes to a fixed repository writes
there **from every project it is ever installed in** — including when someone
asked for a task in the project they are actually standing in. No wording in
this file can prevent that; removing the command does.

Print the draft in full, then the link. Say plainly that submitting it is seen
beyond this project and permanent, and that nothing has been sent.

### The link

The form prefills from the query string, keyed by field id:

| Key | Field |
|---|---|
| `version` | from step 1 |
| `kind` | one of the dropdown's options, copied exactly |
| `what` | What happened |
| `cost` | What it cost you |
| `expected` | What should have happened instead |

```
https://github.com/nyxene/orrery/issues/new?template=friction.yml&version=<v>&kind=<option>&what=<text>&cost=<text>
```

Percent-encode every value. A raw newline, `&` or `#` ends the field at that
character and drops the rest of it without saying so.

**A long report does not travel in a URL.** Browsers and servers cut one off
after a few thousand characters, and what gets cut is the tail — the transcript
that made the report worth filing. Prefill the summaries, print the long part
below the link to be pasted in, and say that is what you did. A link that
arrives truncated is worse than a short one, because nobody can see what is
missing.

Nothing is reported back afterwards. This skill does not learn whether the issue
was filed and must not go looking.

## What this is not

`learn` files a rule into the project when an incident will recur *there*.
`debt` records mess left behind in the code. This one leaves the repository, and
that is the whole difference: it is the only skill whose output another person
reads.
