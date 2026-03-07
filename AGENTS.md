# AI Agent Task Operations Guide (todo.md)

This document defines how an AI agent should create and update task files in a todo.md workspace.

## 1) Scope

- The source of truth is the filesystem.
- Each task is one Markdown file with YAML frontmatter.
- Agents MUST preserve valid existing data unless the user explicitly asks to change it.

## 2) Task file format

Each file MUST follow:

```markdown
---
<yaml frontmatter>
---
<markdown body>
```

Required frontmatter fields for valid tasks:

- `title` (non-empty string)
- `source` (non-empty string, for agent writes use a stable identifier like `codex-agent`)

Strongly recommended on create:

- `status: todo`
- `priority: none`
- `flagged: false`
- `created: <UTC ISO8601 datetime>`
- `ref: t-xxxx` (lowercase hex, 4-6 chars)

## 3) Canonical frontmatter schema

Supported keys:

- `ref` string, pattern `^t-[0-9a-f]{4,6}$`
- `title` string
- `status` enum: `todo`, `in-progress`, `done`, `cancelled`, `someday`
- `due` date `YYYY-MM-DD`
- `due_time` time `HH:MM` (24h, requires `due`)
- `persistent_reminder` boolean (requires both `due` and `due_time`)
- `defer` date `YYYY-MM-DD`
- `scheduled` date `YYYY-MM-DD`
- `priority` enum: `none`, `low`, `medium`, `high`
- `flagged` boolean
- `area` string
- `project` string
- `tags` string array (or comma-separated string, but write as array)
- `recurrence` string (RRULE)
- `estimated_minutes` integer in `[0, 100000]`
- `description` string
- `location_name` string (optional)
- `location_latitude` number in `[-90, 90]`
- `location_longitude` number in `[-180, 180]`
- `location_radius_meters` number in `[50, 1000]` (default `200`)
- `location_trigger` enum: `arrive`, `leave` (default `arrive` when location is used)
- `created` ISO8601 datetime (UTC)
- `modified` ISO8601 datetime (UTC)
- `completed` ISO8601 datetime (UTC)
- `assignee` string
- `completed_by` string
- `blocked_by` one of:
  - `true` (manually blocked)
  - string task ref (single dependency)
  - string array task refs (multiple dependencies)
- `source` string

Unknown frontmatter keys MAY exist. On updates, preserve them unless explicitly asked to remove.

## 4) Filename rules

Default filename format:

- `{YYYYMMDD}-{HHmm}-{slug}.md` in UTC for timestamp
- slug:
  - lowercase
  - replace non `[a-z0-9]` runs with `-`
  - collapse repeated `-`
  - trim leading/trailing `-`
  - truncate to 60 chars
  - fallback to `task` if empty
- If collision, append `-2`, `-3`, ...

## 5) Task identity and lookup

When the user asks to update a task:

1. Prefer explicit file path if provided.
2. Else prefer `ref` exact match.
3. Else use exact title match.
4. Else use case-insensitive contains match and ask for clarification if multiple candidates remain.

Never silently update multiple files unless user explicitly asks for bulk update.

## 6) Create task workflow

1. Build frontmatter with required fields and sensible defaults.
2. Set `created` to current UTC timestamp.
3. Generate a unique `ref` if missing.
4. Validate constraints (Section 9).
5. Generate collision-safe filename.
6. Write the file.

Minimum create template:

```markdown
---
ref: t-1a2b
title: "Example task"
status: todo
priority: none
flagged: false
created: "2026-03-02T15:40:00.000Z"
source: codex-agent
---

```

## 7) Update task workflow

1. Load and parse existing file.
2. Apply only requested field/body changes.
3. Preserve untouched known fields, unknown fields, and body content.
4. Set `modified` to current UTC timestamp for any successful update.
5. Re-validate all constraints before write.
6. Write back atomically.

Normalization rules:

- Always write canonical `status` and `priority` values.
- Keep date as `YYYY-MM-DD`, time as `HH:MM`.
- Keep `tags` as YAML string list.
- Trim whitespace-only string values to null/remove where appropriate.

## 8) Completion workflows

Standard completion:

- set `status: done`
- set `completed: <now UTC>`
- set `completed_by` (for agent actions use a stable identity, for example `codex-agent`)
- set `modified: <now UTC>`

Repeating task completion (`recurrence` exists):

1. Mark current task completed (as above).
2. Remove `recurrence` from the completed record.
3. Create a new task file as the next instance:
   - copy user-visible fields/body (title, area, project, tags, priority, notes, etc.)
   - keep original `recurrence`
   - set `status: todo`
   - set new `created` and `modified` to now
   - clear `completed` and `completed_by`
   - advance `due`, `defer`, and `scheduled` to next recurrence when present

## 9) Validation checklist (must pass before write)

- `title` not empty, max 500 chars
- `source` not empty
- `description` max 2000 chars
- body max 100000 chars
- `assignee`, `completed_by`, `ref` max 120 chars
- tags count <= 100, each tag <= 80 chars
- `blocked_by` refs count <= 50
- `due_time` only allowed when `due` is set
- `persistent_reminder: true` only allowed when both `due` and `due_time` are set
- location reminder values in valid ranges
- `estimated_minutes` in `[0, 100000]`
- `ref` matches `t-[0-9a-f]{4,6}` when present

## 10) Safe edit rules

- Do not delete files to "complete" tasks; completion is a status change.
- Do not rewrite unrelated fields when making narrow updates.
- Do not drop unknown frontmatter keys.
- Do not silently coerce invalid user intent; return a clear validation error and suggested fix.

## 11) Example update (field-only)

User request: "Set due date to 2026-03-05 and priority high for ref t-1a2b."

Expected changes:

- `due` => `2026-03-05`
- `priority` => `high`
- `modified` => now (UTC)
- all other frontmatter keys and body unchanged

## 12) Example update (complete task)

User request: "Complete t-1a2b."

Expected changes:

- `status` => `done`
- `completed` => now (UTC)
- `completed_by` => `codex-agent` (or configured agent identity)
- `modified` => now (UTC)

## 13) GitHub Ship Workflow

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

- Prefer using `Tools/ship_it_pr.sh --title "<title>"` after staging the intended files. Provide `--body` or `--body-file` when a custom PR description is useful.
- If the user says only `ship it` without `msg:`, generate a short PR title from the work performed.
