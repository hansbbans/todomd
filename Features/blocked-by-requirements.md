# Blocked-By Dependencies — Requirements for Codex

> **Feature:** Task blocking / dependency system
> **Version:** v1 (blocked status + ref-based dependencies, auto-unblock)
> **Depends on:** Task Reference IDs (`ref` field) — specified in the Assignee requirements doc
> **Touches:** Frontmatter schema, SwiftData index, task detail view, FileWatcher, notification system, perspectives/filtering, Today/Upcoming view logic

---

## Overview

A task can be **blocked** — meaning it can't be worked on yet because it depends on one or more other tasks being completed first. Blocking comes in two forms:

1. **Blocked with references:** The task specifies one or more other tasks (by `ref` ID) that must complete before it becomes available. When ALL referenced blockers are done, the task auto-unblocks.
2. **Blocked without references:** The task is simply marked as blocked with no specific dependency. The user manually unblocks it when ready. This covers situations like "waiting on an email" or "blocked by an external event" that isn't tracked as a task.

---

## Data Model

### New Frontmatter Fields

```yaml
blocked_by:
  - t-3f8a
  - t-9b2c
```

Or for an unreferenced block:

```yaml
blocked_by: true
```

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `blocked_by` | boolean, string, or string[] or null | No | `null` | Blocking dependencies. See type rules below. |

**Type rules:**

| Value | Meaning |
|---|---|
| `null` (or omitted) | Not blocked. |
| `true` | Blocked, no specific dependency. User must manually unblock. |
| `"t-3f8a"` | Blocked by a single task (string = single ref). |
| `["t-3f8a", "t-9b2c"]` | Blocked by multiple tasks (array of refs). ALL must complete to auto-unblock. |
| `false` | Explicitly not blocked (equivalent to null, but useful for agents that want to signal "I checked, this is unblocked"). |

**Why not a separate `status: blocked`?** Because blocking is orthogonal to status. A task can be `status: todo` AND blocked. A task can be `status: in-progress` AND become blocked mid-work. Overloading the status enum would break existing views and make the status field do double duty. Blocked is a modifier, not a status.

### Derived State

The app computes a `is_blocked` boolean from the `blocked_by` field for use in SwiftData queries and view filtering:

```swift
var isBlocked: Bool {
    switch blockedBy {
    case .none, .bool(false): return false
    case .bool(true): return true
    case .ref(_): return true        // Single ref — check if resolved
    case .refs(let ids): return true  // Multiple refs — check if all resolved
    }
}

var isBlockedResolved: Bool {
    // For referenced blocks: true if ALL referenced tasks have status == done
    // For unreferenced blocks: always false (must be manually cleared)
    // For unblocked: always true
}
```

---

## Blocking Behavior

### Setting a Block (User)

**From task detail view:**
1. New "Blocked By" row in the metadata section (below assignee, above tags).
2. Tapping it opens a picker with two options:
   - **"Mark as Blocked"** — sets `blocked_by: true`. No dependency, just a flag.
   - **"Blocked by Task..."** — opens a task search/picker. User selects one or more tasks. Sets `blocked_by: ["t-3f8a"]` or `blocked_by: ["t-3f8a", "t-9b2c"]`.
3. The task search in the blocker picker:
   - Shows incomplete tasks only (no point blocking on something already done).
   - Searchable by title, project, area, ref.
   - Multiple selection supported.
   - Shows the ref ID next to each task title for clarity.

**From swipe action (quick block):**
- Swipe left on a task row reveals a "Block" action (orange icon).
- Tapping it sets `blocked_by: true` (unreferenced block — fastest path).

### Setting a Block (Agent)

Agents set `blocked_by` in frontmatter when creating or modifying tasks:

```yaml
title: "Deploy to production"
status: todo
blocked_by:
  - t-3f8a    # "Run integration tests"
  - t-9b2c    # "Get QA sign-off"
```

### Removing a Block (Manual Unblock)

**For unreferenced blocks (`blocked_by: true`):**
- In task detail, tap the "Blocked" indicator → "Unblock" button.
- Sets `blocked_by: null`.

**For referenced blocks:**
- User can manually unblock even if blockers aren't done (override).
- In task detail, tap the "Blocked By" section → "Unblock Anyway" button.
- Sets `blocked_by: null`, clearing all references.
- A confirmation: "This task is still waiting on [N] incomplete tasks. Unblock anyway?"

### Auto-Unblock (Referenced Blocks)

**When a referenced blocker task is completed:**

1. FileWatcher detects the blocker's `status` changed to `done` (or `cancelled`).
2. The app queries the SwiftData index for all tasks where `blocked_by` contains the completed task's `ref`.
3. For each dependent task:
   a. Remove the completed blocker's ref from the `blocked_by` array.
   b. If `blocked_by` array is now empty → set `blocked_by: null` (fully unblocked).
   c. If `blocked_by` array still has remaining refs → task stays blocked (waiting on others).
   d. Write the updated frontmatter back to the `.md` file.
4. If a task was fully unblocked:
   a. It becomes visible in Today/Upcoming/Anytime views (per normal availability rules).
   b. If notifications are enabled for auto-unblock events (user setting), fire a local notification: "Task '[title]' is now unblocked and ready to work on."

**Cancelled blockers also unblock.** If a blocker is cancelled rather than completed, it still counts as resolved — the dependency is no longer relevant.

**Edge case — blocker re-opened:** If a completed blocker's status is changed back from `done` to `todo`:
- The app does NOT automatically re-block dependent tasks. That would be surprising and destructive.
- Instead: if the user re-opens a task that other tasks depended on, show an informational banner on the re-opened task: "Note: [N] tasks were unblocked when this task was completed."
- The user can manually re-add the dependency if needed.

### Auto-Unblock Notification Setting

**New user setting:** "Notify when blocked tasks are unblocked"
- Default: On
- Location: Settings → Notifications
- When on: fires a local notification when a task is auto-unblocked.
- When off: auto-unblock happens silently.

---

## Visibility Rules

### Blocked Tasks in Views

**Core rule:** Blocked tasks behave like deferred tasks — they are **hidden from action-oriented views** but visible in organizational views.

| View | Blocked task visible? | Notes |
|---|---|---|
| **Inbox** | Yes | Inbox shows everything unprocessed. |
| **Today** | No | Can't work on it today if it's blocked. |
| **Upcoming** | Yes, with indicator | Shows the blocking status so user can plan around it. |
| **Anytime** | No | Anytime = "available to work on now." Blocked ≠ available. |
| **Someday** | Yes, with indicator | Someday is a parking lot — blocking info is useful context. |
| **Flagged** | Yes, with indicator | If you flagged it, you want to see it even if blocked. Show blocking status. |
| **Area/Project views** | Yes, with indicator | Full view of project health, including what's stuck. |
| **Tags** | Yes, with indicator | Tag views are organizational, not action-oriented. |
| **Custom Perspectives** | Depends on rules | Filterable — see perspective integration below. |

**Blocked indicator:** A small lock icon (🔒 in SF Symbols: `lock.fill`) appears on the task row, to the left of the title. Subtle enough not to dominate the row, distinct enough to notice.

### Blocked + Deferred Interaction

**Rule: Blocked supersedes defer.**

If a task is both blocked AND deferred:
- The task is hidden per blocked rules (not shown in Today/Anytime).
- If the blocker completes before the defer date arrives, the task auto-unblocks BUT remains hidden until the defer date (defer still applies).
- The `blocked_by` field is cleared (unblocked), but the `defer` date still controls visibility.
- When the defer date arrives, the task appears normally.

In other words: unblocking doesn't bypass defer. Both conditions must be met for the task to appear in action views.

### Blocked + Due Date Interaction

**Blocked tasks with due dates are a scheduling conflict.** The user committed to a deadline but the task can't be started yet.

**Handling:**
- Blocked tasks with due dates still appear in the **Upcoming** view on their due date, with both the blocked indicator and the due date indicator.
- If a blocked task becomes **overdue**, it appears in Today with a compound indicator: blocked + overdue. This is intentionally alarming — the user needs to resolve the bottleneck.
- The blocker task(s) get a subtle badge in their own row: "Blocking [N] tasks" (tappable to see which tasks are waiting).

---

## Task Detail View

### Blocked-By Section

**Location:** Below assignee, above tags in the metadata section.

**States:**

**Not blocked (default):**
```
Blocked By    None                    [+ Add]
```

**Blocked without reference:**
```
🔒 Blocked    (no specific dependency) [Unblock]
```

**Blocked with references:**
```
🔒 Blocked by:
  ☐ Run integration tests (t-3f8a)    [→]
  ☐ Get QA sign-off (t-9b2c)          [→]
                                       [Unblock Anyway]
```

- Each referenced blocker shows: status circle (☐/✓), title, ref, and a navigation arrow.
- Tapping a blocker navigates to that task's detail view.
- Completed blockers show with a checkmark and strikethrough title.
- "Unblock Anyway" clears all blocking regardless of blocker status.

### "Blocking" Section (Reverse Dependencies)

**On a task that OTHER tasks are blocked by:**
```
Blocking:
  ☐ Deploy to production (t-7d4e)     [→]
  ☐ Send release notes (t-2a1f)       [→]
```

- This section only appears if other tasks reference this task in their `blocked_by`.
- Computed via reverse index lookup in SwiftData.
- Tapping navigates to the blocked task.
- Provides critical context: "if I complete this task, these other tasks become unblocked."

---

## Dependency Chain Validation

### Circular Dependency Detection

**The app must prevent circular dependencies.**

When the user adds a blocker reference:
1. Check if the proposed blocker is itself blocked by the current task (direct cycle).
2. Check if the proposed blocker is blocked by any task that is blocked by the current task (transitive cycle).
3. If a cycle is detected, show an error: "Can't add this dependency — it would create a circular chain: [task A] → [task B] → [task A]."
4. The dependency is not added.

**Implementation:** BFS/DFS from the proposed blocker, following `blocked_by` references. If the search reaches the current task, it's a cycle. With the constraint of multiple blockers (ALL must resolve), even a 3-deep chain scan is sufficient for v1. Cap traversal depth at 10 to prevent runaway computation.

### Orphaned References

If a `blocked_by` ref points to a task that doesn't exist (file deleted, ref typo):
- The app shows the ref as an unresolved reference: "⚠️ t-xxxx (not found)".
- The unresolved blocker does NOT count as a blocking condition — it's treated as resolved (optimistic). Rationale: if the blocker was deleted, the dependency is irrelevant.
- The user can clear the orphaned reference manually.

---

## Perspective Integration

### New Filter Rules for NL Parser

| Query | Parsed Rule |
|---|---|
| `"blocked tasks"` / `"blocked"` | `{field: "blocked_by", op: "is_not_nil"}` |
| `"unblocked tasks"` / `"not blocked"` | `{field: "blocked_by", op: "is_nil"}` |
| `"blocked by t-3f8a"` | `{field: "blocked_by", op: "contains", value: "t-3f8a"}` |
| `"tasks blocking others"` | `{field: "is_blocking", op: "equals", value: true}` (computed field) |
| `"available tasks"` (implicit) | `{operator: "AND", conditions: [{blocked_by: is_nil}, {defer: on_or_before_today}, {status: in [todo, in-progress]}]}` |

### New Perspective Filter Rules (Advanced Editor)

| Rule | Options |
|---|---|
| **Is blocked** | boolean — task has any `blocked_by` value |
| **Is blocked by specific task** | ref picker — blocked_by contains ref |
| **Is blocking other tasks** | boolean — computed reverse dependency |
| **Has unresolved blockers** | boolean — blocked_by contains refs where referenced task is not done |

---

## Frontmatter Schema Update

Adding to the existing schema:

```yaml
# --- New field ---
blocked_by: [t-3f8a, t-9b2c]        # Array of ref IDs this task depends on
# or
blocked_by: true                      # Blocked without specific dependency
# or  
blocked_by: null                      # Not blocked (default, can be omitted)
```

---

## SwiftData Schema Changes

```swift
@Model
class TaskItem {
    // ... existing fields ...
    
    // New fields
    var blockedByRefs: [String]?     // Array of ref IDs (nil = not blocked)
    var blockedByFlag: Bool          // True if blocked_by is `true` (unreferenced block)
    
    // Computed
    var isBlocked: Bool {
        blockedByFlag || (blockedByRefs != nil && !blockedByRefs!.isEmpty)
    }
    
    // Reverse dependency (populated by index maintenance)
    var blockingRefs: [String]       // Refs of tasks that this task is blocking (computed, not stored in frontmatter)
}
```

**Index additions:**
- `blockedByRefs`: indexed for containment queries
- `blockedByFlag`: indexed for boolean filter
- `blockingRefs`: maintained as a computed/cached field, updated whenever `blocked_by` fields change across any task

---

## Notification Behavior

| Event | Notification (if enabled) | Default |
|---|---|---|
| Task auto-unblocked (all blockers resolved) | "📋 '[title]' is now unblocked" | On |
| Blocked task becomes overdue | "⚠️ '[title]' is overdue but still blocked by [N] tasks" | On |
| Blocker completed | (No separate notification — covered by auto-unblock) | — |

---

## Testing Requirements

### Unit Tests

```
# blocked_by parsing
- blocked_by: null → isBlocked = false
- blocked_by: true → isBlocked = true, blockedByRefs = nil
- blocked_by: "t-3f8a" → isBlocked = true, blockedByRefs = ["t-3f8a"]
- blocked_by: ["t-3f8a", "t-9b2c"] → isBlocked = true, blockedByRefs = ["t-3f8a", "t-9b2c"]
- blocked_by: false → isBlocked = false

# Auto-unblock
- Task A blocks Task B. Complete A → B.blocked_by becomes null, B.isBlocked = false.
- Task A and C block Task B. Complete A → B.blocked_by = ["ref-c"], B.isBlocked = true.
- Task A and C block Task B. Complete both → B.blocked_by = null, B.isBlocked = false.
- Cancel A (blocker) → same unblocking behavior as completing A.
- Re-open A after B was auto-unblocked → B remains unblocked (no re-block).

# Circular dependency detection
- A blocked by B, try to add B blocked by A → error, rejected.
- A blocked by B, B blocked by C, try to add C blocked by A → error, rejected.
- A blocked by B, C blocked by D → adding D blocked by A → allowed (no cycle).

# Orphaned references
- blocked_by: ["t-xxxx"] where t-xxxx doesn't exist → treated as resolved, isBlocked = false.
- blocked_by: ["t-3f8a", "t-xxxx"] where t-xxxx doesn't exist → only t-3f8a counts.

# Visibility
- Blocked task → hidden from Today and Anytime.
- Blocked + deferred task → hidden; unblock before defer date → still hidden until defer.
- Blocked + overdue task → visible in Today with compound indicator.
- Blocked task in project view → visible with lock icon.

# Frontmatter round-trip
- Write blocked_by: ["t-3f8a"] → read back → identical.
- Write blocked_by: true → read back → identical.
```

### Integration Tests

```
- Create task A and B. Set B blocked by A. Complete A → B auto-unblocks, file updated.
- Create chain A → B → C. Complete A → B unblocks. Complete B → C unblocks.
- Agent creates task with blocked_by in frontmatter → app indexes correctly.
- NL perspective "blocked tasks" → returns only blocked tasks.
- NL perspective "available tasks" → excludes blocked tasks.
- Auto-unblock notification fires when setting is on, doesn't fire when off.
```

---

## Implementation Phases

### Phase 1: Blocked Status (No References)
- Add `blocked_by` field to schema and SwiftData model (boolean only: `true`/`null`).
- Blocked indicator (lock icon) on task rows.
- Blocked-by section in task detail view (set/unset blocked flag).
- Visibility rules: hide from Today/Anytime.
- Swipe-to-block action.
- Perspective filter rules for `is_blocked`.

### Phase 2: Referenced Dependencies
- Extend `blocked_by` to support ref IDs (single string or array).
- Blocker task picker in detail view.
- Auto-unblock engine (FileWatcher → detect blocker completion → update dependents).
- Reverse dependency display ("Blocking" section on blocker tasks).
- Circular dependency detection.
- Orphaned reference handling.

### Phase 3: Notifications & Polish
- Auto-unblock notification (configurable).
- Blocked + overdue compound indicator and notification.
- "Blocking [N] tasks" badge on blocker task rows.
- Dependency chain visualization (v2+ — optional, shows A → B → C graphically).
