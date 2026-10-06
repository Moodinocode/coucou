# TODO

## Sessions pill: one pill that lists every Claude Code session
- **Problem:** all Claude Code sessions in VS Code share one pill (`integration_claude`), and `HookServer` only tracks the latest one (`activeSessionId`), so with several sessions (even 3 in the same project) the pill flips between them and you can't tell which session is doing what.
- **Constraints:** running 10 sessions is normal, so one small pill per session can never fit the 2×2 pill grid; approvals must keep working per session (the permission card answers the session that asked).
- **Proposed solution:** keep a per-session model in `HookServer` keyed by `session_id` (project, state, last step, label from the first prompt), show it as a single pill with a count whose colour reflects the busiest session, and list the sessions in its card (live first, scrolls past 3, click opens the project).

## Stale session pill when the editor dies
- **Problem:** the temporary VS Code pill is only removed on `SessionEnd` (`HookServer.swift`, `case "SessionEnd"`); if VS Code quits or crashes without sending it, the pill stays until Coucou restarts.
- **Impact:** a dead session keeps a slot in the pill grid (or a place in the "+N" menu) and looks like it might still be running.
- **Proposed solution:** with the per-session model above, drop a session after a long idle time (e.g. 30 min with no hook event), and remove the pill when its last session goes.

## Switching mode drops a live session's pill
- **Problem:** switching modes calls `AppState.loadIntegrationTasks()`, which removes every catalog pill that isn't in the new mode, including `integration_claude` while a VS Code session is still running.
- **Impact:** the session disappears from the notch until its next hook event re-adds it, so a quiet session can vanish for a long time.
- **Proposed solution:** make `loadIntegrationTasks()` keep workspace pills that currently have a live session (known from the per-session model), and only remove them once the session ends.

## Show the island on an external display
- **Problem:** the island is placed once at launch on the screen with a notch (`IslandWindowController.notchScreen()`, falling back to `NSScreen.main`), so with an external display connected it stays on the MacBook screen even when all the work happens on the external one.
- **Constraints:** external displays have no notch (the no-notch resting bar already exists in `screenGeometry(for:)`); displays can be connected/disconnected at any time; 0 % CPU while hidden (no polling); dragging the bot's head already means "attach a window as context" (`IslandWindowController`, `attachDragStart`), so moving the island needs a distinct gesture or handle.
- **Proposed solution:** always launch on the built-in display; the user drags the island by its top strip (the area next to / around the notch, not Mochi's head, which keeps its attach-a-window drag) onto another display to move it there (not remembered across launches); when the display it's on disconnects, it returns to the built-in display (never to another external one), or to the main display (`NSScreen.screens.first`) when the lid is closed and there is no built-in screen — re-evaluated on `NSApplication.didChangeScreenParametersNotification`.
