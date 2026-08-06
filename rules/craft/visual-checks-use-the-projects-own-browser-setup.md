---
rule: "verify visual/ui changes with the project's own end-to-end browser setup, not a built-in browser-automation mcp tool"
scope: craft
evidence: "a built-in browser-automation tool failed outright mid-session while the project's own browser setup worked; separately, a click that auto-scrolled its target raced with scroll-based dismiss logic and made working UI look broken during debugging"
---

Don't default to a built-in browser-automation MCP tool for visual verification if the project already has its own end-to-end browser install and drivers set up. When such infrastructure exists and has a track record in the project, prefer it — write a throwaway ad-hoc script rather than a formal test spec.

**Why:** A built-in generic browser tool can be flatly unreliable for a given repo (extension not connected, wrong session, etc.) even though it works elsewhere. Meanwhile a project's own browser install is already configured for that codebase's dev server, routes, and auth state, and has already proven itself. Trusting stale setup docs over a direct, current failure (or a direct user correction) wastes a debugging cycle.

**How to apply:** For an ad-hoc visual check, write a throwaway script that drives the project's own browser binding directly — no test-runner ceremony — launch it, navigate, wait for a selector that proves the page actually rendered, screenshot, and read the image yourself; don't just check that the script exited 0.

Watch for a specific race: `.click()` auto-scrolls its target into view first. If it fires right after another action that itself triggered a scroll, the trailing scroll event can race with code that treats "scroll" as an outside-dismiss signal (a popover/dialog closing itself on any window scroll), and the UI under test appears broken when it isn't. Fix by calling `locator.scrollIntoViewIfNeeded()` plus a short settle wait *before* the click that opens the UI you're about to assert on — not just before reading a bounding box.

**Related:** `rules/process/never-touch-system-folders.md` — the same discipline of staying within the project's own resources.
