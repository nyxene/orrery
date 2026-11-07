---
name: debt
description: File a technical-debt item mid-work, or pick the two to pay off for the current task. Invoke the MOMENT you notice mess you are choosing not to fix right now, and at a task's start or end to select the two debt items it must close. Do NOT use for something wrong — a stale comment, a test that cannot fail, a gate that missed — which is fixed now, per Canon §2; nor for deferred features or product scope, which belong on the roadmap.
argument-hint: "[pay] — omit to file new debt; 'pay' to pick this task's two"
---

# Debt

Two modes. Filing is the frequent one.

**This skill owns the distinction, not the taxonomy.** What counts as debt is
settled here and is the same everywhere. What it is filed with is the method's
classification: debt is a `chore` whose body carries `## Where it came from`,
linking the work that left it — no value of its own. The spellings are the
tracker adapter's; the project declares only its `areas` and its `debtPool`
(in `.orrery/config.json`, or this machine's `.orrery/local/config.json`). A
label list baked in here would be wrong in every project but one, and wrong
silently, because a query against a label nobody uses returns an empty pool
rather than an error.

Every act goes through one script, `<that directory>/../../hooks/tracker.sh`,
where `<that directory>` is the base directory this skill was loaded from —
called `tracker.sh` below. It writes to the register the project's `tracker`
setting names: the tracker where there is one, otherwise `.orrery/work/debt/` —
one file per item, committed with the work that found it, reaching the default
branch with that work's merge. The commands are the same for both. **One
register per project, never both:** a second ledger beside the first has no
reader, and it rots within a week of the first item that only lands in one of
the two. `debt` is never a work's name, so no branch or worktree may be called
that — its record would land in the register. Where the project ignores
`.orrery/work/`, the register is still the tree's `work/debt/`; the copy a hook
keeps in `.orrery/local/work/debt/` is history — a paid item stays there.

A non-zero exit says why on stderr, and exit 2 names the values it accepts.
Read it; an empty answer and a failed one must never be taken for each other.

---

## Mode 1 — filing (default)

Triggered the moment you decide **not** to fix something you just noticed. File
it then, not at the end of the task: by the end you will have lost the origin,
which is the single most valuable field here.

### Step 1 — the classification gate

This is the whole discipline, and it is the part that transfers between
projects unchanged. Answer honestly — miscounting a feature as debt is what
makes the pay-off rule meaningless.

- **Debt** — mess *we left behind* that is not wrong. A shortcut taken
  knowingly, a duplication we created, an error path nothing reaches yet.
- **NOT debt — a defect.** Something *wrong*: a comment that no longer
  describes the code, a test that passes whatever the production code does, a
  gate that failed to catch something. Canon §2 has it fixed in the change you
  are already making, at whatever size — so it never reaches this skill, and
  deciding not to fix it is not one of the choices. The one exception is code
  outside this repository, which is filed where it lives.
- **NOT debt — a deferred feature.** Something not built yet. It ships on the
  roadmap as a feature request. The tell is that it came out of a task and is
  scope of the product itself: nobody made a mess, the work simply has not happened.
- **NOT debt — product scope.** A decision awaiting the owner.
- **NOT debt — a domain question.** Research, not cleanup.

If it is not debt, say so and file it where it belongs — a feature request on
the roadmap, or `tracker.sh file` with its own type; a bug stays a bug. Never
reclassify a feature as debt to fill a quota.

### Step 2 — check it is not already filed

```bash
tracker.sh list --search "<a few words of the subject>"
```

If it already exists, record the new sighting on it with
`tracker.sh note <id> --body-file <f>` — in a file register it lands under
*What surfaced it*. A second occurrence is evidence for raising the priority,
not a second item.

### Step 3 — file it

The body answers five questions, and a sixth where there is an answer, each
under a `## ` heading spelled exactly as the left column — in both registers.
A body written freehand each time cannot be read across items, and reading
across items is the whole reason the first two questions exist. And `pay` finds
debt by the first heading: a chore without `## Where it came from` is not
payable.

| The answer | Why it earns its slot |
|---|---|
| **Where it came from** | A link to the issue, PR or work that left it, and the date. Use the number so the tracker backlinks it — from that PR you can see what the shortcut bought |
| **What surfaced it** | One of: a pre-commit gate · a gate that caught it late · **a gate that did not catch it** · code review · an audit · a live check · a user report · noticed in passing. The closed list is what makes these countable, and counting them is how you learn which gates earn their keep |
| **Priority, and why** | By consequence, never by effort. One or two sentences of reasoning, because the level alone is unarguable |
| **Where it lives** | Paths or packages, so whoever touches them finds this |
| **What is wrong** | Concrete enough to act on without re-researching, with the failure scenario: what input or state produces the wrong behaviour, and what the reader ends up believing |
| **What would make it urgent** | Optional. Omit it rather than inventing one |

Priority is set by consequence:

- `critical` — blocks a release, loses data, or is user-visible breakage
- `high` — do it before adding feature scope in the same area
- normal — no `--priority` at all: real cost, no deadline. The default for debt
- `low` — waits until something is already in the file

One area, from the project's `areas`; `tracker.sh` refuses any other and names
the declared ones. If the project declares none, say so and file without one
rather than inventing a scheme — a taxonomy invented per session is worse than
no taxonomy.

Write the body to a temporary file and file it. The title and the header are
`tracker.sh`'s to write, never yours; in a file register the title also names
the file, so it says what is wrong in a few words.

```bash
tracker.sh file --type chore --area <area> [--priority critical|high|low] \
  --title "<what is wrong>" --body-file <body.md>
```

```markdown
## Where it came from
The work that added the second key read on the same hook path.
## What surfaced it
Noticed in passing.
## Priority, and why
Low: a few milliseconds per hook call, which nobody has measured as felt.
## Where it lives
hooks/orrery-config.sh, `orrery_config`.
## What is wrong
A hook reading three keys starts jq three times on one small file.
```

If the project keeps an issue template for debt, it states these same answers.
Nothing here depends on that file existing, and this skill never edits it.

### Step 4 — say it out loud

Report the id `tracker.sh file` printed — `#N`, or the file's path — in the
task's final report, under the origin task. Debt filed silently is debt hidden.

---

## Mode 2 — `pay`

If the host declares a `debtPool`, every feature task also closes **two** debt
items from that pool. A task that is itself paying debt owes none: the quota is
the allocation features never make, and charging it to debt work makes it
recurse. Without a pool, outside legacy mode below, nothing is owed, and the
skill only tracks and reports.

**The pool is narrow on purpose.** Each project declares its own pool — the
areas whose debt feeds this rule — as `debtPool` in its settings. Query once
per pool area. Debt outside the pool is real and stays tracked, but does NOT
feed the two-per-task rule. If the project declares no pool and no `areas`, and
the adapter still serves it from its retired key in legacy mode, its pool is
every area `tracker.sh` accepts (`tracker.sh list --area -` names them).

**Count without the filter first.** A filtered query that returns nothing cannot
tell a clean pool from a pool it could not see, and it reports the same thing
either way — so the unfiltered count is what makes the filtered one mean
anything.

```bash
tracker.sh list --type chore --origin | grep -cv 'no-origin$'   # debt anywhere
tracker.sh list --type chore --area <pool-area> --origin        # once per pool area
```

A line is the id, the date, the title and a mark. Pick from the lines marked
`origin`. Print each `no-origin` line as **not payable until it names its
origin** — never drop it: it is a chore filed as debt that cannot show which
work left it. In legacy mode no mark is printed, because the old label already
means debt.

**Debt exists and the pool is empty is a defect, not a result.** It means those
items carry no area, and the fix is to give them one — not to report nothing to
pay. The reported case: a debt item filed without an area, and then a pool
query that had just been made blind to what the same session had written. A
prose warning stood here and did not hold, which is why this is two commands.

`tracker.sh` lists at most 200 and warns on stderr when a list reaches that,
because a page boundary and a clean tracker look identical. A warned list proves
nothing about the rest.

Pick **newest first**, skipping anything blocked on external input — a manual
data fetch, a deploy, a table that does not exist yet. An unworkable item does
not count as one of the two. Say so rather than substituting silently.

**If the pool holds fewer than two workable items, say so and close what there
is.** Do not widen the scope to make up the number; that was explicitly ruled
out. An empty pool right after a cleanup task is the rule working, not failing.

**Timing is per-task:** at the START when the debt sits in the files or the gate
the task is about to change anyway — so you are not building on top of it and one
gate run covers both. At the END when it lives elsewhere.

Close them properly: the paying change carries what `tracker.sh closer <id>`
prints — `Closes #N` for its PR on a tracker, the file's deletion without one —
through the same gates, the same audit tier as any other change. Paying debt is
not a licence to skip verification. Name the two closed in the task's final
report.
