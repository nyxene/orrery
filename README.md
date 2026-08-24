<div align="center">

# Orrery

**A working method for software written by AI agents and directed by people.**

Consensus planning · fan-out execution · debt that gets paid ·
rules earned from real incidents · guards that fire before every shell call

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.18.0-informational.svg)](CHANGELOG.md)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin-8A63D2.svg)](https://claude.com/claude-code)
[![Gates](https://github.com/nyxene/orrery/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nyxene/orrery/actions/workflows/ci.yml?query=branch%3Amain)

</div>

---

## The problem it is built around

An agent with no memory proposes the same abstraction every session, re-walks
the dead end you hit yesterday, and reports success it never verified. None of
that is fixed by a better prompt. It is fixed by a method that is *executed*:
consent before work starts, evidence before a claim is made, and a rule filed
the moment something breaks — so the next session inherits the lesson instead
of the wall.

Orrery is that method, shipped as a Claude Code plugin. It depends on GitHub
and `jq`, and on nothing else.

## Install

```bash
/plugin marketplace add nyxene/orrery
/plugin install orrery@orrery
```

`jq` must be on `PATH` before anything fires.

Then spend five minutes on **[install/into-project.md](install/into-project.md)**.
The skills read a handful of facts from your project's `CLAUDE.md` — your
labels, your gates, your model tiers — instead of guessing, and that page says
exactly what to declare. A library that hard-codes one project's labels is
wrong in every project but one, and wrong silently.

## The thirteen skills

Each one is invoked by name (`/plan`, `/learn`) or proposed by the agent when
its moment arrives.

| | Skill | What it is for |
|---|---|---|
| 🎯 | **`frame`** | Turn a wish into a stated goal, before any planning starts |
| 🗺️ | **`plan`** | A plan someone else can execute, checked by as many independent agents as the stake earns |
| 🔨 | **`build`** | Execute an approved plan across parallel agents, with an independent audit before commit |
| 🔍 | **`review`** | Review a diff you did not write, through the same gate that reviews plans |
| 🩺 | **`diagnose`** | Find the cause, starting from a command that can prove it is gone |
| ✅ | **`verify`** | Turn "should work" into a command that was run and read |
| ✂️ | **`pare`** | Take the smallest solution that actually works |
| 📋 | **`debt`** | File the mess you chose not to fix — and pay two down every task |
| 🧭 | **`doctor`** | Check the plugin is actually loaded and current, not just installed |
| 📮 | **`feedback`** | Report friction with the tooling itself, sanitized, and only on your word |
| 🤝 | **`handoff`** | Carry the dead ends across a context reset, where they would otherwise evaporate |
| 🎓 | **`learn`** | Turn an incident into a rule, while the cause is still known |
| 🪒 | **`sharpen`** | Improve the method itself from accumulated evidence |

**When two of them seem to fire, the one that names the other is right.** Most
descriptions carry a *not for this — use that* clause, put there by whichever
skill knows where the boundary is. Where neither names the other, take the one
whose description names what you actually asked for rather than the one with the
wider scope: a skill claiming *any change* or *anything* is stating what it
charges, not staking a claim on the work.

## What else is in the box

- **[CANON.md](CANON.md)** — eight non-negotiable rules, loaded into every
  session by hook. Consent before work. Evidence before claims. Surgical
  changes. Root cause, not symptom. They are short because every line is paid
  for in every session of every project.
- **Three agents** — `architect`, `critic`, `auditor`: the checkers of the
  consensus-planning loop, and the independent audit that runs before anything
  is committed. Drafting a plan is not one of them — `plan` writes in the
  session that invoked it, and spends agents only on reading what it wrote.
- **Seven hooks** — two guards (a Bash guard with a mutation-tested case corpus,
  and an agent guard), two loaders for the canon and for scoped rules, a prompt
  that catches unfinished work before a context reset takes it, a reporter that
  tells you when your project's copy of the deny-list has fallen behind the one
  shipped here, and an optional recorder that is off until you name a path for
  it.
- **A deny-list** — 121 deny rules covering system paths, secret files and
  destructive git, additive to your existing settings and safe on any repo.

## Which platforms this holds on

The guards run before every shell call, so what they do — and what they cannot
do — is platform-specific in a way the rest of this page is not.

| Platform | What holds | What proves it |
|---|---|---|
| **macOS** | everything above | the maintainer's pre-commit hook, on the machine this is written on |
| **Linux** | everything above | CI, on every push |
| **Windows** | **nothing yet — support is planned, see below** | — |
| **anything else** | **nothing — the Bash guard refuses every command and says why** | a probe the guard's mutation pass scores |

The last row is not a polite way of saying "untested". On a platform the guard
does not model, no pattern in it can match — and a guard that finds nothing
looks exactly like a guard that read the command and approved it. So it refuses
instead, names the platform, and says what would have to change. You do not get
a degraded guard; you get a stopped one, at the first command rather than after
the one that mattered.

### Windows support is planned

It is not built, and this section says so rather than leaving you to find out at
the first command. What stands in the way is specific, which is the reason it is
worth stating as a plan and not as an aspiration:

- The hooks are `.sh` files. Whether they execute at all under the shell Claude
  Code uses on Windows has not been verified either way.
- The deny-list names POSIX paths, so it is inert there — the rules exist and
  match nothing.
- The Bash guard reads one `uname` and knows two answers. A third needs the
  scratchpad root, the delete verbs and the secret-store paths in their Windows
  spellings, and a CI runner to hold them, since a guard proven on one platform
  says nothing about another.

Until that lands the guard refuses every command on Windows and names the
platform in the refusal. That is deliberate: a stopped guard is legible, a
silent one is not.

If you want this, say so through the friction form linked below — what a
consumer actually runs there decides which of the three bullets gets done first.

Everything else in the plugin — the canon, the rules, the skills, the agents —
is text loaded into a session and is not platform-specific.

## What makes the rules different

Almost every rule in **[rules/](rules/)** exists because something actually went
wrong, and each carries the evidence it was earned from — not general advice
that reads well and loses every argument it enters.

The exception is marked rather than hidden. A handful were set as policy before
they bit, about a harm nobody wants to meet even once — licensing, third-party
content, spending your money without asking. Those carry `evidence:` naming the
risk instead of an incident, and they are held to a higher bar for it: an earned
rule wins an argument on what it cost, a declared one only on the risk it names.

```yaml
rule: nothing goes outward without its own command — approving the mechanism is not it
scope: process
canon: 1
evidence: "a deploy went live off a mechanism approval that was never a publish
  command; the unreleased draft was publicly reachable until an urgent takedown"
```

They load by scope: a rule tagged `git` arrives when a session touches git, and
stays out of the way otherwise. Your own incidents land in your repository's
`.claude/rules/` via `learn` and load with exactly the same weight as these.

## Privacy

Everything runs locally. Nothing about you or your code is transmitted, and
nothing is written outside your repository on its own. **No hook makes a network
call** — the things that run automatically, before every tool call, never leave
your machine.

One skill does reach the network, only when you run it: `doctor` asks GitHub for
this plugin's own current commit, to tell you whether your installed copy has
drifted from the marketplace source. It sends nothing but that request.

One optional feature writes about your usage, and only if you ask for it: set
`ORRERY_CALL_LOG` and a hook records which tools were called — never a command,
a prompt, a path or a name, and never anywhere but your own disk. Unset by
default; see [install/into-project.md](install/into-project.md).

The lessons `learn` records are yours and stay in your repo. Sharing anything
with this project — an issue, a PR, feedback — is voluntary, explicit, and shown
to you before it happens.

## Contributing

Read **[CONTRIBUTING.md](CONTRIBUTING.md)** first: nothing is developed in this
repository, and knowing that up front saves you a rewrite. The most valuable
thing you can send is a **friction report** — a guard that refused something
reasonable, a skill that fired wrongly, a rule whose advice was wrong in your
context. There is [a form for it](../../issues/new?template=friction.yml).

Security problems go through **[SECURITY.md](SECURITY.md)**, never a public
issue: this plugin installs hooks that run before every shell call, so a defect
in one changes what an agent may do on your machine.

## Status

Pre-1.0. Skill names and layout may still move between releases; the
[CHANGELOG](CHANGELOG.md) says what changed and the version in
`.claude-plugin/plugin.json` is what decides whether your install is stale.

---

<div align="center">

Version 0.18.0 · Canon, thirteen skills, three agents, 21 rules, seven hooks

[MIT](LICENSE) © Evgeniy Kovrov

</div>
