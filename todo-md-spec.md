# todo.md — Development Specification

## Overview

**todo.md** is a native iOS task manager that uses plain Markdown files as its database. Each task is a single `.md` file with YAML frontmatter, stored in an iCloud Drive folder. The app provides a Things-level visual experience on top of an open, interoperable data layer.

**Core philosophy:** The filesystem is the API. Any tool that can write a `.md` file — Obsidian, AI agents, shell scripts, Shortcuts — can create or modify tasks. The app is a beautiful, opinionated *view* on top of a markdown filesystem.

**Target platforms:** iPhone (v1), iPad and Mac (v2)

**App name:** todo.md

---

## Data Model

### File Format

Each task is a single `.md` file with YAML frontmatter.

**Filename convention:** `{YYYYMMDD}-{HHmm}-{slug}.md`

Example: `20250226-1430-buy-groceries.md`

- Timestamp is creation time (UTC)
- Slug is a kebab-case version of the title, truncated to 60 characters
- If a collision occurs, append `-2`, `-3`, etc.

**Example task file:**

```markdown
---
title: "Buy groceries for meal prep"
status: "todo"
due: "2025-03-01"
defer: "2025-02-28"
scheduled: "2025-02-28"
priority: "medium"
flagged: false
area: "Personal"
project: "Meal Prep"
tags:
  - errands
  - food
recurrence: "FREQ=WEEKLY;BYDAY=SA"
estimated_minutes: 45
description: "Weekly Trader Joe's run for meal prep ingredients"
created: "2025-02-26T14:30:00Z"
modified: "2025-02-26T14:30:00Z"
completed: null
source: "user"
---

Pick up chicken, rice, broccoli, and sweet potatoes from Trader Joe's.
Don't forget the sriracha this time.
```

### Frontmatter Schema

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `title` | string | yes | Task title, displayed in list views |
| `status` | enum | yes | `todo`, `in-progress`, `done`, `cancelled`, `someday` |
| `due` | date (YYYY-MM-DD) | no | Hard deadline — the date by which the task MUST be done |
| `defer` | date (YYYY-MM-DD) | no | Task hidden until this date (OmniFocus-style) |
| `scheduled` | date (YYYY-MM-DD) | no | The date you PLAN to work on this task (OmniFocus 4.7 "planned date"). Unlike `due`, this is intention, not deadline. Drives the Today view. |
| `priority` | enum | no | `none` (default), `low`, `medium`, `high` |
| `flagged` | boolean | no | Quick-access flag for important tasks, independent of priority (OmniFocus-style). Flagged tasks get their own smart view. Default: `false` |
| `area` | string | no | Top-level life area (e.g., "Work", "Personal", "Health") |
| `project` | string | no | Project name within an area |
| `tags` | string[] | no | Flat list of tags |
| `recurrence` | string (RRULE) | no | RFC 5545 RRULE for repeating tasks |
| `estimated_minutes` | integer | no | Estimated time to complete in minutes (OmniFocus-style). Useful for time-blocking and "what can I do in 15 minutes?" filtering |
| `description` | string | no | Short description/subtitle separate from the body notes (Todoist-style). Displayed as secondary text in list views |
| `created` | datetime (ISO 8601) | yes | Auto-set on creation |
| `modified` | datetime (ISO 8601) | no | Auto-updated on any edit. Enables better sync conflict detection and "recently modified" views |
| `completed` | datetime (ISO 8601) | no | Set when task is marked done |
| `source` | string | yes | Origin of the task: `user`, `shortcut`, or a custom identifier (e.g., `claude-agent`, `obsidian`, `zapier`, `home-automation`). The app sets this to `user` for tasks created in-app and `shortcut` for tasks created via Shortcuts/URL scheme. External tools should set their own identifier. |

### Schema Design Rationale (Todoist & OmniFocus Research)

The schema above was informed by analysis of the Todoist API (REST v2 + Sync v9) and OmniFocus 4 automation/scripting API. Here's what was adopted, adapted, and deliberately excluded:

**Adopted from Todoist:**
- `description` — Todoist separates task content from a description field. This is better than overloading the markdown body for a one-line subtitle that should appear in list views. The body remains for longer notes.
- `modified` timestamp — Todoist tracks `updated_at` on every object. Essential for sync conflict detection and enabling "recently changed" views.

**Adopted from OmniFocus:**
- `scheduled` (OmniFocus calls this `plannedDate`, added in v4.7) — This is the key insight OmniFocus has that most task apps miss. There's a critical distinction between "when is this DUE" and "when do I PLAN to work on this." A task due Friday that you plan to start Wednesday should show up on Wednesday's Today view. Without `scheduled`, you end up abusing `defer` for this purpose, which conflates "hidden until" with "plan to start."
- `flagged` — OmniFocus uses flags as an orthogonal priority axis. Priority is about urgency/importance; flagged is about "I want to see this front and center right now." Having both lets you flag a low-priority task for today without changing its priority.
- `estimated_minutes` — OmniFocus has had this for years and it enables powerful filtering: "show me tasks I can do in under 15 minutes." Also useful for time-blocking integrations in v2.
- `effectiveDeferDate` / `effectiveDueDate` concept — OmniFocus computes "effective" dates that cascade from parent projects to child tasks. We don't need this for v1 (flat task model), but the schema should not preclude it for v2 when project-level dates may cascade.

**Deliberately excluded:**
- Todoist's `section_id` / sections within projects — Our folder structure handles this organically. Sections add complexity without clear benefit for a file-per-task model.
- Todoist's `parent_id` / subtask hierarchy — Todoist and OmniFocus both support subtasks. For v1, we keep it flat. Subtask support can be added in v2 via a `parent` frontmatter field referencing another task's filename.
- Todoist's `assignee_id` / `assigner_id` — Collaboration features are v2+. The schema can be extended when needed.
- OmniFocus's `sequential` project flag — This controls whether tasks in a project must be done in order. Powerful but complex. Deferred to v2.
- OmniFocus's `repetitionRule` distinction between "repeat every", "defer another", and "due again" — OmniFocus has three distinct repeat modes. For v1, we use standard RRULE which maps to "repeat every." The other modes can be added via a `recurrence_type` field in v2.
- Todoist's `duration` object (amount + unit) — Our `estimated_minutes` is simpler and sufficient. Todoist's "day" unit for duration doesn't make practical sense for task time estimation.

**Notes on schema alignment with TaskNotes (Obsidian plugin):**

- Property names are intentionally aligned with the TaskNotes Obsidian plugin for interoperability
- `status` values overlap with TaskNotes conventions
- `recurrence` uses RRULE format, same as TaskNotes
- Additional user-defined frontmatter properties should be preserved (read but not displayed in v1)

### Body Content

Everything below the frontmatter `---` is free-form markdown. In v1, this is rendered as **plain text** in the task detail view. Markdown rendering is a v2 enhancement.

### Folder Structure

**Default:** All task files live in a single flat folder:

```
iCloud Drive/todo.md/
  20250226-1430-buy-groceries.md
  20250226-1445-review-pr-for-auth.md
  20250227-0900-weekly-team-meeting.md
  .order.json
```

**User-organized:** Users may create subfolders for their own organization. The app reads **recursively** and treats folder location as informational only. All hierarchy is determined by frontmatter (`area`, `project`).

```
iCloud Drive/todo.md/
  Work/
    20250226-1445-review-pr-for-auth.md
  Personal/
    20250226-1430-buy-groceries.md
  .order.json
```

### Manual Sort Order

A `.order.json` file at the root of the todo.md folder stores manual sort orders for different views.

```json
{
  "version": 1,
  "views": {
    "inbox": ["20250226-1430-buy-groceries.md", "20250227-0900-weekly-team-meeting.md"],
    "today": ["20250227-0900-weekly-team-meeting.md", "20250226-1430-buy-groceries.md"],
    "project:Meal Prep": ["20250226-1430-buy-groceries.md"],
    "area:Work": ["20250226-1445-review-pr-for-auth.md"]
  }
}
```

- Keys are view identifiers
- Values are ordered arrays of filenames
- Files not in the array appear at the end in default sort (created date)
- The app updates this file on drag-to-reorder

---

## Task Lifecycle

### Creation

1. User creates task via quick entry or detail view
2. App generates filename from timestamp + slugified title
3. App writes `.md` file with frontmatter to iCloud Drive folder
4. App updates local index/cache
5. App schedules local notifications if due or defer date is set

### Completion

1. User checks off task
2. App sets `status: "done"` and `completed: <now>` in frontmatter
3. File remains in place (not moved)
4. **Optional user setting:** Auto-move completed tasks to `Archive/` subfolder

### Completion of Repeating Task

1. User checks off a repeating task
2. App marks the current file as `status: "done"` and sets `completed` timestamp
3. App removes `recurrence` from the completed file (it's now a historical record)
4. App creates a **new** `.md` file with:
   - Same title, area, project, tags, priority, body content
   - Same `recurrence` rule
   - New `created` timestamp
   - `due` and `defer` dates calculated from the RRULE (next occurrence)
   - `status: "todo"`

This approach preserves full task history — every completed instance is its own file.

### Cancellation

User can set `status: "cancelled"`. Task remains in filesystem but is hidden from active views.

### Deferred Tasks (OmniFocus Model)

- A task with `defer: "2025-03-01"` is **hidden** from Today, Upcoming, and Anytime views until March 1
- On March 1, it appears in the appropriate view based on its `due` date
- If `defer` is in the past or null, the task is immediately available
- Deferred tasks are still visible in the "All" view within their project/area, shown with a visual indicator

---

## Views / Navigation

### Sidebar (Primary Navigation)

The app uses a Things-style sidebar for navigation:

| View | Content | Sort Default |
|------|---------|-------------|
| **Inbox** | Tasks where `area` is null AND `project` is null | Manual order |
| **Today** | Tasks where `due` = today, OR `scheduled` = today, OR `defer` ≤ today and `due` = today. Grouped by: Overdue, Scheduled, Due Today, Deferred-now-available | Manual order |
| **Upcoming** | Tasks with a `due` or `scheduled` date in the future, grouped by date | Date ascending |
| **Anytime** | Tasks where `status` = "todo" or "in-progress", `defer` is null or past, not in Someday | Manual order |
| **Someday** | Tasks where `status` = "someday" | Manual order |
| **Flagged** | Tasks where `flagged` = true and not completed | Manual order |
| **--- separator ---** | | |
| **Areas** | Grouped list of areas, expandable to show projects within each area | Manual order |
| **Tags** | List of all tags, tap to filter | Alphabetical |

### Task List View

- Each task row shows: checkbox, title, description subtitle (if set), due date (if set), scheduled date indicator, project pill, priority indicator, flag icon (if flagged), estimated time badge (if set)
- Swipe right: complete
- Swipe left: defer to tomorrow / set date
- Long press: quick actions menu (move to project, set priority, delete)
- Tap: open task detail view

### Task Detail View

- Title (editable, large font)
- Description subtitle (editable, secondary text below title)
- Status toggle
- Flagged toggle (flag icon, Things-style)
- Due date picker
- Scheduled date picker ("When do you plan to work on this?")
- Defer date picker
- Priority selector
- Estimated time picker (quick presets: 5m, 15m, 30m, 1h, 2h, custom)
- Area picker
- Project picker (filtered by selected area)
- Tags (inline chip entry)
- Recurrence rule builder (simple UI: daily, weekly, monthly, yearly + custom)
- Notes section (plain text body content, full screen on tap)
- Delete button (with confirmation)
- Created / Modified / Completed timestamps (read-only, small text)
- Source indicator (read-only, small text — e.g., "Created by claude-agent")

### Quick Entry

- Floating "+" button (bottom right, Things-style)
- Expands to a compact entry form: title field, optional date, optional tags
- Natural language date parsing: "tomorrow", "next friday", "march 1"
- Supports creating task and immediately returning to previous view
- Share sheet extension: share text/URLs from other apps to create a task

---

## Technical Architecture

### Tech Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| UI | SwiftUI | Primary framework, modern declarative UI |
| UI (custom) | UIKit (via UIViewRepresentable) | Escape hatch for Things-level gestures: custom swipe actions, drag-to-reorder, spring animations |
| Data persistence | FileManager + iCloud Drive | `.md` files are the source of truth |
| Local index | SwiftData | In-memory/local cache for fast queries without re-parsing every `.md` file on every view change |
| YAML parsing | Yams (Swift library) | Parse/write YAML frontmatter |
| Markdown parsing | swift-markdown or custom frontmatter splitter | Split frontmatter from body content |
| Date parsing (NLP) | NSDataDetector + custom patterns | "tomorrow", "next friday", etc. |
| Recurrence | Custom RRULE parser or swift-rrule | Calculate next occurrence from RFC 5545 rules |
| Notifications | UNUserNotificationCenter | Local notifications for due dates and defer dates |
| URL scheme | `todomd://` | Deep linking and Shortcuts integration |
| Shortcuts | App Intents framework | "Add Task", "Complete Task", "Get Tasks Due Today" |

### Data Flow

```
┌─────────────────────────────────────────────────┐
│                 iCloud Drive                      │
│           /todo.md/ (folder of .md files)         │
└──────────────────┬──────────────────────────────┘
                   │ FileManager + NSMetadataQuery
                   │ (watch for external changes)
                   ▼
┌─────────────────────────────────────────────────┐
│              FileWatcher Service                  │
│  - Detects new/modified/deleted .md files         │
│  - Parses frontmatter                             │
│  - Updates local SwiftData index                  │
│  - Schedules/updates notifications                │
└──────────────────┬──────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────┐
│            SwiftData Local Index                  │
│  - TaskModel: mirrors frontmatter fields          │
│  - Fast queries for view filtering/sorting        │
│  - Tracks file path for write-back                │
└──────────────────┬──────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────┐
│              SwiftUI Views                        │
│  - Sidebar, List, Detail, Quick Entry             │
│  - Read from SwiftData                            │
│  - Write changes → FileWatcher → .md file         │
└─────────────────────────────────────────────────┘
```

### File Watcher (Critical Component)

The `FileWatcher` is the bridge between the filesystem and the app's UI.

**On app launch / foreground:**
1. Enumerate all `.md` files in the iCloud Drive folder (recursive)
2. Compare against local SwiftData index (by filename + modification date)
3. Parse any new or modified files
4. Remove index entries for deleted files
5. Re-schedule notifications for any changed due/defer dates

**While app is active:**
1. Use `NSMetadataQuery` to watch for iCloud Drive changes
2. On change notification, diff against index and update

**Write path (user edits a task in-app):**
1. Update SwiftData model immediately (optimistic UI)
2. Serialize frontmatter + body to `.md` string
3. Write to iCloud Drive via FileManager
4. FileWatcher ignores self-triggered changes (track via write timestamp)

### iCloud Drive Integration

- Use `FileManager.default.url(forUbiquityContainerIdentifier:)` to get the iCloud container
- Store files in a visible iCloud Drive folder so users can see them in Files.app and Obsidian
- The folder name `todo.md` is user-visible in iCloud Drive
- Handle iCloud download states: files may be "in cloud" and need to be downloaded before reading
- Use `NSFileCoordinator` for safe concurrent access

### Notification System (v1)

**Scheduling logic:**
- When a task has a `due` date: schedule notification at 9:00 AM on the due date
- When a task has a `defer` date: schedule notification at 9:00 AM on the defer date ("Task X is now available")
- When a task has both: schedule both notifications
- Notification identifiers tied to filename for easy cancellation/rescheduling
- Default notification time is 9:00 AM, user-configurable in settings

**Limitations (v1):**
- Notifications are only scheduled/updated when the app is in foreground
- If an external tool (Obsidian, AI agent) creates a task while the app is closed, the notification will be scheduled on next app launch

---

## Visual Design

### Design Language

The app should closely mirror Things 3's visual design:

- **Clean, minimal chrome** — content-first, no unnecessary borders or dividers
- **Generous whitespace** — breathing room between task rows
- **Subtle depth** — light shadows on cards, not flat but not heavy
- **Color as meaning** — priority indicators use color (blue for today, yellow for upcoming, red for overdue)
- **Fluid animations** — spring physics on check/uncheck, smooth list reordering, satisfying completion animation
- **Typography** — SF Pro, with clear hierarchy (title weight/size vs. metadata)

### Color Palette

| Element | Light Mode | Dark Mode |
|---------|-----------|-----------|
| Background | #FFFFFF | #1C1C1E |
| Card/Surface | #F8F8F8 | #2C2C2E |
| Primary text | #000000 | #FFFFFF |
| Secondary text | #8E8E93 | #8E8E93 |
| Accent (today) | #4A90D9 | #5AA3F0 |
| Overdue | #E74C3C | #FF6B6B |
| Priority high | #E74C3C | #FF6B6B |
| Priority medium | #F5A623 | #FFB84D |
| Priority low | #7ED321 | #98E44A |
| Checkbox (unchecked) | #C8C8CC | #48484A |
| Checkbox (checked) | #4A90D9 | #5AA3F0 |

### Key Animations

- **Task completion:** Checkbox fills with accent color, circle contracts with spring, then task row slides out with a slight delay (Things-style satisfaction)
- **Quick entry:** Bottom sheet slides up with spring physics, keyboard appears simultaneously
- **Drag to reorder:** Lifted task gets a subtle shadow and scale increase, other items smoothly part
- **Swipe actions:** Revealed actions slide in with icon + color background (green for complete, blue for defer)
- **View transitions:** Sidebar selection animates content with a horizontal slide

---

## External Integration

### URL Scheme

`todomd://` supports the following actions:

| URL | Action |
|-----|--------|
| `todomd://add?title=Buy+milk&due=2025-03-01&tags=errands` | Create a task |
| `todomd://add?title=Review+PR&area=Work&project=Auth+Service` | Create with area/project |
| `todomd://show/today` | Open Today view |
| `todomd://show/inbox` | Open Inbox view |

### Shortcuts / App Intents

| Intent | Parameters | Return |
|--------|-----------|--------|
| Add Task | title, due, defer, priority, area, project, tags | Task filename |
| Complete Task | task title (fuzzy match) or filename | Success/failure |
| Get Tasks | view (today/inbox/upcoming), area, project, tag | List of task titles |
| Get Overdue Tasks | (none) | List of task titles |

### AI Agent / External Tool Contract

Any tool can create a task by writing a conforming `.md` file to the `iCloud Drive/todo.md/` folder.

**Requirements for external task creation:**
1. File must be in the `todo.md` folder (or a subfolder)
2. File must end in `.md`
3. File must have valid YAML frontmatter with at least `title`, `status`, `created`, and `source`
4. The `source` field should identify the creating tool (e.g., `claude-agent`, `obsidian-tasknotes`, `zapier`, `home-assistant`). This lets the user see where tasks originated and filter by source.
4. Filename should follow the `{YYYYMMDD}-{HHmm}-{slug}.md` convention (but the app will handle non-conforming names gracefully)

**Example script to create a task:**

```bash
#!/bin/bash
TITLE="$1"
SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
TIMESTAMP=$(date -u +"%Y%m%d-%H%M")
FILENAME="${TIMESTAMP}-${SLUG}.md"
FOLDER="$HOME/Library/Mobile Documents/com~apple~CloudDocs/todo.md"

cat > "$FOLDER/$FILENAME" << EOF
---
title: "$TITLE"
status: "todo"
created: "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
source: "cli-script"
---
EOF
```

---

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| Notification time | 9:00 AM | Default time for due/defer date notifications |
| Archive completed | Off | Auto-move completed tasks to Archive/ subfolder |
| Completed task retention | Forever | How long to keep completed tasks visible (forever, 7 days, 30 days) |
| Default priority | None | Priority for new tasks |
| Quick entry default view | Inbox | Where new quick-entry tasks go |
| iCloud folder name | todo.md | Name of the iCloud Drive folder (advanced) |

---

## v1 Scope Summary

### In Scope (v1)

- iPhone app
- Full CRUD on task `.md` files in iCloud Drive
- YAML frontmatter parsing and writing
- Views: Inbox, Today, Upcoming, Anytime, Someday, Flagged, Areas, Projects, Tags
- Scheduled dates (plan-to-work-on vs. hard deadline distinction)
- Flagged tasks with dedicated view
- Estimated time per task
- Task descriptions (subtitle text)
- Manual sort order (drag to reorder) with `.order.json`
- Quick entry with natural language date parsing
- Share sheet extension
- Swipe actions (complete, defer)
- Deferred dates (OmniFocus model)
- Repeating tasks with RRULE
- Local notifications for due and defer dates
- URL scheme (`todomd://`)
- App Intents / Shortcuts support
- Things-style visual design and animations
- Light and dark mode
- Plain text rendering of body content

### Out of Scope (v2+)

- iPad and Mac apps (likely Catalyst or native SwiftUI with NavigationSplitView)
- Background file monitoring (push notifications for externally-created tasks)
- Full markdown rendering in body content
- **Persistent reminders (DUE-style nagging)** — see detail below
- Subtasks (via `parent` frontmatter field referencing another task's filename)
- Sequential projects (tasks must be completed in order, OmniFocus-style)
- Repeat mode variants: "defer another" and "due again" (OmniFocus-style, beyond standard RRULE)
- **Custom perspectives / saved filters** — see detail below
- **Custom app theming** — preset themes (Things, OmniFocus, Todoist, Reminders, etc.) plus full color/shape/typography customization — see detail below
- Time tracking / Pomodoro
- Task dependencies
- Calendar integration (Google/Outlook sync)
- Widgets (home screen, lock screen)
- Search (full-text across all tasks)
- Kanban board view
- Attachments / images in task notes
- Collaboration (shared iCloud folders with multiple users)
- Task templates
- **Import & export (zero lock-in)** — import from Things, OmniFocus, Todoist, Apple Reminders, CSV; export to any format — see detail below
- **Voice ramble mode** — speak naturally, AI parses into structured tasks — see detail below

### Out of Scope (v3)

- **Integrated calendar** — native calendar view combining tasks and calendar events in one UI — see detail below

### Security & Agent Abuse Prevention (OPEN — Requires Deep Design Work)

**Status: Unresolved. This needs dedicated architecture time before v1 ships.**

The filesystem-as-API model is our biggest strength and our most dangerous attack surface. Any process with iCloud Drive access can create, modify, or delete task files. This is the feature — but it's also the risk.

**Threat model:**

| Threat | Vector | Severity |
|---|---|---|
| **Malicious task injection** | A rogue script or compromised automation drops hundreds/thousands of `.md` files into the `todo.md/` folder | High — could overwhelm the user, bury real tasks, or inject offensive content |
| **Task modification/deletion** | An agent or script modifies existing tasks (changing due dates, marking things done, deleting files) | Critical — silent data corruption |
| **Frontmatter injection attacks** | Crafted YAML frontmatter exploits parser vulnerabilities or injects unexpected field values | Medium — depends on parser robustness |
| **Resource exhaustion** | Massive files, deeply nested YAML, or thousands of rapid file changes overwhelm the app | Medium — DoS on the local app |
| **Social engineering via tasks** | An agent creates tasks with misleading titles ("Your account has been compromised — click here") containing malicious URLs in the body | Medium — phishing via task content |
| **Unauthorized source impersonation** | A script sets `source: "user"` to make injected tasks look manually created | Low — cosmetic but erodes trust in the source field |

**Questions to resolve:**

1. **Should we validate or sandbox external writes?** Options range from "trust everything" (current model) to "quarantine files not written by the app until user approves." A quarantine inbox for externally-created files would preserve interoperability while adding a review step.

2. **Rate limiting on file ingestion?** If 500 files appear in one second, should we ingest them all immediately or batch and alert? "247 new tasks were added by `claude-agent` — review?"

3. **Source trust levels?** Should `source` be a trust signal? Files from `source: "user"` (written by the app) could be treated differently from `source: "cli-script"` or `source: "unknown"`. But any process can forge the source field, so this is security theater unless we add signing.

4. **File signing or checksums?** The app could embed a hash or signature in each file it writes. Files without a valid signature are flagged as externally-created. This adds a cryptographic trust layer without breaking interoperability — external files still work, they're just visually distinguished. But it adds complexity and the user may not care.

5. **Frontmatter sanitization?** What happens when a file contains `status: "$(rm -rf /)"` or a 50MB `description` field? The YAML parser needs to be hardened: max field lengths, allowed value ranges, type checking against the schema, rejection of unknown executable-looking content.

6. **Notification abuse?** An injected task with `due: today` and `nag: true` (v2) could trigger persistent notifications the user didn't ask for. External files should probably not be allowed to set `nag: true` by default.

7. **Body content safety?** Markdown body content could contain malicious URLs, JavaScript (if we ever render full HTML), or social engineering text. v1 renders body as plain text (safe). v2 markdown rendering needs an allowlist of safe elements — no `<script>`, no `<iframe>`, no raw HTML.

8. **iCloud shared folder risks?** If/when we add collaboration (v2+), shared iCloud folders mean *other people* can write files into your task system. This escalates every threat above from "rogue script on my machine" to "anyone I share a folder with."

**Minimum v1 safeguards (implement these):**
- YAML parser hardening: max field lengths (title: 500 chars, description: 2000 chars, body: 100KB), type validation against schema, graceful rejection of malformed files
- Rate limit alert: if >50 files are created within 60 seconds, show a user-facing alert with source attribution
- Source badge: visually distinguish externally-created tasks (subtle icon/indicator showing `source` value)
- No raw HTML rendering in body content (plain text only in v1)
- Crash-proof parsing: no file should ever be able to crash the app, regardless of content

**v2+ security roadmap:**
- Optional file signing for app-written tasks
- Quarantine inbox for external files (opt-in setting)
- Per-source permissions ("allow `claude-agent` to create but not modify/delete")
- Notification permission per source (external files can't set `nag: true` without user approval)
- Markdown rendering sandboxing (allowlisted elements only)
- Audit log: `.audit.json` recording all file changes with timestamps and sources

#### Persistent Reminders (v2 Feature Detail)

Inspired by the app **DUE**, persistent reminders are notifications that keep firing at a set interval until the task is completed or explicitly snoozed/dismissed.

**Behavior:**
- A task with `nag: true` and a `due` or `defer` date fires the initial notification at the scheduled time
- If the user does not complete the task or dismiss the notification, a follow-up notification fires at a configurable interval (default: every 5 minutes)
- Nagging continues until the user either: completes the task, snoozes it (pushes to a new time), or explicitly dismisses the nag
- Dismissing a nag does NOT complete the task — it just silences the reminders until the next due date (for repeating tasks) or permanently (for one-off tasks)
- The notification action buttons should include: "Done" (completes the task), "Snooze 1hr", "Snooze until tomorrow", and "Stop nagging"

**Frontmatter extension:**
```yaml
nag: true
nag_interval: 5        # minutes between repeated notifications (default: 5)
```

**Technical considerations:**
- iOS limits local notification scheduling to 64 max pending. Persistent reminders need to pre-schedule a chain of notifications (e.g., 12 notifications at 5-min intervals = 1 hour of nagging) and re-schedule more when the app is opened or a notification is interacted with.
- Use `UNNotificationAction` on the notification category so users can complete/snooze directly from the lock screen without opening the app. Tapping "Done" triggers the app delegate to mark the task complete and cancel remaining nag notifications.
- This feature benefits significantly from background file monitoring (also v2), since completing a task from Obsidian or another tool should cancel the nag chain.
- Consider a user-level global setting: "Enable persistent reminders" (default off). Nagging is polarizing — some people love it, some hate it. Make it opt-in per task via `nag: true` and opt-in globally via settings.

**Important: Ship persistent reminders and background file monitoring together.** Without background monitoring, completing a nagging task from Obsidian or an external tool won't cancel the nag notification chain until the user opens the iOS app — which defeats the purpose. These two features are co-dependent and should be planned as a single v2 milestone.

#### Custom Perspectives / Saved Filters (v2 Feature Detail)

The single most-loved power feature in OmniFocus — and simultaneously its biggest usability complaint. Users love the concept of saved, filtered views but find OmniFocus's perspective builder confusing and its Boolean logic incomplete. Todoist's filter syntax (`#Work & today & p1`) is powerful but requires memorizing a query language.

**Design principles:**
- Visual builder first, query syntax never. Users should construct filters by picking fields, operators, and values from dropdowns — not typing filter strings.
- Every built-in view (Today, Upcoming, Flagged, etc.) should be expressible as a perspective. Show users "here's how Today works" as an editable perspective to teach the mental model.
- Composable conditions with AND/OR/NOT. Full Boolean support — this is a specific OmniFocus complaint we can leapfrog.

**Filterable fields:** All frontmatter fields — `status`, `area`, `project`, `tags` (contains/not contains), `priority`, `flagged`, `due` (before/after/on/none), `scheduled` (before/after/on/none), `defer` (before/after/past/none), `estimated_minutes` (less than/greater than), `source`, `created` (relative: last 7 days, this month, etc.)

**Saved perspective structure:** Stored as a JSON object in `.perspectives.json` at the root of the `todo.md/` folder (same pattern as `.order.json`):
```json
{
  "perspectives": [
    {
      "id": "work-available",
      "name": "Work — Available Now",
      "icon": "briefcase",
      "color": "#4A90D9",
      "filter": {
        "operator": "AND",
        "conditions": [
          { "field": "area", "op": "equals", "value": "Work" },
          { "field": "status", "op": "in", "value": ["todo", "in-progress"] },
          { "field": "defer", "op": "before_or_none", "value": "today" }
        ]
      },
      "sort": { "field": "priority", "direction": "desc" },
      "group_by": "project"
    }
  ]
}
```

**UI placement:** Custom perspectives appear in the sidebar below the built-in views. Users can reorder them. Each gets a custom icon (SF Symbols picker) and accent color.

**Interaction model:**
1. Tap "+" in sidebar → "New Perspective"
2. Name it, pick icon/color
3. Add conditions: "Where [field dropdown] [operator dropdown] [value picker]"
4. Add more conditions with AND/OR toggle
5. Pick sort order and optional grouping
6. Save → appears in sidebar

**Why this is v2, not v1:** The built-in views cover 90% of daily use. Perspectives require the SwiftData index to support arbitrary compound queries efficiently, which is straightforward but needs careful schema design. The visual builder UI is also non-trivial to get right — and getting it wrong would undermine the "simple but powerful" positioning.

#### Custom App Theming (v2 Feature Detail)

Let users make todo.md *feel* like their favorite task app — or something entirely their own. This isn't just a color picker; it's a full visual identity system that controls colors, shapes, typography density, and interaction style.

**Core concept:** A "theme" is a coordinated set of visual parameters that transforms the entire app's look. Ship with curated presets inspired by popular apps, plus a full custom builder.

**Preset themes (ship with these):**

| Theme | Inspiration | Key Characteristics |
|---|---|---|
| **Classic** | Things 3 (default) | Cool gray palette, rounded cards, generous whitespace, subtle shadows, spring animations |
| **Focus** | OmniFocus | Denser layout, more visible metadata per row, purple/gray palette, utilitarian chrome, compact spacing |
| **Minimal** | Todoist | Flat design, red accent, tighter rows, no card shadows, snappy transitions |
| **System** | iOS Reminders | Follows system accent color, grouped inset list style, SF Rounded typography, native feel |
| **Ink** | Pen & paper | Warm cream background, serif headings, checkbox drawn as circles with stroke, minimal color |
| **Dark Pro** | Terminal/Obsidian | True black background, monospace metadata, green accent, no rounded corners, sharp edges |

**Themeable parameters:**

*Colors:*
- Background (primary, secondary, card)
- Text (primary, secondary, tertiary)
- Accent color (used for today badge, active states, tint)
- Overdue color
- Priority colors (high/medium/low)
- Checkbox colors (unchecked stroke, checked fill, animation trail)
- Tag pill colors (auto-derived from accent or per-tag custom)

*Shapes:*
- Corner radius (global scale: 0 = sharp, 16 = pill-shaped)
- Card style: flat / elevated (shadow) / outlined (border) / none (rows only)
- Checkbox shape: circle / rounded square / square
- Divider style: line / inset / none

*Typography:*
- Font family: SF Pro (default) / SF Mono / SF Rounded / New York (serif) / system
- Row density: comfortable (Things-like) / compact (OmniFocus-like) / dense (Todoist-like)
- Metadata visibility: show all inline / show on tap / minimal (title + checkbox only)

*Animation:*
- Completion animation: spring collapse (Things-style) / fade out / strikethrough-then-fade / instant
- Transition style: spring / ease-in-out / snappy / none

**Theme storage:** `.theme.json` at the root of the `todo.md/` folder, consistent with `.order.json` and `.perspectives.json`:
```json
{
  "base": "classic",
  "overrides": {
    "colors": {
      "accent": "#E85D3A",
      "background_primary": "#FAFAF8"
    },
    "shapes": {
      "corner_radius": 4,
      "checkbox_shape": "square"
    },
    "typography": {
      "row_density": "compact"
    }
  }
}
```

Users can start from a preset and override individual parameters. The `base` field inherits all unspecified values from the preset, so a theme file can be as simple as `{"base": "ink"}` or as detailed as a full custom build.

**Theme builder UI:**
1. Settings → Appearance → Theme
2. Pick a preset (live preview as you tap each)
3. "Customize" → categorized editor (Colors, Shapes, Typography, Animation)
4. Each parameter shows a live mini-preview of affected elements
5. "Reset to preset" safety valve

**Community sharing (v2+):** Because themes are just JSON files in iCloud Drive, users can share `.theme.json` files. Consider a simple import: "Paste theme JSON" or "Import from Files." No server-side theme gallery needed — the filesystem handles distribution.

**Why this is v2, not v1:** v1 ships with the Things-inspired default theme plus standard light/dark mode support. The theming engine requires abstracting every color, spacing, and shape value into a token system from day one — which we should architect for in v1's design system even if we don't expose the UI until v2. If we hardcode colors in v1, retrofitting a theming layer is painful.

#### Import & Export — Zero Lock-In (v2 Feature Detail)

This is the feature that makes our data-ownership story credible end-to-end. It's not enough to say "your data is markdown" — we need to make it trivially easy to get data *into* todo.md from other apps and *out of* todo.md into anything else. The pitch: you can adopt todo.md in five minutes, and leave in five minutes. That confidence is what makes people stay.

**Import: Getting in**

| Source | Method | Notes |
|---|---|---|
| **Todoist** | Todoist API (OAuth) | Pull projects, tasks, subtasks, labels, priorities, due dates, descriptions, comments. Map Todoist labels → `tags`, Todoist projects → `project`, Todoist priority 1-4 → `priority` enum. Todoist has no start/defer dates so those fields stay empty. Todoist descriptions → `description`, comments → body notes. |
| **OmniFocus** | Parse OmniFocus backup (`.ofocus` bundle or TaskPaper export) | OmniFocus can export to TaskPaper format, which is plain text and parseable. Map OF folders → `area`, OF projects → `project`, OF tags → `tags`, OF defer dates → `defer`, OF due dates → `due`, OF planned dates → `scheduled`, OF flagged → `flagged`, OF estimated time → `estimated_minutes`. This is the richest import path — nearly 1:1 field mapping. |
| **Things 3** | Things URL scheme + JSON export (via Shortcuts) | Things has no API, but its Shortcuts integration exposes task data. Alternatively, parse the Things SQLite database (documented by community). Map Things areas → `area`, Things projects → `project`, Things tags → `tags`, Things "when" date → `scheduled`, Things deadline → `due`. |
| **Apple Reminders** | EventKit framework | Direct iOS framework access. Map Reminders lists → `project`, due dates → `due`, priorities → `priority`, notes → body, flagged → `flagged`. Limited metadata but covers the basics. |
| **CSV / JSON** | Generic file import | Column/field mapping UI. User maps their columns to todo.md frontmatter fields. Handles exports from TickTick, Notion, Asana, or any tool that exports structured data. |
| **Markdown files** | Drag-and-drop or bulk copy | For users coming from Obsidian task plugins, logseq, etc. Parse existing YAML frontmatter, map known fields, preserve unknown fields as-is. If no frontmatter, treat filename as title and file content as body. |

**Import UX flow:**
1. Settings → Import → Pick source
2. For API sources (Todoist): OAuth flow → preview task count and project structure → confirm
3. For file sources (OmniFocus, CSV): pick file → preview parsed results with field mapping → adjust mapping if needed → confirm
4. All imports create new `.md` files with `source: "import-todoist"` (or whichever source)
5. Show import summary: "Created 247 tasks across 12 projects. 3 tasks had parsing issues (view details)."
6. Non-destructive: never modifies or deletes source data

**Export: Getting out**

This is philosophically simpler because the data is *already* in an open format. But we should still make it easy to leave.

| Format | Method | Notes |
|---|---|---|
| **Markdown (native)** | Already done — it's your `todo.md/` folder | The files are the export. Copy the folder. You're done. |
| **CSV** | Settings → Export → CSV | Flattens frontmatter fields into columns. One row per task. Body content in a `notes` column. Good for spreadsheet analysis or import into other tools. |
| **JSON** | Settings → Export → JSON | Array of objects, each containing all frontmatter fields plus body. Best for programmatic consumption or import into tools with JSON import. |
| **TaskPaper** | Settings → Export → TaskPaper | For OmniFocus users going back. Maps fields to TaskPaper's `@tag(value)` syntax. |
| **Todoist CSV** | Settings → Export → Todoist format | Generates a CSV in Todoist's specific import format (TYPE, CONTENT, PRIORITY, INDENT, AUTHOR, RESPONSIBLE, DATE, DATE_LANG, TIMEZONE). Tested against Todoist's importer. |
| **Apple Reminders** | Settings → Export → Reminders | Uses EventKit to create Reminders entries directly. Lossy (no areas, no defer dates, no estimated time) but functional for the basics. |
| **OPML** | Settings → Export → OPML | Hierarchical outline format. Projects as parent nodes, tasks as children. Good for outliner tools. |

**Export UX flow:**
1. Settings → Export → Pick format
2. Choose scope: All tasks / Active only / Specific area or project / Date range
3. Preview → Export
4. Saves to Files app or shares via share sheet

**Bulk operations:**
- "Export completed tasks older than 6 months" — archive management
- "Export all tasks in [project] as CSV" — for sharing with non-todo.md users or for a spreadsheet review
- Scheduled auto-export (daily/weekly JSON backup to a user-specified iCloud folder) — belt-and-suspenders for the truly paranoid

**The philosophical point:** Export is almost a non-feature for us because the `.md` files *are* the canonical data. The export options exist for two reasons: (1) convenience when someone needs data in a specific format for another tool, and (2) marketing — "look, we have seven export formats" signals commitment to openness even though most users will never need them because their data was never locked in to begin with.

**Why this is v2, not v1:** Import requires building and testing parsers for each source format, plus OAuth flows for API-based imports. Export requires format-specific serializers. Both need solid error handling and edge case coverage (what happens when a Todoist task has 5 levels of subtasks and we only support 1 in v1?). The v1 story is strong enough without it: "your data is markdown files in iCloud Drive." That alone beats every competitor on portability. Import/export makes the story airtight.

#### Voice Ramble Mode (v2 Feature Detail)

Inspired by Todoist's "Ramble" feature (launched 2025). The idea: you speak naturally — a stream-of-consciousness brain dump — and the app parses your speech into structured tasks with all the right frontmatter fields populated.

**Why this matters:** The fastest capture method is speech, but speech is messy. "Oh and I need to, uh, pick up the dry cleaning before Friday, and also remind me to call the dentist next week, that's not urgent though, and I should probably start working on the Q3 deck on Monday, that's for work obviously" — this is how people actually think. Translating that into discrete tasks with dates, projects, and priorities is cognitive overhead that kills capture velocity.

**How it works:**

1. **Trigger:** Long-press the "+" button (or dedicated microphone button) → recording starts
2. **Speech-to-text:** Use Apple's Speech framework (`SFSpeechRecognizer`) for on-device transcription. Real-time — show the text streaming as the user speaks.
3. **AI parsing:** Send the raw transcript to an LLM (Claude API or on-device model) with a structured prompt:
   - Extract discrete tasks from the stream
   - For each task, infer: `title`, `due` (if mentioned), `scheduled` (if "start" language used), `project`/`area` (from context clues), `priority` (from urgency language), `tags` (from topic keywords), `description` (any elaboration beyond the title)
   - Return structured JSON array of tasks
4. **Review screen:** Show parsed tasks in an editable list before committing. Each task shows inferred fields with confidence indicators. User can edit, delete, or approve individual tasks.
5. **Commit:** Approved tasks are written as `.md` files with `source: "voice-ramble"`

**Parsing example:**

*Input transcript:*
> "I need to pick up the dry cleaning before Friday, and call the dentist sometime next week, that's not urgent. Oh and I should start working on the Q3 deck on Monday, that's for work."

*Parsed output:*
| Title | Due | Scheduled | Priority | Area | Source signal |
|---|---|---|---|---|---|
| Pick up dry cleaning | Friday | — | medium | — | "before Friday" → due date |
| Call the dentist | — | next week | low | — | "not urgent" → low priority, "next week" → scheduled |
| Start working on Q3 deck | — | Monday | medium | Work | "start working on Monday" → scheduled, "for work" → area |

**Technical considerations:**
- **On-device vs. cloud parsing:** Speech-to-text should be on-device (privacy, speed). The NLP task extraction could be on-device with a small model or cloud via API. Offer both: on-device for privacy-conscious users (lower accuracy), cloud for better parsing.
- **Latency:** The review screen should appear within 2-3 seconds of the user stopping speech. Pre-parse in streaming chunks if possible.
- **Language support:** Start with English. Apple's Speech framework supports many languages; the NLP parsing layer is the bottleneck.
- **Disambiguation:** "Next Friday" is ambiguous near the weekend. Use the same natural language date parsing logic as quick entry, with the same disambiguation rules.
- **Multi-task detection:** The hard NLP problem. "Pick up groceries and milk" — one task or two? Err on the side of fewer tasks (combine) and let the user split in the review screen.

**Why this is v2, not v1:** Requires either an LLM API integration or a capable on-device model for the NLP parsing step. The review/edit UI for batch task creation is also new UI surface area. v1's quick entry with natural language date parsing covers single-task fast capture well enough.

#### Integrated Calendar (v3 Feature Detail)

The thesis: tasks take time, and time lives on a calendar. Todoist proved this with their 2024 "Year of the Calendar" — it was their most praised feature launch. The ability to see tasks and calendar events in one view fundamentally changes how you plan a day.

**Core concept:** A native calendar view inside todo.md that overlays your tasks onto your existing calendar events (from Apple Calendar / Google Calendar / Outlook). Not a replacement calendar — a unified planning surface.

**Views:**

*Day view:*
- Timeline from 6 AM to midnight (scrollable)
- Calendar events shown as colored blocks (pulled from EventKit / Google Calendar API)
- Tasks with a `scheduled` time shown as draggable blocks on the timeline
- Tasks with only a `scheduled` date (no time) shown in an "unscheduled" tray at the top
- Drag tasks from the tray onto the timeline to time-block them
- Drag to resize task blocks (updates `estimated_minutes`)
- Visual gaps between events = available time, subtly highlighted

*Week view:*
- 7-column grid, compressed timeline
- Calendar events as thin blocks
- Tasks as colored dots/pills at their scheduled time or in a day header tray
- Tap a day to drill into day view
- Drag tasks between days to reschedule

*Month view:*
- Traditional calendar grid
- Dots under dates indicating task count (color-coded: red for overdue, blue for scheduled, gray for done)
- Tap a date to see that day's tasks and events in a bottom sheet

**Task-calendar interactions:**
- **Drag to schedule:** Drag a task from any list view onto the calendar to set its `scheduled` date and time
- **Drag to reschedule:** Move a task block to a different time or day
- **Resize to estimate:** Drag the bottom edge of a task block to set/change `estimated_minutes`
- **Auto-fit:** "Show me where I have 30 free minutes today" — highlight gaps that fit a selected task's estimated time
- **Overdue visibility:** Overdue tasks pinned to the top of today's view with a distinct treatment

**Calendar sources (read-only):**
- Apple Calendar (via EventKit — automatic, no setup)
- Google Calendar (via API, OAuth)
- Outlook/Exchange (via Microsoft Graph API or EventKit if already configured on device)
- CalDAV (generic, covers Fastmail, Proton, etc.)

**What this is NOT:**
- Not a calendar app. You can't create/edit calendar events from todo.md — only view them as context for task planning.
- Not a replacement for Fantastical or Apple Calendar. It's a planning surface, not an event management tool.
- Events are read-only overlays. Tasks are the interactive layer.

**Data model additions:**
- `scheduled_time` (time) — optional time component for `scheduled` date. If set, task appears at that time on the calendar. If only `scheduled` date is set, task appears in the "unscheduled" tray.
- `estimated_minutes` already exists in v1 schema — calendar view gives it a visual representation.

**Why this is v3, not v2:** Calendar integration requires EventKit permissions, potentially Google/Microsoft OAuth flows, a completely new UI paradigm (timeline-based instead of list-based), complex drag-and-drop interactions, and significant performance work (rendering hundreds of events + tasks on a scrollable timeline). It's a major feature surface that could be its own app. v2 should focus on power-user features (perspectives, theming, voice) that enhance the existing list paradigm. v3 introduces the new paradigm.

---

## Implementation Phases

### Phase 1: Foundation (Core Data Layer)

**Goal:** Read and write `.md` files, maintain a local index.

- Set up Xcode project with SwiftUI lifecycle
- Implement iCloud Drive folder access and permissions
- Build YAML frontmatter parser/serializer (using Yams)
- Create `TaskModel` SwiftData schema mirroring frontmatter
- Build `FileWatcher` service: enumerate, parse, diff, index
- Write-back: SwiftData changes → `.md` file updates
- Unit tests for parser, serializer, FileWatcher

### Phase 2: Core Views

**Goal:** Navigate and view tasks.

- Sidebar navigation (tab bar on iPhone, sidebar on iPad when applicable)
- Task list view with basic row layout (title, due date, priority indicator)
- Implement view filtering logic: Inbox, Today, Upcoming, Anytime, Someday
- Area and Project grouping views
- Tag filtering view
- Task detail view (read-only first, then editable)

### Phase 3: Task Editing & Creation

**Goal:** Full CRUD in the app.

- Task detail editing (all frontmatter fields)
- Quick entry bottom sheet with natural language date parsing
- Area/project/tag pickers
- Recurrence rule builder UI
- New task → write `.md` file to iCloud Drive
- Delete task (with confirmation)

### Phase 4: Interactions & Polish

**Goal:** Things-level feel.

- Swipe-to-complete animation (spring physics, checkbox fill, row exit)
- Swipe-to-defer action
- Drag-to-reorder with `.order.json` persistence
- Long-press context menu
- Completion animation for repeating tasks (check → new task appears)
- View transition animations
- Pull-to-refresh (re-scan iCloud folder)

### Phase 5: Notifications & Integration

**Goal:** The app works with the broader ecosystem.

- Local notification scheduling for due and defer dates
- Notification tap → open relevant task
- URL scheme handler (`todomd://`)
- App Intents / Shortcuts integration
- Share sheet extension (create task from shared content)

### Phase 6: Visual Polish & Launch Prep

**Goal:** Ship-ready quality.

- Final color palette and typography pass
- Dark mode refinement
- Empty state designs (no tasks in Inbox, etc.)
- Onboarding flow (iCloud permissions, quick tour)
- App icon and launch screen
- Performance optimization (large vaults: 1000+ tasks)
- TestFlight beta
- App Store assets and description

---

## Key Technical Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| iCloud Drive sync latency | Tasks created externally may not appear immediately | Use `NSMetadataQuery` for real-time iCloud notifications; show sync indicator |
| iCloud conflict resolution | Two devices edit same file simultaneously | Use `NSFileVersion` to detect conflicts; show conflict resolution UI |
| YAML parsing edge cases | Malformed frontmatter from external tools | Graceful degradation: show file in "unparseable" list, don't crash |
| Performance with large vaults | 1000+ `.md` files could be slow to enumerate | SwiftData index makes queries fast; only re-parse modified files |
| RRULE complexity | Some recurrence rules are very complex | Use a well-tested RRULE library; limit UI to common patterns |
| `.order.json` conflicts | Reorder on two devices simultaneously | Last-write-wins with timestamp; merge strategies in v2 |

---

## Dependencies (Swift Packages)

| Package | Purpose | Required |
|---------|---------|----------|
| [Yams](https://github.com/jpsim/Yams) | YAML parsing/serialization | Yes |
| [swift-markdown](https://github.com/apple/swift-markdown) | Markdown parsing (v2 rendering) | No (v2) |
| A RRULE library (TBD — evaluate options) | Recurrence rule calculation | Yes |

Minimize external dependencies. Prefer Apple frameworks where possible.

---

## Development Automation & QA Instructions for Codex

### Philosophy

The developer (Hans) should rarely need to open Xcode manually. Codex should own the build, test, and QA cycle end-to-end. Hans will review outputs, test on-device via TestFlight, and provide feedback — but the compile-test-fix loop should be automated.

### Build Automation

- **Use `xcodebuild` from the command line** for all builds. Do not assume Hans is running Xcode.
- Set up the project with a `Makefile` or `justfile` (preferred) with these targets:
  - `build` — clean build for simulator
  - `build-device` — build for physical device (release config)
  - `test` — run all unit and integration tests
  - `lint` — run SwiftLint (include in project from day one)
  - `format` — run SwiftFormat for consistent code style
  - `archive` — create an archive for TestFlight upload
  - `upload` — upload to TestFlight via `altool` or `xcrun notarytool` (requires credentials setup once)

Example:
```bash
# Full QA cycle in one command
just lint && just test && just build
```

- **Use `xcpretty`** (or `xcbeautify`) to make `xcodebuild` output human-readable.
- **Pin the Xcode version** in `.xcode-version` file for consistency.
- Store the Xcode project settings such that `xcodebuild` works without specifying scheme/destination flags every time (use a `project.yml` with XcodeGen or Tuist to generate the `.xcodeproj` deterministically).

### Project Generation

- **Use XcodeGen or Tuist** to generate the Xcode project from a YAML/Swift spec. This means:
  - No `.xcodeproj` checked into git (add to `.gitignore`)
  - Reproducible project setup: `just generate` recreates the project
  - Easier merge conflict resolution (no pbxproj hell)
  - Codex can modify project structure by editing the spec file, not Xcode GUI

### Testing Strategy

**Unit tests (run on every commit):**
- YAML frontmatter parser: round-trip tests (parse → serialize → parse), malformed input handling
- RRULE calculation: next occurrence for daily/weekly/monthly/yearly, edge cases (end of month, leap year)
- Filename generation: slug creation, collision handling, truncation
- View filtering logic: Today/Upcoming/Anytime/Someday/Inbox membership rules
- Deferred date logic: tasks hidden before defer date, visible after
- `.order.json` read/write/merge
- Natural language date parsing: "tomorrow", "next friday", "in 3 days", "march 1"

**Integration tests:**
- FileWatcher: write a `.md` file to a temp directory, verify it's detected and parsed
- Write-back: modify a SwiftData model, verify the `.md` file is updated correctly
- Repeating task completion: verify new file is spawned with correct dates
- Notification scheduling: verify `UNUserNotificationCenter` requests are created for due/defer dates

**UI tests (Xcode UI Testing framework):**
- Quick entry flow: open → type title → set date → save → verify task appears in correct view
- Completion flow: swipe to complete → verify animation triggers → verify task moves out of active view
- Navigation: tap each sidebar item → verify correct tasks are shown
- Edit flow: tap task → modify fields → save → verify frontmatter is updated

**Snapshot tests (optional but recommended):**
- Use `swift-snapshot-testing` for key views (task row, detail view, sidebar)
- Catches unintentional visual regressions

### Automated QA Checklist

Before any PR or phase completion, Codex should run and report results for:

1. `just lint` — zero warnings
2. `just test` — all unit and integration tests pass
3. `just build` — compiles with zero warnings (treat warnings as errors)
4. `just build-device` — compiles for ARM64 (catches simulator-only code)
5. Manually verify on simulator: launch → create task → complete task → verify file on disk

### CI Pipeline

Set up **GitHub Actions** with:

```yaml
# .github/workflows/ci.yml
on: [push, pull_request]
jobs:
  build-and-test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Generate project
        run: just generate
      - name: Lint
        run: just lint
      - name: Test
        run: just test
      - name: Build
        run: just build
```

- CI must pass before any phase is considered complete
- Add a `just ci` target that runs the full pipeline locally (same steps as GitHub Actions)

### TestFlight Automation

- Set up **Fastlane** (or bare `xcodebuild` + `altool`) for automated TestFlight uploads
- `just release` should: increment build number → archive → upload to TestFlight
- Hans provides signing certificates and App Store Connect API key once during initial setup
- After that, `just release` handles everything

### Error Reporting from Codex

When Codex encounters build failures or test failures, it should:

1. Include the **full error output** (not truncated)
2. State which phase/file/test failed
3. Propose a fix
4. Apply the fix and re-run automatically if confidence is high
5. Only escalate to Hans if the fix is ambiguous or requires a design decision

### Code Quality Standards

- **SwiftLint** with a strict config (no force unwraps, no force casts, max line length 120)
- **SwiftFormat** for consistent style
- All public interfaces must have doc comments
- No `// TODO:` or `// FIXME:` without an associated GitHub issue
- Minimum 80% code coverage on the data layer (parser, FileWatcher, view filtering)
- Zero compiler warnings (warnings as errors in release config)

---

## Competitive Pain Points (User Research)

The following pain points were synthesized from Reddit communities (r/omnifocus, r/todoist, r/productivity, r/thingsapp), GTD forums, review sites (Capterra, G2), and detailed comparison articles. These represent recurring frustrations that todo.md is uniquely positioned to solve.

### Pain Points We Directly Solve

**1. Data ownership and vendor lock-in (CRITICAL — most common complaint across all apps)**
Users consistently express anxiety about their task data being trapped in proprietary databases. Todoist exports to a barely-usable CSV that strips project hierarchy, subtasks, and dates. OmniFocus uses a proprietary SQLite database inside an opaque `.ofocus` bundle. Things stores data in a CloudKit database with no export. Multiple users have written about switching to Joplin, Obsidian, or plain-text systems specifically to own their data. One widely-shared article was literally titled "I ditched Todoist for an open-source notes app to own my data forever."

**todo.md advantage:** This is our entire thesis. Your data is markdown files. Period. No export needed — it's already exported.

**2. Todoist has no start/defer dates (PERSISTENT — years of complaints)**
Todoist officially does not support start dates. Their own help article says so. Users have built elaborate workarounds with labels, tickler projects, and reminder hacks. GTD forum threads about this are *years* long. Todoist finally added "deadlines" in January 2025 (separate from the scheduling date), but it's still not the defer-date model that OmniFocus and Things users expect.

**todo.md advantage:** We have three date types: `due` (hard deadline), `defer` (hidden until), and `scheduled` (plan to work on). This is the most complete date model of any consumer task app.

**3. OmniFocus is too complex / high friction on mobile**
Recurring complaint: OmniFocus is powerful but demands maintenance. Users report spending more time managing the system than doing the work. On iPhone specifically, deep folder hierarchies require 4-5 taps to reach a task. Multiple users describe switching to Things specifically because they could manage tasks one-handed at a bar. The review-cycle and perspective-building learning curve drives people away.

**todo.md advantage:** Things-level visual simplicity with OmniFocus-level data flexibility, achieved through flat views powered by frontmatter metadata rather than deep folder navigation.

**4. OmniFocus UI feels dated compared to Things**
Even loyal OmniFocus users acknowledge the UI is "utilitarian" compared to Things' polish. The 2026 review landscape consistently rates Things highest for visual design and interaction quality. OmniFocus 4 improved but still looks like a power tool, not a consumer app.

**todo.md advantage:** We're explicitly targeting Things-level visual polish. Spring animations, satisfying completion interactions, generous whitespace.

**5. Subscription fatigue and pricing**
OmniFocus is $99.99/year. Todoist Pro is $48/year. Things is a one-time purchase ($50 total across platforms) which users love but the lack of updates worries them. Users regularly complain about paying subscriptions for what feels like a glorified list.

**todo.md advantage:** To be determined, but the open-data model means even if the app disappears, your data is still perfectly usable markdown files. This fundamentally changes the value proposition of any pricing model.

**6. Cross-tool interoperability is nonexistent**
No major task app plays well with others. You can't have an AI agent create a task in Things. You can't edit an OmniFocus task from VS Code. Todoist has an API but your data still lives on their servers. Users who want automation (Shortcuts, scripts, AI agents) are constantly fighting their task app's limitations.

**todo.md advantage:** The filesystem IS the API. Drop a .md file, it's a task. Edit it in Obsidian, Vim, or via a shell script — the app picks it up. No API keys, no authentication, no rate limits.

### Pain Points We Should Learn From (Don't Repeat These Mistakes)

**7. Overdue task guilt / shame spiral**
Both Todoist and OmniFocus users report that overdue items create anxiety rather than motivation. Todoist's Karma system penalizes overdue tasks. Red overdue badges create shame rather than productivity. Users describe the "bankruptcy" moment where they select-all and reschedule everything.

**Design implication:** Our overdue styling should be informational, not punitive. Consider a "reschedule all overdue" batch action. Don't gamify completion in ways that create guilt.

**8. Recurring task inflexibility**
OmniFocus has three repeat modes (repeat every, defer another, due again) and users need all of them. Todoist's recurrence is good but the single-date model makes it confusing. "Mow the lawn every week" vs. "mow the lawn a week after I last mowed it" are fundamentally different, and most apps handle only the first.

**Design implication:** v1 uses RRULE (repeat every). v2 should add defer-another and due-again modes. Already in our v2 scope.

**9. Filters and perspectives are powerful but hard to build**
OmniFocus perspectives are the killer feature AND the biggest usability complaint. Users love the concept of saved, filtered views but find building them confusing. One user specifically complained about incomplete Boolean operations in OmniFocus filter construction.

**Design implication:** For v1, our views are pre-built (Inbox, Today, Upcoming, etc.). For v2, any "custom perspective" builder should be simple — more like "show me tasks where [field] [operator] [value]" with a visual builder, not a query language.

**10. Sync conflicts and data corruption**
OmniFocus 4.8.3 forced a database format migration that locked out users on older macOS versions. Users lost custom perspectives built over years. Todoist sync is generally reliable but opaque — you can't see what's happening. Things uses CloudKit which is reliable but completely opaque.

**Design implication:** Our sync is iCloud Drive file sync, which is transparent and debuggable. Conflict resolution via `NSFileVersion` should be user-visible ("this task was edited on two devices — which version do you want?") rather than silently choosing a winner.

---



1. **RRULE library selection:** Evaluate `RRuleSwift`, `swift-rrule`, or roll a minimal implementation for common patterns (daily, weekly, monthly, yearly).
2. **Natural language date parsing:** `NSDataDetector` vs. a lightweight custom parser. Test coverage of phrases like "next friday", "in 3 days", "end of month".
3. **Performance threshold:** At what file count does full enumeration become unacceptable? Benchmark with 500, 1000, 5000 files.
4. **iCloud container type:** Visible `Documents` folder in iCloud Drive (user can see in Files.app) vs. app-specific container. We want visible — confirm this works with the `todo.md` folder name.
