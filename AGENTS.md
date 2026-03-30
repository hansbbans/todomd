# AI Agent Task Operations Guide (todo.md)

This document defines how an AI agent should create and update task files in a todo.md workspace.

## 1) Scope

- The source of truth is the filesystem.
- The app reads task files recursively from the selected folder.
- The app tracks Markdown task files and explicitly ignores `AGENTS.md`.
- Each task is one Markdown file with YAML frontmatter plus a Markdown body.
- Agents MUST preserve valid existing data unless the user explicitly asks to change it.

## 2) Canonical Task File Shape

Each task file should follow:

```markdown
---
<yaml frontmatter>
---
<markdown body>
```

Notes:

- The body may be empty.
- The serializer writes a trailing newline at EOF.
- The body may contain plain notes, a managed checklist block, or both.
- Canonical agent-written tasks SHOULD include at least:
  - `title`
  - `source`
  - `status: todo`
  - `priority: none`
  - `flagged: false`
  - `created: <UTC ISO8601 datetime>`
  - `ref: t-xxxx`
- The parser is more forgiving for older imports, but agents SHOULD write the canonical shape rather than relying on compatibility fallbacks.

## 3) Canonical Frontmatter Schema

Supported canonical keys:

- `ref` string, pattern `^t-[0-9a-f]{4,6}$`
- `title` string
- `status` enum: `todo`, `in-progress`, `done`, `cancelled`, `someday`
- `due` date `YYYY-MM-DD`
- `due_time` time `HH:MM` (24h, requires `due`)
- `persistent_reminder` boolean (requires both `due` and `due_time`)
- `defer` date `YYYY-MM-DD`
- `scheduled` date `YYYY-MM-DD`
- `scheduled_time` time `HH:MM` (24h, requires `scheduled`)
- `priority` enum: `none`, `low`, `medium`, `high`
- `flagged` boolean
- `area` string
- `project` string
- `tags` string array (canonical write form; parser also accepts a comma-separated string on read)
- `recurrence` string RRULE
- `estimated_minutes` integer in `[0, 100000]`
- `description` string
- `location_name` optional string
- `location_latitude` number in `[-90, 90]`
- `location_longitude` number in `[-180, 180]`
- `location_radius_meters` number in `[50, 1000]` (default `200`)
- `location_trigger` enum: `arrive`, `leave` (default `arrive`)
- `created` ISO8601 datetime in UTC
- `modified` ISO8601 datetime in UTC
- `completed` ISO8601 datetime in UTC
- `assignee` string
- `completed_by` string
- `blocked_by` one of:
  - `true` for a manual block
  - a single task ref string
  - an array of task ref strings
  - `false`, `null`, or omission for unblocked
- `source` string

Unknown frontmatter keys MAY exist. On updates, preserve them unless explicitly asked to remove them.

Field semantics that are easy to get wrong:

- `description` is a short subtitle shown in list views. It is separate from the body.
- The body is where long notes live.
- Checklist items are stored in the body, not in frontmatter.
- `blocked_by` is orthogonal to `status`; blocked tasks are usually still `todo` or `in-progress`.
- `recurrence` support in core is limited to `FREQ=DAILY|WEEKLY|MONTHLY|YEARLY`, optional `INTERVAL`, and optional `BYDAY` for weekly rules. Do not assume broader RRULE support.

## 4) Body Format And Managed Checklists

The body is free-form Markdown notes plus an optional managed checklist block at the end.

Canonical managed checklist format:

```markdown
Notes about the trip.

<!-- todo.md checklist -->
- [ ] Passport
- [x] Charger
```

Rules:

- The checklist block is identified by the exact marker `<!-- todo.md checklist -->`.
- The marker must introduce the trailing managed checklist block.
- After the marker, only blank lines and checkbox lines are allowed for the block to be recognized.
- Canonical checkbox lines should use `- [ ] Item` and `- [x] Item`.
- The parser also accepts `*` and `+` bullets and uppercase `X`, but canonical writes should normalize to `- [ ]` / `- [x]`.
- If non-checklist content appears after the marker, the app treats the whole body as notes and does not manage a checklist block.
- Checkbox-looking text in normal notes does not count as a managed checklist unless it is inside the explicit trailing checklist block.
- Checklists are simple sub-items only. They are not separate tasks, dependencies, or subtasks.

Agent guidance:

- If the user asks to change notes only, preserve the checklist block exactly.
- If the user asks to change checklist items only, preserve the notes exactly.
- If the user asks to add a checklist to a notes-only body, append a blank line, the marker, and canonical checkbox lines.
- Do not append free-form notes after the managed checklist marker.

## 5) Compatibility On Read, Canonical On Write

The parser accepts older or non-canonical inputs. Agents updating existing tasks should understand them, then write back canonical data.

Compatibility behaviors implemented in code:

- Known frontmatter keys are read case-insensitively.
- Legacy key aliases are accepted on read:
  - `dateCreated` -> `created`
  - `dateModified` -> `modified`
  - `completedDate` -> `completed`
  - `completedBy` -> `completed_by`
  - `blockedBy` -> `blocked_by`
- Status aliases accepted on read:
  - `to-do` -> `todo`
  - `open`, `pending` -> `todo`
  - `inprogress`, `doing` -> `in-progress`
  - `complete`, `completed` -> `done`
  - `canceled` -> `cancelled`
  - `maybe` -> `someday`
- Priority aliases accepted on read:
  - `p1` -> `high`
  - `p2`, `normal`, `med` -> `medium`
  - `p3` -> `low`
  - `p4` -> `none`
- `tags` may be read from either a YAML string list or a comma-separated string, but agents should write a YAML string list.
- `blocked_by: false` is accepted on read and behaves like unblocked; canonical writes should omit `blocked_by` when unblocked.
- If `title` is missing, the parser can fall back to the filename stem.
- If `source` is missing, the parser defaults it to `"unknown"`.
- If `status` or `priority` is missing, they default to `todo` and `none`.
- Unknown or unsupported `status` / `priority` values also fall back to `todo` / `none`.

Agent rule: when you rewrite a task, write canonical keys and canonical enum values.

## 6) Filename Rules

Default filename format:

- `{YYYYMMDD}-{HHmm}-{slug}.md` in UTC

Slug rules:

- lowercase
- replace non `[a-z0-9]` runs with `-`
- collapse repeated `-`
- trim leading/trailing `-`
- truncate to 60 characters
- fallback to `task` if empty

Collision handling:

- If the base filename already exists, append `-2`, `-3`, and so on.

If a preferred filename is provided:

- trim surrounding whitespace
- append `.md` if it is missing
- otherwise preserve the requested filename

## 7) Task Identity And Lookup

When the user asks to update a task:

1. Prefer an explicit file path if provided.
2. Else prefer exact `ref` match.
3. Else use exact title match.
4. Else use case-insensitive contains match and ask for clarification if multiple candidates remain.

Never silently update multiple files unless the user explicitly asked for a bulk update.

## 8) Create Task Workflow

1. Build frontmatter with canonical fields and sensible defaults.
2. Set `created` to the current UTC timestamp.
3. Set or preserve a valid unique `ref`.
4. Validate all constraints before write.
5. Generate a collision-safe filename if the user did not provide one.
6. Write the file atomically.

Reference handling:

- If you are creating a task by writing a file directly, generate a valid unique `ref` yourself when possible.
- If repository code is doing the create:
  - a valid unique `ref` is preserved
  - otherwise a new one is generated
  - generation uses 4 hex digits normally and upgrades to 6 hex digits for new refs when the known task set is very large

Minimum canonical create template:

```markdown
---
ref: t-1a2b
title: "Example task"
status: todo
priority: none
flagged: false
created: "2026-03-21T13:40:00.000Z"
source: codex-agent
---

```

Example create template with notes and checklist:

```markdown
---
ref: t-1a2b
title: "Pack for flight"
status: todo
priority: medium
flagged: false
created: "2026-03-21T13:40:00.000Z"
source: codex-agent
---
Trip notes and reminders.

<!-- todo.md checklist -->
- [ ] Passport
- [ ] Charger
```

## 9) Update Task Workflow

1. Load and parse the existing file.
2. Apply only the requested field and/or body changes.
3. Preserve untouched known fields, unknown frontmatter, notes, and checklist content.
4. Set `modified` to the current UTC timestamp for any successful update.
5. Re-validate all constraints before write.
6. Write back atomically.

Normalization rules:

- Always write canonical `status` and `priority` values.
- Keep dates as `YYYY-MM-DD`.
- Keep times as `HH:MM`.
- Keep `tags` as a YAML string list.
- Trim whitespace-only string values to null/remove where appropriate.
- Keep the managed checklist marker exact if a checklist exists.

## 10) Status Transition Workflows

Standard completion:

- set `status: done`
- set `completed: <now UTC>`
- set `completed_by` to a stable identity such as `codex-agent`
- set `modified: <now UTC>`
- the app can infer missing completion metadata for externally edited completed tasks, but agents SHOULD still write `completed` and `completed_by` explicitly instead of relying on inference

Cancellation:

- if you are explicitly cancelling a task, mirror app behavior:
  - set `status: cancelled`
  - set `completed: <now UTC>`
  - set `completed_by` to the cancelling identity
  - set `modified: <now UTC>`

Reopening a completed or cancelled task:

- when moving from `done` or `cancelled` back to an active state such as `todo`, `in-progress`, or `someday`:
  - clear `completed`
  - clear `completed_by`
  - set `modified: <now UTC>`
- the app can also clear stale completion metadata during sync, but agents SHOULD clear it explicitly

Repeating task completion (`recurrence` exists):

1. Mark the current task completed.
2. Remove `recurrence` from the completed record.
3. Create a new task file for the next instance.

The next instance should:

- receive a new unique `ref`
- keep the original `recurrence`
- set `status: todo`
- set new `created` and `modified` timestamps to now
- clear `completed` and `completed_by`
- preserve body notes, managed checklist items, description, tags, assignee, source, unknown frontmatter, and other unchanged user-visible data
- advance `due`, `defer`, and `scheduled` to the next occurrence when present
- preserve `due_time` and `scheduled_time`

## 11) Validation Checklist

These constraints must pass before write:

- `title` must be non-empty and at most 500 characters
- `source` must be non-empty
- `description` max 2000 characters
- `location_name` max 200 characters
- body max 100000 characters
- `assignee`, `completed_by`, and `ref` max 120 characters
- tags count <= 100
- each tag <= 80 characters
- `blocked_by` ref count <= 50
- each `blocked_by` ref must be non-empty and <= 120 characters
- `estimated_minutes` must be in `[0, 100000]`
- `ref` must match `t-[0-9a-f]{4,6}` when present
- `due_time` is only allowed when `due` is set
- `scheduled_time` is only allowed when `scheduled` is set
- `persistent_reminder: true` is only allowed when both `due` and `due_time` are set
- if any location reminder fields are used, latitude and longitude are required
- `location_latitude` must be in `[-90, 90]`
- `location_longitude` must be in `[-180, 180]`
- `location_radius_meters` must be in `[50, 1000]`
- `location_trigger` must be `arrive` or `leave`

Parser hardening limits also exist:

- frontmatter nesting depth over 24 is rejected
- frontmatter node count over 2000 is rejected

Agent rule: keep frontmatter simple and flat. Do not introduce deeply nested custom objects unless the user explicitly wants them and you are confident they remain within parser limits.

## 12) Safe Edit Rules

- Do not delete files to "complete" tasks; completion is a status change.
- Do not rewrite unrelated fields when making a narrow update.
- Do not drop unknown frontmatter keys.
- Do not silently coerce invalid user intent; return a clear validation error and suggested fix.
- Do not convert notes into checklist items or checklist items into notes unless the user asked for that.
- Do not add prose after the managed checklist marker.
- Do not assume arbitrary RRULE features beyond the recurrence support implemented in core.
- Do not assume every `.md` file in the workspace is a task file.

## 13) Example Update (Field Only)

User request: "Set due date to 2026-03-05 and priority high for ref t-1a2b."

Expected changes:

- `due` => `2026-03-05`
- `priority` => `high`
- `modified` => now (UTC)
- all other frontmatter keys and body content unchanged

## 14) Example Update (Checklist Only)

User request: "Add checklist item 'Adapter' to t-1a2b."

Expected changes:

- preserve all frontmatter
- preserve notes above the checklist block
- append `- [ ] Adapter` inside the managed checklist block
- if no managed checklist block exists, create it using the canonical marker format
- set `modified` => now (UTC)

## 15) Example Update (Complete Task)

User request: "Complete t-1a2b."

Expected changes:

- `status` => `done`
- `completed` => now (UTC)
- `completed_by` => `codex-agent` (or configured agent identity)
- `modified` => now (UTC)

## 16) GitHub Ship Workflow

When the user writes `ship it msg: <title>`, treat `<title>` as the GitHub PR title and ship the current task through a PR so GitHub has a persistent review/merge record.

Required workflow:

1. Run the most relevant verification for the current change and report any verification that could not be run.
2. Never ship by pushing directly to `main`.
3. Create or switch to a feature branch with the `codex/` prefix.
4. Stage only the files for the current task. If unrelated local changes would be swept in, stop and ask instead of shipping.
5. Commit the staged changes on the feature branch.
6. Push the feature branch to `origin`.
7. Create a GitHub PR against `main` using the supplied title.
8. Merge the PR on GitHub so the PR remains part of the repository history. Prefer a merge commit unless the user asks for a different merge strategy.
9. Fast-forward local `main` to the merged remote state and delete the local feature branch if it is safe to do so.

Implementation note:

- Prefer using `Tools/ship_it_pr.sh --title "<title>"` after staging the intended files.
- Provide `--body` or `--body-file` when a custom PR description is useful.
- If the user says only `ship it` without `msg:`, generate a short PR title from the work performed.
