---
rule: every retrospective comment uses the mandatory table format below, never prose or bullets alone
scope: process
evidence: "a prose-only retrospective was posted while this rule already existed, and had to be edited in place after the missing tables were pointed out"
---

Every retrospective comment posted on a closing multi-PR phase or task issue must use the exact table format specified below — never prose or bullets alone. This is a hard rule, not a style preference; re-read it before drafting any retrospective rather than reconstructing the format from habit.

**Why:** issue and PR timestamps (`created_at`/`closed_at`/`merged_at`) persist forever and are free to query later — and so does subagent token, tool-call and duration data. Every spawned agent leaves a transcript under the session's own `subagents/` directory carrying its usage block, its tool calls and its timestamps, beside a `.meta.json` naming what it was. That data is routinely left unread. Resource usage and a step-by-step summary need to be preserved for later retrospectives, and a prose-only writeup throws the structured data away even when the content is otherwise complete.

**How to apply — mandatory format:**
- An HTML comment block up top with machine-readable key:value data (phase/issue/PR numbers, token totals).
- A human-readable markdown table of tokens/tool-calls/time per stage (planning roles, per-PR implementation and audit, and so on). **Generate it, do not assemble it by hand**: `skills/build/retrospect.sh` reads the session's transcripts and prints this table and the header block above. It runs after the work lands — there is nothing to record while the work is in flight.
- A wall-clock timestamp table pulled from real `gh pr view --json createdAt,mergedAt` / `gh issue view --json closedAt` data — never estimate these, always query.
- A condensed numbered list of what actually happened (key findings and deviations, not just "PR X merged").
- Post via `gh issue comment <N> --body-file <path>` on **the issue that is closing** — the task issue for a task, the umbrella for a phase, and never on an individual sub-PR. These are two artifacts rather than one. A task retrospective's numbers come from the session that did the work, because that is the only session holding the transcripts; a phase retrospective is assembled from the task ones by reading them back (`gh issue view <N> --json comments`), because the session that closes an umbrella is almost never the one that did the work. The machine-readable header block exists so that second reading needs no transcripts at all.
- **The four parts above are the phase form. An ordinary issue's minimum is the header block, the spend table and one line of what happened** — both generated parts cost nothing to produce, which is the point: the half that answers "what did this cost" is the half nobody has to write. Demanding four tables on a one-line fix is how a rule stops being followed, and measurement across three projects found it had.
- `skills/build/close-issue.sh <N> --what "<one line>"` does the whole minimum form and then closes the issue, which is what `hooks/process-guard.sh` refuses a bare `gh issue close` in favour of. Add `--since <iso8601>` when this session already reported on an earlier issue, or that issue's spend is counted here again.
- Keep the format consistent across phases so `gh issue view <N> --json comments` and aggregate searches stay useful for building a cross-phase retrospective later.
- Distinguish cumulative agent compute (tokens, tool-calls, summed subagent durations — the honest "resources spent" proxy) from wall-clock, which includes idle and waiting time. State this distinction explicitly so the numbers aren't misread later.
- Don't mix harness-reported subagent-token totals from a completion notification's usage block with a transcript-summed output-token count without flagging that they're different, smaller-versus-larger metrics. `retrospect.sh` sums transcripts and says so in its own footer; keep that line.
- **A number that could not be read is `not captured`, never an estimate.** If the transcripts are gone the honest cell is empty, because an invented figure is indistinguishable from a real one the moment anyone reads the table later — which is the only reason the table exists.

**Related:** `rules/process/research-docs-end-with-a-references-table.md` — both exist because structured source and resource data is cheap to capture in the moment and expensive to reconstruct afterwards.
