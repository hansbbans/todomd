# todo.md Implementation Status (Code-Audited)

Last audited against code: 2026-03-06

This document reflects what is implemented in `Sources/` today.
Use this as the current status reference when roadmap documents differ.

## Done

- Calendar integration is shipped (Apple Calendar access, event overlays in Today and Upcoming).
- Widgets are shipped (Today/Inbox/Perspective views, complete-from-widget action).
- Persistent reminders are shipped (`persistent_reminder` + nag notification planning/scheduling).
- Core local notifications are shipped (due/defer, catch-up path, background refresh scheduling).
- Task refs are shipped (`ref` generation/backfill + `todomd://task/{ref}` routing).
- Assignee, completed-by, and blocked-by fields are shipped.
- Blocked-by auto-unblock on blocker completion is shipped.
- Perspectives are shipped (`.perspectives.json`, custom rule editor, ordering, widget support).
- Deterministic natural-language perspective parsing is shipped (Tier 1 parser + rule summary).
- Voice capture/ramble is shipped (speech recognition, live transcript, parsed multi-task preview, spoken correction commands, batch add).
- Reminders import is shipped (Apple Reminders -> todo.md tasks).
- Full CRUD, watcher sync, conflict handling, manual ordering, share extension, and App Intents are shipped.
- Search is shipped for title/description/area/project/source/tags/filename.
- A Mac app target exists in the Xcode project (`TodoMDMacApp` scheme/target).

## Partially Done

- Natural-language perspectives cloud fallback (Tier 2): query parser marks low confidence, but no cloud/LLM parser integration is implemented.
- Blocked-by advanced UX: core refs + auto-unblock are present, but the UI is still manual text entry for refs; there is no dedicated blocker picker, cycle detection, or dependency graph UI.
- Theming: token architecture exists, but user-facing custom theme builder/preset switching is not implemented (classic preset only in code).
- Import/export: Reminders import exists, but multi-source import/export suite (Todoist/OmniFocus/Things/CSV/JSON/TaskPaper/OPML UI) is not implemented.

## Not Done

- Subtasks/parent-child task model (`parent` field and hierarchy UI/logic).
- Recurrence mode variants beyond RRULE "repeat every" (for example "defer another" / "due again").
- Agent registry and permission model (`.agents.json`, enforcement, audit logging).
- Collaboration controls (quarantine, per-source permissions, source-level notification permissioning).
- Full markdown body rendering (body is still plain text in task detail).
- Advanced notification reliability observability model (`planned/scheduled/delivered/acknowledged/missed`) and incident tooling.

## Rank-Ordered Outstanding Items

Recommended order by user impact and product leverage:

1. Multi-source import/export suite (Todoist/Things/OmniFocus/CSV/JSON/TaskPaper/OPML UI).
2. Natural-language perspectives Tier 2 fallback and disambiguation flow.
3. Subtasks / parent-child task model and hierarchy UI.
4. Blocked-by advanced UX (picker, validation, cycle detection, dependency graph).
5. Full markdown body rendering in task detail.
6. Recurrence mode variants beyond RRULE "repeat every".
7. Advanced notification reliability observability and incident tooling.
8. User-facing theming/preset switching beyond the classic preset.
9. Agent registry and permission model.
10. Collaboration controls and source-level permissioning.

## Future Ideas

- Inbox triage mode. Turn raw inbox processing into a focused flow: one task at a time, assign project/date/priority/tag with fast keyboard gestures.

## Notes

- Some roadmap docs still describe calendar integration as future (`v3`), but calendar support is already implemented in code.
- Older status/planning docs that describe voice ramble as a placeholder are stale; the feature is now wired in code.
- The widget shared-storage TODO doc is stale in part: App Group-backed shared folder preferences and migration logic already exist in code.
- Keep roadmap documents for planning/history; use this file for current implementation truth.
