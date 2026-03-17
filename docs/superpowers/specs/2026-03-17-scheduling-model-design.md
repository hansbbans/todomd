# Scheduling Model Design: This Evening, Deadline vs When, Today Star

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `scheduled_time` field to the task model to enable "This Evening" scheduling, surface the existing `due`/`scheduled` distinction clearly in the UI as "Deadline" vs "When", add a star tap target in task rows to quickly schedule for today, and show a `◆` deadline proximity badge.

**Architecture:** One new frontmatter field (`scheduled_time`), one new `TodayGroup` case (`.scheduledEvening`), a configurable evening-start time in Settings, and UI changes to the task row, composer, and task editor. No migration needed — existing tasks are unaffected.

**Tech Stack:** Swift 6, SwiftUI, `@Observable`, `UserDefaults`, Swift Testing, `TodoMDCore` (data model + query engine)

---

## Data Model

### New frontmatter field: `scheduled_time`

Added to `TaskFrontmatterV1`:

```swift
var scheduledTime: LocalTime?   // frontmatter key: "scheduled_time", format: "HH:MM"
```

**Validation** (in `TaskValidation`): `scheduled_time` requires `scheduled` to be set. If `scheduled` is nil and `scheduled_time` is non-nil, emit a validation warning and ignore `scheduled_time` (same pattern as `due_time` requires `due`).

**Serialization** (in `TaskMarkdownCodec`): written as `scheduled_time: "HH:MM"`, omitted when nil. Accepted key aliases: none (no legacy aliases needed).

**Recurring task advancement** (in `TaskLifecycleService`): `scheduled_time` is preserved unchanged when creating the next occurrence, exactly as `due_time` is today.

**Unknown key preservation**: existing `unknownFrontmatter` passthrough is unaffected.

---

## Evening Start Time Setting

**Key:** `"taskBehavior.eveningStartTime"` in `UserDefaults`
**Type:** `String` in `"HH:MM"` format
**Default:** `"18:00"`

Exposed via `AppContainer` (or a dedicated settings store) as:

```swift
var eveningStartTime: LocalTime {
    get { /* read from UserDefaults, fallback to LocalTime(hour: 18, minute: 0) */ }
    set { /* write to UserDefaults */ }
}
```

`LocalTime` is the existing `ScalarTypes.LocalTime` struct (`hour: Int, minute: Int`). Comparison is by `(hour * 60 + minute)`.

---

## `TodayGroup` Changes

### New case

```swift
public enum TodayGroup: String, Sendable {
    case overdue               = "Overdue"
    case scheduledEvening      = "This Evening"   // NEW
    case scheduled             = "Scheduled"
    case dueToday              = "Due Today"
    case deferredNowAvailable  = "Deferred"
}
```

### Updated `todayGroup(for:today:eveningStart:)` signature

The function gains an `eveningStart: LocalTime` parameter (passed in by callers from `AppContainer.eveningStartTime`):

```swift
public func todayGroup(
    for record: TaskRecord,
    today: LocalDate,
    eveningStart: LocalTime
) -> TodayGroup?
```

The existing `todayGroup(for:today:)` overload (no `eveningStart`) is removed or kept as a convenience defaulting to `LocalTime(hour: 18, minute: 0)` for backward compatibility with tests.

### Updated evaluation order

```swift
guard isActive(record), isAvailableByDefer(record, today: today), isAssignedToUser(record) else { return nil }

let f = record.document.frontmatter

// 1. Overdue (blocked tasks that are past due still surface)
if f.isBlocked {
    if let due = f.due, due < today { return .overdue }
    return nil
}
if let due = f.due, due < today { return .overdue }

// 2. Scheduled this evening (NEW — before generic .scheduled check)
if f.scheduled == today,
   let st = f.scheduledTime,
   st >= eveningStart {
    return .scheduledEvening
}

// 3. Scheduled today (unchanged)
if f.scheduled == today { return .scheduled }

// 4. Due today (unchanged)
if f.due == today { return .dueToday }

// 5. Deferred now available (unchanged)
if let d = f.defer, d <= today { return .deferredNowAvailable }

return nil
```

`isToday` delegates to `todayGroup` as before (non-nil = in Today).

---

## Today View UI

### Section ordering

Sections render in this order, each only if non-empty:

1. **Overdue** — existing red header
2. **Scheduled** — existing header
3. **Due Today** — existing header
4. **Deferred** — existing header
5. **This Evening** — new section, header uses `moon.stars` SF Symbol + "This Evening" label

### "This Evening" section header

```swift
Label("This Evening", systemImage: "moon.stars")
    .font(.caption.weight(.semibold))
    .foregroundStyle(.secondary)
```

Style matches existing section headers (same `.caption.weight(.semibold)`, `.textCase(nil)`, secondary color).

---

## Task Row Changes

### Star icon (collapsed row)

A `star.fill` / `star` icon is added as the **trailing tap target** in every collapsed task row:

- `star.fill` in `.systemYellow` when `scheduled == today` (regardless of `scheduled_time`)
- `star` in `.tertiaryLabel` / `.tertiary` when not scheduled today
- Tap action:
  - If `scheduled != today`: set `scheduled = today`, clear `scheduled_time`
  - If `scheduled == today`: set `scheduled = nil`, clear `scheduled_time`
- The icon is placed after the flag icon (if flagged) on the trailing edge
- Hit target: minimum 44×44pt (use `.contentShape` padding if needed)
- Accessibility label: "Schedule for Today" / "Remove from Today"

### Deadline proximity badge `◆`

Added to the metadata line (the `.footnote` line below the title in collapsed rows):

- **Yellow `◆`** when `due` is 1, 2, or 3 days from today (inclusive): `today < due <= today+3`
- **Red `◆`** when `due == today` or `due < today` (today or overdue)
- Rendered as `Image(systemName: "diamond.fill")` or the Unicode `◆` character in a `Text`, colored `.systemOrange` (yellow) or `.systemRed`
- Followed by "Deadline [date]" in the same color, replacing the plain date text when `due` is set
- Only shown when `due` is non-nil; `.scheduled` date has no badge
- If the task is already in the `.overdue` TodayGroup section, the red badge is still shown in the row for clarity

---

## Composer Changes

The inline composer and `QuickEntrySheet` currently have a single date chip. This is split into two chips:

### "When" chip

- Icon: `calendar` SF Symbol
- Label: "When" when unset; formatted date when set (e.g. "Mar 17", "Tomorrow", "Mar 17, Evening")
- "Evening" suffix shown when `scheduled_time >= eveningStartTime`
- Tapping opens a `When` picker sheet with shortcuts:
  - **Today** — sets `scheduled = today`, clears `scheduled_time`
  - **This Evening** — sets `scheduled = today`, sets `scheduled_time = eveningStartTime`
  - **Tomorrow** — sets `scheduled = tomorrow`, clears `scheduled_time`
  - **Date picker** — arbitrary date; after picking, offer "Morning" / "Evening" toggle
- Maps to `scheduled` + `scheduled_time` frontmatter fields

### "Deadline" chip

- Icon: `diamond.fill` SF Symbol (matches the badge)
- Label: "Deadline" when unset; date in warning color when set
- Styled with `.systemOrange` tint when set (not yet overdue) or `.systemRed` (overdue/today)
- Tapping opens a simple date picker — no time component, no shortcuts
- Maps to `due` frontmatter field
- **Does not affect `scheduled`** — the two chips are fully independent

### Natural language parsing

Existing NLP date parsing (triggered by typing dates in the title) continues to populate `scheduled` (the "When" field). It does not populate `due`. This is unchanged behavior.

---

## Task Detail View Changes

In `TaskDetailView` (the full-screen editor):

- The existing "Due Date" field is renamed **"Deadline"** — same data (`due`), different label
- A new **"When"** field is added above "Deadline", editing `scheduled` + `scheduled_time`
- "When" field shows a time component picker when a date is selected (same "Morning" / "Evening" shortcuts as composer, plus a time picker)
- Field ordering: When → Deadline → Reminder (existing fields below are unchanged)

---

## Settings Changes

In `SettingsView`, within the existing **Task Behavior** section, add:

```swift
Section("Scheduling") {
    DatePicker(
        "Evening starts at",
        selection: $container.eveningStartTime,
        displayedComponents: .hourAndMinute
    )
}
```

`$container.eveningStartTime` is a `Binding<Date>` that bridges to the `LocalTime` stored value (converting `Date` → `LocalTime` via calendar components and back). Default: 6:00 PM.

---

## Files Changed

| File | Change |
|------|--------|
| `Sources/TodoMDCore/Contracts/TaskFrontmatterV1.swift` | Add `scheduledTime: LocalTime?` field |
| `Sources/TodoMDCore/Parsing/TaskMarkdownCodec.swift` | Parse/serialize `scheduled_time` |
| `Sources/TodoMDCore/Contracts/TaskValidation.swift` | Validate `scheduled_time` requires `scheduled` |
| `Sources/TodoMDCore/Domain/TaskQueryEngine.swift` | Add `.scheduledEvening` to `TodayGroup`, update `todayGroup` logic |
| `Sources/TodoMDCore/Domain/TaskLifecycleService.swift` | Preserve `scheduled_time` on recurring advancement |
| `Sources/TodoMDApp/App/AppContainer.swift` | Add `eveningStartTime: LocalTime` property with UserDefaults persistence |
| `Sources/TodoMDApp/Features/RootView.swift` | Today view section ordering, "This Evening" header, star icon in task rows, deadline badge in metadata line, update `todayGroup` call sites to pass `eveningStart` |
| `Sources/TodoMDApp/Features/QuickEntrySheet.swift` | Split date chip into "When" + "Deadline" chips |
| `Sources/TodoMDApp/Detail/TaskDetailView.swift` | Rename "Due Date" → "Deadline", add "When" field with time picker |
| `Sources/TodoMDApp/Settings/SettingsView.swift` | Add "Evening starts at" time picker |
| `Tests/TodoMDCoreTests/TaskQueryEngineTests.swift` | Tests for `scheduledEvening` group |
| `Tests/TodoMDCoreTests/TaskMarkdownCodecTests.swift` | Tests for `scheduled_time` parse/serialize |

---

## Test Cases

### `TaskQueryEngineTests`

| Test | What it verifies |
|------|-----------------|
| `todayGroup_scheduledEvening_atEveningStart` | `scheduled = today`, `scheduled_time = 18:00`, `eveningStart = 18:00` → `.scheduledEvening` |
| `todayGroup_scheduledEvening_afterEveningStart` | `scheduled_time = 21:00` → `.scheduledEvening` |
| `todayGroup_scheduledDay_beforeEveningStart` | `scheduled_time = 10:00` → `.scheduled` |
| `todayGroup_scheduledDay_noTime` | `scheduled_time = nil` → `.scheduled` |
| `todayGroup_eveningFuture_notInToday` | `scheduled = tomorrow`, `scheduled_time = 20:00` → `nil` (not in Today) |
| `todayGroup_overdue_takesPrecdence` | `due < today`, `scheduled = today`, `scheduled_time = 20:00` → `.overdue` |

### `TaskMarkdownCodecTests`

| Test | What it verifies |
|------|-----------------|
| `roundtrip_scheduledTime` | `scheduled_time: "20:30"` survives encode → decode |
| `scheduledTime_requiresScheduled_validation` | `scheduled_time` without `scheduled` → validation warning, field ignored |
| `scheduledTime_nil_omittedFromOutput` | `scheduledTime = nil` → key absent in serialized YAML |
| `scheduledTime_preserved_onRecurringAdvance` | Recurring advancement copies `scheduled_time` to next occurrence |
