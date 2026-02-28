# Assignee & Completion Tracking — Requirements for Codex

> **Feature:** Task assignment (primarily for agents) + completion attribution
> **Version:** v1 (single assignee, free-text identity) → v2 (agent registry)
> **Depends on:** New `ref` field (Task Reference IDs) — specified in this doc
> **Touches:** Frontmatter schema, SwiftData index, task detail view, perspectives/filtering, notification system, agent contract

---

## Prerequisite: Task Reference IDs

### Overview

Before assignees or blocked-by can work reliably, tasks need a stable, short, human-readable identifier that survives file renames and is easy to reference from other tasks or tools.

### Frontmatter Addition

```yaml
ref: t-3f8a
```

**Format:** `t-` prefix + 4 lowercase hex characters (e.g., `t-3f8a`, `t-00b1`, `t-ffcd`).

**Properties:**
- Auto-generated at task creation. Never changes after creation.
- Unique within the user's `todo.md/` folder. The app checks the SwiftData index for collisions at generation time and regenerates if a collision occurs.
- 65,536 possible values with 4 hex chars. At 5,000 tasks (including completed), collision probability is ~17% per generation attempt — still resolves in 1–2 attempts. If the active task count exceeds 10,000, auto-upgrade to 6 hex chars (`t-3f8a1b`) for new tasks. Existing refs are never changed.
- The `ref` field is **required** for all new tasks going forward. Tasks created before this feature ship won't have a `ref`. The app backfills refs for existing tasks on first launch after update (batch operation, writes to each file).
- External tools creating tasks SHOULD include a `ref`. If omitted, the app assigns one on first index.

### Index & Lookup

- SwiftData `TaskItem` model adds a `ref: String` field, indexed and unique.
- `TaskRefResolver` utility: given a ref string, returns the `TaskItem` (or nil + error).
- URL scheme: `todomd://task/t-3f8a` opens the task detail view.
- Markdown body linking (v2): `[[t-3f8a]]` renders as a tappable link to the referenced task.

---

## Part 1: Assignee

### 1.1 Data Model

**New frontmatter fields:**

```yaml
assignee: claude-agent
```

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `assignee` | string or null | No | `null` | The agent or person currently responsible for this task. Free-text string in v1. |

**Conventions (not enforced in v1, enforced by registry in v2):**
- `"user"` — the human user (Hans). This is the implicit assignee when the field is null.
- `"claude-agent"` — Claude via any integration (Shortcuts, file drop, etc.)
- `"codex"` — Codex / Claude Code
- `"shortcut"` — Apple Shortcuts automation
- Custom strings for any other agent or tool.

**Null semantics:** `assignee: null` (or field omitted) means the task is assigned to the user. This preserves backward compatibility — every existing task is implicitly the user's.

### 1.2 Assignment Behavior

**User assigns a task to an agent:**
- In task detail view, tap the "Assignee" field.
- Picker shows: recently-used assignee strings + text input for new ones.
- Selecting an assignee writes the field to the `.md` file.

**Agent self-assigns:**
- An agent creating a task can set `assignee` to itself in the frontmatter.
- An agent can update the `assignee` field on an existing task by modifying the file.
- Agents SHOULD NOT overwrite an `assignee` that is already set to a different agent without explicit instruction. (This is a convention, not enforced in v1. The v2 registry can enforce permissions.)

**Reassignment flow (agent completes subtask, parent stays open):**
- Agent completes its work and updates the task:
  - Sets `assignee: user` (handing back to Hans).
  - Optionally appends a note in the body: `## Agent Notes\nCompleted the data pull. Results attached.`
  - Does NOT change `status` — the task remains `in-progress` or `todo`.
- The user sees the task reappear in their views (previously filtered to `assignee: user` or unassigned).

### 1.3 Views & Filtering

**Sidebar addition:**
- New built-in view: **"My Tasks"** — shows tasks where `assignee` is null or `"user"`. This becomes the default working view.
- New built-in view: **"Delegated"** — shows tasks where `assignee` is not null and not `"user"`. Grouped by assignee.

**Perspective integration:**
- New filter rules for the NL perspective parser:
  - `"assigned to claude-agent"` → `{field: "assignee", op: "equals", value: "claude-agent"}`
  - `"my tasks"` / `"assigned to me"` → `{field: "assignee", op: "in", value: [null, "user"]}`
  - `"delegated"` / `"assigned to agents"` → `{operator: "AND", conditions: [{field: "assignee", op: "is_not_nil"}, {field: "assignee", op: "not_equals", value: "user"}]}`
  - `"unassigned"` → `{field: "assignee", op: "is_nil"}`

**Today view modification:**
- Today view defaults to showing only the user's tasks (`assignee` is null or `"user"`).
- A toggle/filter chip at the top: "My Tasks | All" lets the user see delegated tasks due today too.

### 1.4 Task Detail View

**Assignee row in detail view:**
- Shows below `source` in the metadata section.
- Displays: assignee icon (person icon for user, robot icon for agents) + assignee name.
- Tappable to reassign.

### 1.5 Agent Contract Update

Update the agent file-drop contract (from the main spec) to include:

```yaml
# Required fields (unchanged)
title: "Pull Q3 revenue data"
status: todo
created: 2026-02-27T14:30:00Z
source: claude-agent

# New assignee fields
assignee: claude-agent        # Agent assigns to itself
```

Agents can also create tasks assigned to the user:
```yaml
assignee: user                # Or simply omit the field
```

---

## Part 2: Completion Tracking

### 2.1 Data Model

**New frontmatter fields:**

```yaml
completed_by: claude-agent
completed_at: 2026-02-27T16:45:00Z
```

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `completed_by` | string or null | No | `null` | Who completed this task. Set automatically when status changes to `done` or `cancelled`. |
| `completed_at` | datetime or null | No | `null` | When the task was completed. (Note: this field already exists as `completed` in the current spec. Rename to `completed_at` for clarity, or keep both — see migration note.) |

**Migration note:** The current spec has a `completed` datetime field. Two options:
- **Option A:** Rename `completed` → `completed_at` globally. Cleaner, but requires migration.
- **Option B:** Keep `completed` as-is, add `completed_by` alongside it. No migration, slightly inconsistent naming.

**Recommendation:** Option B for v1 (no migration risk). Standardize naming in a future schema version.

### 2.2 Auto-Population Behavior

**When the user completes a task (taps checkbox):**
```yaml
status: done
completed: 2026-02-27T16:45:00Z
completed_by: user
```

**When an agent completes a task (modifies the file):**
```yaml
status: done
completed: 2026-02-27T16:45:00Z
completed_by: claude-agent    # Should match the agent's source/assignee identity
```

**When a task is cancelled:**
```yaml
status: cancelled
completed: 2026-02-27T16:45:00Z
completed_by: user            # Whoever cancelled it
```

**When a task is re-opened (status changed back from done/cancelled):**
```yaml
completed_by: null            # Cleared
completed: null               # Cleared
```

### 2.3 Inference Rules

If a task's status changes to `done` and the app detects it:
- **Changed via the app UI:** `completed_by: user`
- **Changed via external file modification:** `completed_by` = value of `assignee` field if set, otherwise value of `source` field. If neither is set, `completed_by: unknown`.
- **Agent contract:** Agents completing tasks SHOULD set `completed_by` themselves. If they don't, the app infers from `assignee` or `source`.

### 2.4 Views & Filtering

**Completed view enhancement:**
- Completed tasks now show a "Completed by" badge: small icon (person/robot) + name.
- Grouping option in Completed view: "Group by completer" (user vs. agents).

**Perspective integration:**
- New filter rules for NL parser:
  - `"completed by claude-agent"` → `{field: "completed_by", op: "equals", value: "claude-agent"}`
  - `"completed by me"` → `{field: "completed_by", op: "equals", value: "user"}`
  - `"completed by agents"` → `{operator: "AND", conditions: [{field: "completed_by", op: "is_not_nil"}, {field: "completed_by", op: "not_equals", value: "user"}]}`

### 2.5 Task Detail View

**Completion metadata in detail view:**
- When a task is done, the detail view shows:
  - "Completed by [icon] [name] on [date]" in the metadata section.
- When a task is active, these fields are hidden.

---

## Part 3: Agent Registry (v2)

### 3.1 Overview

In v2, replace free-text assignee strings with a lightweight registry that enables permissions and status tracking.

### 3.2 Data Model

**File:** `todo.md/.agents.json`

```json
{
  "version": 1,
  "agents": {
    "claude-agent": {
      "name": "Claude Agent",
      "icon": "cpu",
      "permissions": {
        "create": true,
        "modify_own": true,
        "modify_any": false,
        "complete": true,
        "delete": false,
        "reassign": true
      },
      "last_seen": "2026-02-27T14:30:00Z"
    },
    "codex": {
      "name": "Codex",
      "icon": "terminal",
      "permissions": {
        "create": true,
        "modify_own": true,
        "modify_any": true,
        "complete": true,
        "delete": false,
        "reassign": true
      },
      "last_seen": "2026-02-27T10:00:00Z"
    }
  }
}
```

### 3.3 Permission Enforcement

- `create`: Can create new tasks.
- `modify_own`: Can modify tasks where `assignee` matches this agent.
- `modify_any`: Can modify any task regardless of assignee.
- `complete`: Can mark tasks as done.
- `delete`: Can delete task files. (Default false — agents shouldn't delete.)
- `reassign`: Can change the `assignee` field on tasks.

**Enforcement:** When the FileWatcher detects a change to a task file, it checks the `source` of the modification (via `modified` timestamp correlation + `assignee` field changes) against the registry permissions. Violations are logged to `.audit.json` and optionally surfaced to the user as a notification.

### 3.4 Assignee Picker Enhancement

With the registry, the assignee picker shows:
- Registered agents with their icons and names.
- Permission summary (what this agent can do).
- "Last seen" timestamp.
- Option to add a new agent (creates a registry entry).

---

## SwiftData Schema Changes

```swift
@Model
class TaskItem {
    // ... existing fields ...
    
    // New fields
    var ref: String              // Unique task reference ID, indexed
    var assignee: String?        // Agent/user assigned to this task
    var completedBy: String?     // Who completed this task
    
    // Existing field (unchanged)
    var completed: Date?         // When the task was completed
}
```

**Index additions:**
- `ref`: unique index
- `assignee`: standard index (for filtering by assignee)
- `completedBy`: standard index (for filtering completed-by)

---

## Frontmatter Schema Update (Cumulative)

Adding to the existing schema from the main spec:

```yaml
# --- New fields ---
ref: t-3f8a                          # Task reference ID (auto-generated, immutable)
assignee: claude-agent               # Who is responsible (null = user)
completed_by: user                   # Who completed it (set on completion)
```

---

## Testing Requirements

### Unit Tests

```
# Ref generation
- Generate ref → format is t-[4 hex chars]
- Generate 1000 refs → no collisions
- Ref persists across file read/write round-trip

# Assignee
- Create task with assignee → field written to frontmatter
- Create task without assignee → assignee is null in index
- Filter "assignee == claude-agent" → returns only matching tasks
- Filter "assignee is null" → returns unassigned tasks
- Reassign task → old assignee cleared, new assignee written

# Completion tracking
- Complete task via UI → completed_by = "user", completed = now
- Complete task via external edit with assignee set → completed_by = assignee
- Re-open task → completed_by and completed cleared
- Cancel task → completed_by set to canceller

# Backfill
- Launch with 100 existing tasks without ref → all get refs assigned
- No duplicate refs after backfill
- Backfill is idempotent (running twice doesn't change refs)
```

### Integration Tests

```
- Agent drops file with assignee → appears in Delegated view
- Agent completes task → completed_by reflects agent name
- Agent reassigns to user → task appears in My Tasks view
- Filter perspective "assigned to claude-agent" → correct results
- Ref-based lookup via URL scheme → opens correct task
```

---

## Implementation Phases

### Phase 1: Ref IDs
- Add `ref` field to schema and SwiftData model.
- Auto-generate on task creation.
- Backfill existing tasks on first launch.
- Add `TaskRefResolver` utility.
- URL scheme: `todomd://task/{ref}`.

### Phase 2: Assignee (v1 — free-text)
- Add `assignee` field to schema and SwiftData model.
- Assignee picker in task detail view.
- My Tasks / Delegated built-in views.
- Today view filter toggle.
- Update agent contract docs.
- Perspective parser rules for assignee filtering.

### Phase 3: Completion Tracking
- Add `completed_by` field to schema and SwiftData model.
- Auto-populate on status change (UI and external).
- Inference logic for external completions.
- Completed view enhancement (completed-by badge, grouping).
- Perspective parser rules for completed-by filtering.

### Phase 4: Agent Registry (v2)
- `.agents.json` schema and FileWatcher.
- Permission model and enforcement.
- Enhanced assignee picker with registry data.
- Audit logging for permission violations.
