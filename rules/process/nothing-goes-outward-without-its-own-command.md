---
rule: nothing goes outward without its own command — approving the mechanism is not it
scope: process
canon: 1
evidence: "a deploy went live off a mechanism approval that was never a publish command; the unreleased draft was publicly reachable until an urgent takedown, and external copies may outlive any revert. The opposite error followed: a finished commit was withheld from the project's own remote as though pushing there were exposure"
---

An action that makes anything reachable outside the repository — publishing a
site, enabling a hosted-pages deploy, releasing a package, making a repo
public, posting or sending beyond it — starts only on an explicit command to do
it *now*, in the current exchange. A decision that chose the mechanism,
approved the plan, or created the tracking issue authorises building the
machinery, never flipping it on.

**What counts as outward, and what does not.** The test is whether the action
changes *who can see the thing* or *which repository holds it* — never whether
bytes left the disk. Pushing a branch to the project's own remote is neither: it
moves a commit between two copies of the same repository, visible to exactly the
people who already had access, and it is the normal completion of committed
work. Writing an issue comment is the same. What crosses the line is a push to a
*different* repository, a release or tag consumers resolve, flipping a private
repository public, or sending anything to a third-party service.

**Why:** the mechanism decision and the publish command arrive in the same
conversation and read alike — "it's static, hosted pages will do" sounds like a
go. The obvious alternative, treating an approved deploy issue as consent,
fails on the asymmetry of the mistake: every other wrong action is repairable
inside the repository, but exposure propagates into caches and indexes where no
revert reaches. A wrong *how* costs a rewrite; a wrong *now* costs control over
who has seen the thing.

That same asymmetry is why the boundary has to be stated rather than felt. A
rule about exposure invites reading every outbound-looking command as exposure,
and the over-strict reading is not free: it withholds finished work behind a
question the owner has already answered by setting the project's branch flow,
and it spends the attention Canon §7 exists to protect. Erring wide looks like
caution and is really a second failure mode with a quieter cost.

**How to apply:** build everything up to the switch without asking — the
workflow file, the config, the staged content are all inert. The switch itself
waits for words to the effect of "publish it", given in the current exchange; a
plan, an issue, or a mechanism choice from an earlier one does not count, and
neither does an autonomy grant that never named going outward. Stage it so the
ask costs one word. If it went out wrongly anyway: take it down first, report
second, and say plainly that external copies may survive the takedown.

**Related:** Canon §1 owns consent and this expands it along the outward axis —
consent to *work* and consent to *expose* are different grants, and
`rules/process/only-an-explicit-go-ahead-starts-work.md` holds the shapes of
the first. `rules/git/arm-auto-merge-only-when-told.md` is the same law scoped
to merges. Do not file a build artifact under this rule: a ref that is gated
because a tool owns its contents — a release branch assembled by a promotion
script — is held by a provenance gate, not a consent one, and writing it by
hand fails as a second source rather than as exposure.
