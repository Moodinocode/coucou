# TODO

## Sessions pill: one pill that lists every Claude Code session
- **Problem:** all Claude Code sessions in VS Code share one pill (`integration_claude`), and `HookServer` only tracks the latest one (`activeSessionId`), so with several sessions (even 3 in the same project) the pill flips between them and you can't tell which session is doing what.
- **Constraints:** running 10 sessions is normal, so one small pill per session can never fit the 2×2 pill grid; approvals must keep working per session (the permission card answers the session that asked).
- **Proposed solution:** keep a per-session model in `HookServer` keyed by `session_id` (project, state, last step, label from the first prompt), show it as a single pill with a count whose colour reflects the busiest session, and list the sessions in its card (live first, scrolls past 3, click opens the project).

## Switching mode drops a live session's pill
- **Problem:** switching modes calls `AppState.loadIntegrationTasks()`, which removes every catalog pill that isn't in the new mode, including `integration_claude` while a VS Code session is still running.
- **Impact:** the session disappears from the notch until its next hook event re-adds it, so a quiet session can vanish for a long time.
- **Proposed solution:** make `loadIntegrationTasks()` keep workspace pills that currently have a live session (known from the per-session model), and only remove them once the session ends.

## About 21 % CPU while the island is showing, with no session running
- **Problem:** with pills on screen and no session at all, the app uses about 21 % CPU and about 100 MB (measured 2026-10-09 on a Debug build with `top`, same on `main` and with the stale-session fix: 21.7 % vs 21.3–21.8 %). The cause is not investigated yet; the pill animations (`Canvas` + `TimelineView`) redrawing at 60 fps while nothing changes is the first thing to check.
- **Impact:** a declared main pill keeps the island visible all day, so this cost is permanent, not only while an agent works; the "0 % CPU when the island is hidden" rule does not cover it.
- **Proposed solution:** profile the resting island with Instruments, then pause or slow the animation timeline when every pill is idle and the mouse is away, and measure a Release build to confirm the gain.
