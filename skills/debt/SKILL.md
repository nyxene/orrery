---
name: debt
description: File a technical-debt item mid-work, or pick the ones to pay off for the current task. Invoke the MOMENT you notice mess you are choosing not to fix right now, and at a task's start or end to select the debt items it must close. Do NOT use for something wrong — a stale comment, a test that cannot fail, a gate that missed — which is fixed now, per Canon §2; nor for deferred features or product scope, which belong on the roadmap.
argument-hint: "[pay] — omit to file new debt; 'pay' to pick this task's quota"
---

# Debt

Two modes. Filing is the frequent one.

**This skill owns the distinction, not the taxonomy.** What counts as debt is
settled here and is the same everywhere. Which labels carry it is the project's,
declared in its `.orrery/config.json` (`debtLabels`) — a label list baked in here is a label list that is
wrong in every project but one, and wrong silently, because a query against a
label nobody uses returns an empty pool rather than an error.

The register of debt is the tracker, where the project has one (`"tracker":
"github"` in `.orrery/config.json`). Without one it is `.orrery/work/debt/` — one
file per item, committed with the work that found it, reaching the default
branch with that work's merge. **One register per project, never both:** a
second ledger beside the first has no reader, and it rots within a week of the
first item that only lands in one of the two.

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
the roadmap, or a tracker item where one exists. Never
reclassify a feature as debt to fill a quota.

### Step 2 — check it is not already filed

With a tracker: query the project's debt label, whatever it declared:

```bash
gh issue list --state open --label "<debt-label>" --limit 200 \
  --json number,title -q '.[]|"#\(.number)  \(.title)"'
```

If it already exists, comment recording the new sighting. A second occurrence is
evidence for raising the priority, not a second issue.

### Step 3 — file it

With a tracker, the issue has to answer five questions, and a sixth where there is an answer.
What it is laid out with is the project's business; **that each answer sits
under a stable heading is not**, because a body written freehand each time
cannot be read across issues, and reading across issues is the whole reason the
first two questions exist.

| The answer | Why it earns its slot |
|---|---|
| **Where it came from** | The issue or PR number and the date. Use the number so the tracker backlinks it — from that PR you can see what the shortcut bought |
| **What surfaced it** | One of: a pre-commit gate · a gate that caught it late · **a gate that did not catch it** · code review · an audit · a live check · a user report · noticed in passing. The closed list is what makes these countable, and counting them is how you learn which gates earn their keep |
| **Priority, and why** | By consequence, never by effort. One or two sentences of reasoning, because the level alone is unarguable |
| **Where it lives** | Paths or packages, so whoever touches them finds this |
| **What is wrong** | Concrete enough to act on without re-researching, with the failure scenario: what input or state produces the wrong behaviour, and what the reader ends up believing |
| **What would make it urgent** | Optional. Omit it rather than inventing one |

Priority is set by consequence:

- `critical` — blocks a release, loses data, or is user-visible breakage
- `high` — do it before adding feature scope in the same area
- `medium` — real cost, no deadline. The default for debt
- `low` — cosmetic, or unreachable today

Labels: the project's debt label, its scope label for the area, and its priority
label. All three come from the project's `.orrery/config.json` (`debtLabels`). If it declares none, say
so and use what the tracker already has rather than inventing a scheme — a
taxonomy invented per session is worse than no taxonomy.

If the project keeps an issue template for debt, it states these same answers.
Nothing here depends on that file existing, and this skill never edits it.

### Step 4 — say it out loud

With a tracker, report the number in the task's final report, under the origin task. Debt filed
silently is debt hidden.

### Without a tracker

The same gate, the same answers, a file instead of an issue:
`.orrery/work/debt/<slug>.md`, the slug saying what is wrong in a few words. The
labels become three lines at the top, each carrying the full label, so `grep`
can do what a label query does. `debt` is never a work's name, so no branch or
worktree may be called that — its record would land in the register:

```markdown
priority: priority/low
area: area/hooks
filed: <the date, YYYY-MM-DD>

# Each config key is read with its own jq process

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

Step 2 is `ls .orrery/work/debt/` and a `grep -il` for the subject; a second
sighting is a line added under *What surfaced it*, not a second file. Step 4
names the file instead of a number.

---

## Mode 2 — `pay`

A host project may declare a per-task debt quota; when declared, every feature
task closes that many debt issues from the active pool. When none is declared,
the skill only tracks and reports.

**The pool is narrow on purpose.** Each project declares its own pool — the
area labels whose debt feeds this rule — in its `.orrery/config.json`
(`debtLabels.pool`). Query once per
pool label: repeated `--label` flags are ANDed, so two in one call ask for
issues carrying both. Debt outside that
area is real and stays tracked, but does NOT feed the per-task quota. If the
project declares no pool, the pool is the area the current task touches.

**Count without the filter first.** A filtered query that returns nothing cannot
tell a clean pool from a pool it could not see, and it reports the same thing
either way — so the unfiltered count is what makes the filtered one mean
anything.

```bash
gh issue list --state open --label "<debt-label>" --limit 200 --json number | jq length
gh issue list --state open --label "<debt-label>" --label "<pool-label>" --limit 200 \
  --json number,title,createdAt,labels \
  -q '.[]|"\(.createdAt[0:10])  #\(.number)  \(.labels|map(.name)|join(","))  \(.title)"'
```

**Debt exists and the pool is empty is a defect, not a result.** It means those
issues carry no scope label, and the fix is to label them — not to report
nothing to pay. The reported case: a debt issue filed without an area label, and
then a pool query that had just been made blind to what the same session had
written. A prose warning stood here and did not hold, which is why this is two
commands.

The limit is 200 and not 50 for the same reason a truncated list proves nothing
about the rest: a page boundary and a clean tracker look identical. If a count
comes back at the limit, raise it rather than concluding anything.

Pick **newest first**, skipping anything blocked on external input — a manual
data fetch, a deploy, a table that does not exist yet. An unworkable item does
not count toward the quota. Say so rather than substituting silently.

**If the pool holds fewer workable items than the quota, say so and close what
there is.** Do not widen the scope to make up the number; that was explicitly ruled
out. An empty pool right after a cleanup task is the rule working, not failing.

**Timing is per-task:** at the START when the debt sits in the files or the gate
the task is about to change anyway — so you are not building on top of it and one
gate run covers both. At the END when it lives elsewhere.

Without a tracker the same two commands are a count and a filter over the files
— `ls .orrery/work/debt/*.md | wc -l`, then `grep -l '^area: <pool-label>$'` —
and newest first is by `filed:`. Paying an item deletes its file in the paying
change; the deletion reaching the default branch is the close.

Close them properly — with a tracker, a PR with `Closes #N`; without, the change
that deletes the file — through the same gates, the same audit tier
as any other change. Paying debt is not a licence to skip verification. Name
the issues closed in the task's final report.
