# The re-review — only what moved

Part of `plan`, read when a checker returns anything but APPROVE. It lives
beside the skill rather than in it, so the skill fits what Claude Code keeps of
it after compaction.

A non-APPROVE verdict revises the plan. It does not restart the pass.

- **The draft** is revised here against the findings, and the revision states
  how each one was answered. An architect antithesis you reject is answered in
  writing, not ignored.
- **Critic** re-checks **its own prior findings** and anything the revision newly
  touched. Not a fresh full pass — the plan it already read has not changed
  underneath it.
- **Architect** re-checks **its own prior findings** whenever it raised any —
  narrowly, like the critic: did each fix hold. Nobody else reads them. The
  critic re-checks only its own, so without this an accepted architect finding
  is marked answered by the draft that answered it and verified by no one — a
  trust-boundary plan once went to build on four of them that way, and the
  security audit afterwards found three high-severity holes in the same area.
- It **re-argues the direction only if the approach changed** — or if the
  revision rejected its antithesis. A finding about a missing function name
  does not warrant re-arguing the direction; a rejected argument does, because
  nobody else can weigh it. The critic never saw the antithesis, by design, so a
  rejection the architect does not re-read is an argument that dies unopposed
  after being answered once by the party it was aimed at.
- A rejection the architect **accepts** ends it. It says so in one line and the
  iteration closes.

**Two iterations, then stop** — and the count belongs to the work rather than to
the document. If the critic still withholds APPROVE after two, the defect is in
the brief rather than the plan. Present the best version, name what the critic
will not pass, and hand it to the owner.

Five plans for one task, each of them inside the two-iteration cap, is how ten
checker rounds produced no code. Every round
was within the limit; nothing counted the sequence — which is why the work's
item carries `Attempt:`, `plan` reads it before drafting, and never writes a
third.
