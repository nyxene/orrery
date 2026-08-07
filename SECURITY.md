# Security Policy

## Why this file is not boilerplate here

Orrery installs shell hooks that run before every Bash call in your sessions,
and a deny-list that decides which commands are refused. A defect in either is
not a bug in a library you call — it is a change to what an agent is allowed to
do on your machine. Please treat findings accordingly.

The classes that matter most:

- **A guard bypass.** A command that removes files outside the session
  scratchpad, or performs a destructive git operation, and is not refused.
- **A loader that executes untrusted content.** The canon and rule loaders read
  markdown; anything that turns that content into execution is serious.
- **Residue in a shipped file.** A credential, a private path, or customer data
  that reached this repository through a release.

## Supported versions

The latest released version is supported. This project is pre-1.0: fixes land
in a new release rather than as patches to an older one.

## Reporting

**Do not open a public issue.** Use GitHub private vulnerability reporting —
the *Report a vulnerability* button on the
[Security tab](https://github.com/nyxene/orrery/security/advisories/new). The
thread stays attached to the repository, stays private until a fix ships, and
does not depend on anyone watching an inbox.

If that is unavailable to you, contact the maintainer through
[their GitHub profile](https://github.com/nyxene) and say only that you have a
security report — never the details, until there is a private channel to put
them in.

Please include the version from `.claude-plugin/plugin.json`, your OS, the exact
command or content that reproduces it, and what you expected instead. A
reproduction that fits in a shell snippet is worth more than a long description.

Do not include real credentials or customer data in a report. Write the shape
rather than the value — the report needs to know which kind of secret was
involved, never the secret.

## What to expect

- An acknowledgement within 72 hours.
- An assessment, and where the problem is confirmed, a fix in the next release
  with the finding credited unless you ask otherwise.
- If a report turns out not to be a vulnerability, a plain explanation of why,
  and it becomes an ordinary issue if it is still a defect.

This is a small project maintained by one person. Timelines are honest rather
than contractual.
