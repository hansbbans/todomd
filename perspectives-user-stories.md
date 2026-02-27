# Custom Perspectives — User Stories for Codex

> **Feature:** Custom Perspectives / Saved Filters (v2)
> **Source:** Adapted from OmniFocus 4.8.5 perspectives system, simplified for todo.md's frontmatter-based data model.
> **Storage:** `.perspectives.json` at root of `todo.md/` iCloud Drive folder.
> **Index:** All queries run against SwiftData local index, NOT raw file parsing.

---

## Epic 1: Perspective CRUD

### 1.1 Create a new perspective

**As a** user
**I want to** create a new custom perspective from the sidebar
**So that** I can build a saved, filtered view of my tasks tailored to a specific context (e.g., "Work — Available Now", "Quick Wins Under 15 min").

**Acceptance criteria:**
- Tapping "+" at the bottom of the sidebar's "Perspectives" section opens the perspective editor.
- A new perspective is created with default name "Untitled Perspective" and a default rule of `status in [todo, in-progress]` (show active tasks).
- The perspective editor opens immediately, ready for the user to configure name, icon, color, and rules.
- The new perspective is written to `.perspectives.json` on save.
- The new perspective appears in the sidebar under the built-in views.

### 1.2 Edit an existing perspective

**As a** user
**I want to** edit a custom perspective's name, icon, color, and filter rules
**So that** I can refine my saved views as my workflow evolves.

**Acceptance criteria:**
- Long-pressing a custom perspective in the sidebar shows a context menu with "Edit" option.
- Tapping "Edit" opens the perspective editor with all current settings pre-populated.
- Changes are saved to `.perspectives.json` on dismiss/save.
- The sidebar updates immediately to reflect name/icon/color changes.
- The task list re-filters immediately when rules change.

### 1.3 Delete a perspective

**As a** user
**I want to** delete a custom perspective I no longer need
**So that** my sidebar stays clean and relevant.

**Acceptance criteria:**
- Long-pressing a custom perspective shows "Delete" in the context menu.
- A confirmation alert appears: "Delete '[name]'? This cannot be undone."
- On confirm, the perspective is removed from `.perspectives.json` and disappears from the sidebar.
- If the user is currently viewing the deleted perspective, navigate to Inbox.

### 1.4 Reorder perspectives in the sidebar

**As a** user
**I want to** drag custom perspectives to reorder them in the sidebar
**So that** my most-used views are at the top.

**Acceptance criteria:**
- In sidebar edit mode, custom perspectives show drag handles.
- Drag-and-drop reorders custom perspectives relative to each other.
- Built-in views (Inbox, Today, Upcoming, etc.) are NOT reorderable — they always appear above custom perspectives.
- Order is persisted in the `order` array within `.perspectives.json`.

### 1.5 Duplicate a perspective

**As a** user
**I want to** duplicate an existing perspective
**So that** I can create a variant without starting from scratch.

**Acceptance criteria:**
- Long-press context menu includes "Duplicate."
- Duplicated perspective is named "[Original Name] Copy" and placed below the original.
- All rules, sort, grouping, icon, and color are copied.
- The duplicate is immediately editable.

---

## Epic 2: Perspective General Settings (Name, Icon, Color)

### 2.1 Set perspective name

**As a** user
**I want to** give my perspective a descriptive name
**So that** I can identify it at a glance in the sidebar.

**Acceptance criteria:**
- Name field is a text input at the top of the perspective editor.
- Max 100 characters.
- Name displays in the sidebar tab.

### 2.2 Choose an icon

**As a** user
**I want to** pick an icon for my perspective from SF Symbols
**So that** I can visually distinguish it from other perspectives.

**Acceptance criteria:**
- Tapping the icon well opens an SF Symbols picker.
- Picker shows a curated grid of ~50 relevant symbols (briefcase, house, star, heart, bolt, clock, tag, etc.) plus a search field for the full SF Symbols catalog.
- Selected icon appears in the sidebar tab and at the top of the perspective's task list.
- Default icon is `list.bullet` if none selected.

### 2.3 Choose a color

**As a** user
**I want to** assign a color to my perspective
**So that** it has a distinct visual identity.

**Acceptance criteria:**
- Tapping the color swatch opens a color picker.
- Picker shows 12 pre-selected colors (matching the app's design palette) plus a "Custom…" option that opens the system color picker.
- Color is applied to: sidebar icon tint, perspective header accent, and the active/selected state in the sidebar.
- Default color is the app's accent color if none selected.

---

## Epic 3: Filter Rules (Contents)

### 3.1 Add a filter rule

**As a** user
**I want to** add filter rules to my perspective
**So that** only tasks matching specific criteria appear.

**Acceptance criteria:**
- Tapping "Add Rule" presents a list of available rule types (see 3.4).
- Each rule type has a human-readable label and an icon.
- The new rule is added beneath the current top-level logical operator.
- The task list updates live as rules are added.

### 3.2 Configure logical operators (AND / OR / NOT)

**As a** user
**I want to** combine rules with AND, OR, and NOT logic
**So that** I can build complex filters without learning a query language.

**Acceptance criteria:**
- The top-level rule group defaults to "All of the following" (AND).
- Tapping the top-level label cycles through: "All of the following" (AND), "Any of the following" (OR), "None of the following" (NOT).
- Nested rule groups can be added via "Add Rule → All / Any / None of the following."
- Rules can be dragged between groups to change their logical scope.
- Nesting is supported to at least 3 levels deep.
- Visual indentation clearly shows the hierarchy.

**Example composite filter:**
```
All of the following:
  ├─ area equals "Work"
  ├─ status in [todo, in-progress]
  └─ Any of the following:
       ├─ priority equals "high"
       └─ flagged equals true
```
This shows: active Work tasks that are either high-priority OR flagged.

### 3.3 Remove or disable a rule

**As a** user
**I want to** remove or temporarily disable a rule
**So that** I can experiment with filters without losing my configuration.

**Acceptance criteria:**
- Each rule row has a "..." menu with "Turn Off" and "Delete" options.
- "Turn Off" grays out the rule and excludes it from filtering, but keeps it in the editor.
- "Delete" removes the rule entirely.
- Turning a rule off/on updates the task list immediately.

### 3.4 Available filter rules

**As a** user
**I want to** filter on any frontmatter field
**So that** I can build perspectives around any attribute of my tasks.

**Available rules (mapped from todo.md frontmatter schema):**

| Rule | Options | Maps to |
|------|---------|---------|
| **Status** | `todo`, `in-progress`, `done`, `cancelled`, `someday` | `status` field |
| **Priority** | `none`, `low`, `medium`, `high` | `priority` field |
| **Flagged** | `true` / `false` | `flagged` field |
| **Has a due date** | (boolean — has or doesn't have) | `due` field exists |
| **Has a scheduled date** | (boolean) | `scheduled` field exists |
| **Has a defer date** | (boolean) | `defer` field exists |
| **Due date in range** | On / Before / After / Between + date picker | `due` field value |
| **Scheduled date in range** | On / Before / After / Between + date picker | `scheduled` field value |
| **Defer date in range** | On / Before / After / Between + date picker | `defer` field value |
| **Created date in range** | On / Before / After / Between + date picker | `created` field value |
| **Completed date in range** | On / Before / After / Between + date picker | `completed` field value |
| **Modified date in range** | On / Before / After / Between + date picker | `modified` field value |
| **Area equals** | Picker from existing areas | `area` field |
| **Project equals** | Picker from existing projects | `project` field |
| **Is in area** | Picker (shows all tasks in the area, any project) | `area` field |
| **Is in project** | Picker (shows all tasks in the project) | `project` field |
| **Has no area or project** | (boolean — equivalent to "is in Inbox") | `area` and `project` both nil |
| **Is tagged with any of** | Tag picker (multi-select) | `tags` array contains any |
| **Is tagged with all of** | Tag picker (multi-select) | `tags` array contains all |
| **Is untagged** | (boolean) | `tags` array is empty |
| **Has estimated time** | (boolean) | `estimated_minutes` field exists |
| **Estimated time less than** | 5 min / 15 min / 30 min / 60 min | `estimated_minutes` < value |
| **Estimated time greater than** | 15 min / 30 min / 60 min / 120 min | `estimated_minutes` > value |
| **Is repeating** | (boolean) | `recurrence` field exists |
| **Source equals** | Text input or picker from seen sources | `source` field |
| **Title contains** | Text input (case-insensitive substring match) | `title` field |
| **Body contains** | Text input (full-text search on body content) | markdown body |
| **All of the following** | (logical group — AND) | — |
| **Any of the following** | (logical group — OR) | — |
| **None of the following** | (logical group — NOT) | — |

### 3.5 Date range rules support relative dates

**As a** user
**I want to** use relative date expressions like "today", "in the next 7 days", "in the past 30 days"
**So that** my perspectives automatically update without me editing them.

**Acceptance criteria:**
- Date range rules accept: specific dates (via date picker), "Yesterday", "Today", "Tomorrow", "In the past [N] [days/weeks/months]", "In the next [N] [days/weeks/months]", "Between [date] and [date]".
- Relative dates are evaluated at perspective load time, so "Today" always means the current day.
- The picker shows a preview of what the relative date resolves to (e.g., "In the next 7 days → Feb 27 – Mar 6").
- Stored in `.perspectives.json` as: `{"op": "in_next", "value": 7, "unit": "days"}`.

### 3.6 Live preview while building rules

**As a** user
**I want to** see the task list update in real-time as I add and modify rules
**So that** I can verify my perspective shows what I expect.

**Acceptance criteria:**
- The perspective editor is presented as a half-sheet (bottom sheet) over the task list.
- As rules are added/changed/removed, the task list behind the editor re-filters immediately.
- A task count badge shows at the top of the editor: "Showing [N] tasks."
- If zero tasks match, show an empty state: "No tasks match these rules. Try adjusting your filters."

---

## Epic 4: Sort & Group Options (Structure)

### 4.1 Choose sort order

**As a** user
**I want to** choose how tasks are sorted within my perspective
**So that** the most important or urgent tasks appear first.

**Acceptance criteria:**
- Sort picker in perspective editor with options:
  - Due date (earliest first)
  - Scheduled date (earliest first)
  - Defer date (earliest first)
  - Priority (highest first)
  - Estimated time (shortest first)
  - Title (A-Z)
  - Created date (newest first)
  - Modified date (newest first)
  - Completed date (newest first)
  - Flagged status (flagged first, then by due date)
  - Manual (user drag-to-reorder)
- Default sort: Due date.
- Sort direction: Primary direction is built into each option (e.g., due = earliest first). No separate asc/desc toggle needed — each option implies a sensible direction.

### 4.2 Choose grouping

**As a** user
**I want to** group tasks by a field
**So that** I can see related tasks organized under headers.

**Acceptance criteria:**
- Group picker in perspective editor with options:
  - None (flat list)
  - Area
  - Project
  - Tag (tasks with multiple tags appear under each tag)
  - Tags (combined — tasks appear once, grouped by tag combination)
  - Priority
  - Due date (grouped by day, with increasing granularity near today)
  - Scheduled date (grouped by day)
  - Defer date (grouped by day)
  - Flagged status (flagged first, then unflagged)
  - Source
- Default grouping: None.
- Group headers are collapsible (tap to expand/collapse).
- Group headers show a task count badge.

### 4.3 Manual reordering within a perspective

**As a** user
**I want to** manually reorder tasks within a perspective by dragging
**So that** I can prioritize tasks in a custom order that makes sense to me.

**Acceptance criteria:**
- When sort is set to "Manual", tasks can be dragged to reorder.
- Manual order is stored per-perspective in `.perspectives.json` under a `manual_order` key (array of filenames).
- A "Reset Order" button re-sorts by the last non-manual sort option.
- When sort is NOT manual, drag-to-reorder is disabled.

---

## Epic 5: Perspective Layout

### 5.1 Custom row density per perspective

**As a** user
**I want to** choose how much metadata appears in each task row for this perspective
**So that** I can make some perspectives dense (showing many tasks at once) and others detailed.

**Acceptance criteria:**
- Layout picker in perspective editor with options:
  - Default (uses app-wide setting)
  - Comfortable (title, description, due/scheduled indicators, project pill, flag — same as Things-style default)
  - Compact (title, due indicator, priority dot — one line per task)
  - Detailed (title, description, all date fields, project, area, tags, estimated time — two or three lines per task)
- Layout selection is per-perspective and stored in `.perspectives.json`.

---

## Epic 6: Persistence & Sync

### 6.1 Perspectives persist in `.perspectives.json`

**As a** user
**I want to** have my perspectives saved to a JSON file in my iCloud Drive `todo.md/` folder
**So that** they sync across devices and can be edited by external tools.

**Acceptance criteria:**
- All perspective data is stored in `todo.md/.perspectives.json`.
- File is created on first perspective creation if it doesn't exist.
- File is valid JSON and human-readable (pretty-printed, 2-space indent).
- Schema:
```json
{
  "version": 1,
  "order": ["perspective-id-1", "perspective-id-2"],
  "perspectives": {
    "perspective-id-1": {
      "id": "perspective-id-1",
      "name": "Work — Available Now",
      "icon": "briefcase",
      "color": "#4A90D9",
      "rules": {
        "operator": "AND",
        "conditions": [
          { "field": "area", "op": "equals", "value": "Work" },
          { "field": "status", "op": "in", "value": ["todo", "in-progress"] },
          {
            "operator": "OR",
            "conditions": [
              { "field": "priority", "op": "equals", "value": "high" },
              { "field": "flagged", "op": "equals", "value": true }
            ]
          }
        ]
      },
      "sort": { "field": "due", "direction": "asc" },
      "group_by": "project",
      "layout": "default",
      "manual_order": null
    }
  }
}
```
- File is written atomically (write to temp, then rename) to avoid corruption.

### 6.2 External perspective creation

**As a** user or external tool
**I want to** create or modify perspectives by editing `.perspectives.json` directly
**So that** AI agents and scripts can set up custom views for me.

**Acceptance criteria:**
- The app watches `.perspectives.json` via the same `NSMetadataQuery` / FileWatcher system used for task files.
- External changes to the file are detected and reflected in the sidebar within a few seconds.
- If the JSON is malformed, the app shows a non-blocking warning ("Perspectives file has errors — using last valid version") and does not crash.
- If an externally-added perspective references fields or operators the app doesn't recognize, the perspective is shown with a warning badge and the unknown rules are ignored (not deleted).

### 6.3 iCloud sync for perspectives

**As a** user
**I want to** have my perspectives sync across all my devices via iCloud Drive
**So that** perspectives I create on my iPhone are available everywhere.

**Acceptance criteria:**
- `.perspectives.json` syncs via iCloud Drive like any other file in the `todo.md/` folder.
- Conflict resolution: if two devices edit perspectives simultaneously, use `NSFileVersion` to detect the conflict and prompt the user to choose a version (same as task file conflicts).
- Perspective changes on one device appear on other devices within iCloud sync latency (typically seconds to minutes).

---

## Epic 7: Built-in View Expressibility

### 7.1 Show built-in views as editable perspectives

**As a** user
**I want to** see how built-in views (Today, Upcoming, Flagged, etc.) are defined as filter rules
**So that** I can understand the perspective model and use it to build my own.

**Acceptance criteria:**
- Each built-in view has a "View Rules" option (read-only) in its View Options.
- The rules are displayed using the same visual editor as custom perspectives.
- Example — **Today** view rules:
  ```
  Any of the following:
    ├─ Due date in range: On Today
    ├─ Scheduled date in range: On Today
    └─ Defer date in range: On or Before Today
  AND
  None of the following:
    └─ Status in [done, cancelled]
  ```
- Built-in view rules are NOT editable. To customize, the user must "Duplicate as Custom Perspective" which creates an editable copy.
- The "Duplicate as Custom Perspective" button appears at the bottom of the read-only rule view.

---

## Epic 8: SwiftData Query Engine

### 8.1 Perspective rules translate to SwiftData predicates

**As a** developer (Codex)
**I want to** translate perspective rule JSON into SwiftData `#Predicate` expressions
**So that** perspectives query the local index efficiently.

**Acceptance criteria:**
- A `PerspectiveQueryBuilder` class accepts a `PerspectiveRules` struct (decoded from JSON) and returns a `Predicate<TaskItem>`.
- Logical operators map to: AND → `&&`, OR → `||`, NOT → `!`.
- Field operators map to:
  - `equals` → `==`
  - `not_equals` → `!=`
  - `in` → `.contains()`
  - `contains` (for tags) → check if tags array contains value
  - `before` / `after` / `on` / `between` → date comparison operators
  - `less_than` / `greater_than` → `<` / `>`
  - `is_nil` / `is_not_nil` → `== nil` / `!= nil`
  - `string_contains` → `.localizedStandardContains()`
- Nested rule groups recurse correctly.
- Unit tests cover: single rule, AND combination, OR combination, NOT exclusion, nested AND-within-OR, date range with relative dates, tag contains, empty rules (show all), conflicting rules (show none).

### 8.2 Sort and group translate to SwiftData sort descriptors

**As a** developer (Codex)
**I want to** translate sort/group options into SwiftData `SortDescriptor` arrays
**So that** the query returns results in the correct order.

**Acceptance criteria:**
- Each sort option maps to a `SortDescriptor<TaskItem>`:
  - `due` → `SortDescriptor(\.due, order: .forward)` with nil-last behavior
  - `priority` → custom comparator (high > medium > low > none)
  - `title` → `SortDescriptor(\.title, comparator: .localizedStandard)`
  - etc.
- Group-by queries add a secondary sort or partition by the group field.
- Manual sort returns items in the order specified by the `manual_order` array.

---

## Epic 9: Edge Cases & Error Handling

### 9.1 Handle empty perspectives gracefully

**As a** user
**I want to** see a helpful empty state when a perspective matches zero tasks
**So that** I know the perspective is working but there's nothing to show.

**Acceptance criteria:**
- Empty state shows: icon of the perspective, name, and message: "No tasks match this perspective's filters."
- Below the message: "Edit Rules" button to quickly modify the perspective.

### 9.2 Handle corrupted `.perspectives.json`

**As a** user
**I want to** not lose my perspectives if the JSON file gets corrupted
**So that** external editing errors don't destroy my setup.

**Acceptance criteria:**
- On launch, if `.perspectives.json` fails to parse, the app: loads from the last known good cached version (kept in SwiftData), shows a warning banner: "Perspectives file could not be read. Using cached version.", and writes a `.perspectives.json.backup` copy of the corrupted file for debugging.
- The app never crashes due to a malformed perspectives file.

### 9.3 Handle unknown fields in rules

**As a** user
**I want to** be able to add frontmatter fields in the future without breaking existing perspectives
**So that** the schema can evolve.

**Acceptance criteria:**
- If a rule references a field name not in the current schema, the rule is skipped (treated as always-true for AND, always-false for OR) and a small warning icon appears on the rule in the editor.
- Unknown fields are preserved in the JSON — they are not deleted on save.

### 9.4 Performance with many perspectives

**As a** developer (Codex)
**I want to** ensure perspectives perform well even with complex rules and large task counts
**So that** switching between perspectives feels instant.

**Acceptance criteria:**
- Switching to a perspective with up to 10 rules across 1,000 tasks completes in < 100ms.
- SwiftData index is used for all queries — no file parsing at query time.
- Benchmark tests verify performance at 500, 1,000, and 5,000 task counts.

---

## Non-Functional Requirements

| Requirement | Target |
|---|---|
| Perspective switch latency | < 100ms for 1,000 tasks, 10 rules |
| `.perspectives.json` max size | Warn at > 1MB (indicates hundreds of perspectives) |
| Max perspectives | No hard limit; sidebar scrolls. Recommend < 20 for usability. |
| Max rules per perspective | No hard limit; warn at > 25 rules (likely over-engineered) |
| Max nesting depth | 5 levels (beyond this, suggest simplifying) |
| Accessibility | All perspective editor controls must be VoiceOver-navigable |
| Animation | Sidebar perspective reorder uses spring animation matching task drag behavior |

---

## Out of Scope (v3+)

- Shared perspectives between users (requires collaboration features)
- Perspective-specific notification rules ("notify me when this perspective has > 5 tasks")
- Smart perspectives that auto-generate based on usage patterns
- Perspective widgets on home screen / lock screen (requires Widget feature)
- Full-text search within perspective editor (searching across all perspectives' rules)
