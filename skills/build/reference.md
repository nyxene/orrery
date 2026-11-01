# Build — reference

Two parts of `build` that are read when they are needed rather than on every
invocation. They live beside the skill rather than in it, so the skill fits
what Claude Code keeps of it after compaction.

## Why the audit tier is its own session

The audit tier is the one that is about context rather than capability. A judge
that ran inside the session which produced the work inherits its reasoning whole
— the same files in the same order, the same alternatives already dismissed — so
whatever was missed is missing from the judge as well. A fresh session is the
mechanism, and it is what the gate buys. Spawning the `auditor` agent type is
what supplies it.

A different model family on top of that is an amplifier rather than the
mechanism: two fresh sessions of one model already have separate contexts, and
two families additionally have separate blind spots, which is worth buying where
the stake earns it. This repository buys it — `auditor` pins Fable — but a
project with one family available conforms, and nothing in the tier table says
otherwise.

## The record, in full

Step 9 runs `<that directory>/record.sh write --what "<one line>" [--retries <n>]`.

Re-run it before every later push and it refreshes; it measures from the
branch's first reflog entry unless `--since` says otherwise. `--retries` is
how many times step 6 went round — no transcript says it, so you do, and an
unstated count is written `not recorded`, never 0. `--final` on the last
write also deletes the work's handoff. **No other step of `build` records
anything for it** — the transcripts already hold the usage, which is why this step is at
the end and costs the run nothing. If it reports no transcripts, the cells
are `not captured`; never fill them with an estimate. Writing from a session
that did not do the work: `--not-captured`, or the table reports the
writer's spend as the work's.

Work that ends without merging is closed on its branch, once:
`record.sh close refused|withdrawn|answered|enacted --why "<one line>"`. The
outcome cannot be overwritten, and the branch keeps the record.

An umbrella or a phase is summed from its children's records rather than
measured — the closer's spend is not the phase's — and written with
`record.sh write --body-file <path>`. Do not invent a second format — the
rule exists because a second one was invented.

## Licensing and provenance

Read the moment a decision touches third-party material, in any step.

**Licensing/legal questions get escalated scrutiny, never a silent
default**: anything touching data provenance (third-party constant or
reference tables, named-author formulas, scraped or verbatim text,
patented algorithms) defaults to the most independently-defensible
option — attribute to the original human or public-domain source,
re-derive rather than copy, avoid copyleft-triggering redistribution —
per `rules/craft/third-party-content-splits-into-idea-vs-expression.md`. The defensible
option costs a little now; the other one carries an unbounded liability
the moment the work reaches anyone outside the room.

**Taking the defensible default is autonomous. Ruling on a licence is
not.** Re-deriving instead of copying sidesteps the question and needs
nobody's permission. Deciding that a particular third-party artifact may
be used *as it is* is a legal judgement, and Canon §6 reserves it — an
agent presents the risk and the mechanism, never the verdict. Where no
defensible default exists, stop and put it to the owner, in any mode.
Either way the decision is mandatory in the log, never omitted for being
"obviously fine."

## Recovering a lost report

`hooks/agent-guard.sh` denies a named spawn whose brief never tells the agent to
send its deliverable back, so the lost-report failure is blocked rather than
remembered. Recovering an already-lost report is the part no guard can do: the
payloads are in `~/.claude/projects/<project>/<session>/subagents/agent-*.jsonl`,
and an agent that "went silent" is this failure until proven otherwise.
