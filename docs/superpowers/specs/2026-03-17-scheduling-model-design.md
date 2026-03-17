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

**Validation** (in `TaskValidation`): `scheduled_time` requires `scheduled` to be set. If `scheduled` is nil and `scheduled_time` is non-nil, throw `TaskValidationError.invalidFieldValue` — matching the existing behaviour of `due_time` requiring `due` (see `TaskValidation.swift` lines 117–119).

**Serialization** (in `TaskMarkdownCodec`): written as `scheduled_time: "HH:MM"`, omitted when nil. Accepted key aliases: none.

**Recurring task advancement** (in `TaskLifecycleService`): No explicit code is needed. `scheduled_time` is implicitly preserved because `var next = document` copies all fields and `scheduledTime` is never overwritten — the same mechanism that preserves `dueTime` today.

**Unknown key preservation**: existing `unknownFrontmatter` passthrough is unaffected.

---

## Evening Start Time Setting

**Key:** `"taskBehavior.eveningStartTime"` in `UserDefaults`
**Type:** `String` in `"HH:MM"` format
**Default:** `"18:00"`

`AppContainer` exposes two properties:

```swift
// Internal storage — LocalTime
var eveningStartTime: LocalTime {
    get {
        guard let s = defaults.string(forKey: "taskBehavior.eveningStartTime"),
              let t = try? LocalTime(isoTime: s) else {
            return try! LocalTime(isoTime: "18:00")   // safe: hardcoded valid value
        }
        return t
    }
    set { defaults.set(newValue.isoString, forKey: "taskBehavior.eveningStartTime") }
}

// Bridging property for SwiftUI DatePicker (Binding<Date>)
var eveningStartDate: Date {
    get {
        var comps = DateComponents()
        comps.hour = eveningStartTime.hour
        comps.minute = eveningStartTime.minute
        return Calendar.current.date(from: comps) ?? Date()
    }
    set {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
        eveningStartTime = (try? LocalTime(isoTime: String(format: "%02d:%02d", comps.hour ?? 18, comps.minute ?? 0))) ?? (try! LocalTime(isoTime: "18:00"))
    }
}
```

`LocalTime` is the existing `ScalarTypes.LocalTime` struct. Comparison uses `(hour * 60 + minute)` — check whether `LocalTime` already implements `Comparable`; if not, add a `>=` operator or compare via `totalMinutes` in the call site.

---

## `TodayGroup` Changes

### New case

```swift
public enum TodayGroup: String, Sendable {
    case overdue               = "Overdue"
    case scheduled             = "Scheduled"
    case scheduledEvening      = "This Evening"   // NEW — placed after scheduled in enum
    case dueToday              = "Due Today"
    case deferredNowAvailable  = "Deferred-now-available"  // raw value unchanged
}
```

The enum declaration order does not control section display order (the app layer uses an explicit `groupOrder` array). The raw value `"Deferred-now-available"` is preserved exactly as-is.

### Updated `todayGroup` signature

The function gains an `eveningStart: LocalTime` parameter, passed in from `AppContainer.eveningStartTime`:

```swift
public func todayGroup(
    for record: TaskRecord,
    today: LocalDate,
    eveningStart: LocalTime
) -> TodayGroup?
```

**`isToday` and `matches` cascade:** Both `isToday` and `matches` delegate to `todayGroup` and must gain an `eveningStart` parameter. Updated signatures:

```swift
public func isToday(_ record: TaskRecord, today: LocalDate, eveningStart: LocalTime) -> Bool {
    todayGroup(for: record, today: today, eveningStart: eveningStart) != nil
}

public func matches(_ view: ViewIdentifier, record: TaskRecord, today: LocalDate, eveningStart: LocalTime) -> Bool {
    // existing switch, passing eveningStart through to isToday / todayGroup calls
}
```

All call sites of `isToday` and `matches` throughout `AppContainer` must be updated to pass `container.eveningStartTime`. Search for both function names. A default-value overload is NOT added — callers must be explicit.

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

**Time-of-day note:** The grouping is based solely on `scheduled_time` value, not the current wall-clock time. A task in "This Evening" stays there all day regardless of whether evening has started.

---

## Today View UI

### Section ordering

The app layer's explicit `groupOrder` array is updated to:

1. **Overdue**
2. **Scheduled**
3. **Due Today**
4. **Deferred**
5. **This Evening** — new, always last

Each section renders only if non-empty.

### "This Evening" section header

```swift
Label("This Evening", systemImage: "moon.stars")
    .font(.caption.weight(.semibold))
    .foregroundStyle(.secondary)
```

Style matches existing section headers (`.caption.weight(.semibold)`, `.textCase(nil)`, secondary color).

---

## Task Row Changes

### Star icon (collapsed row)

A `star.fill` / `star` icon is added as the **trailing tap target** in collapsed task rows for **active tasks only** (status `.todo` or `.inProgress`). The icon is not shown for completed or cancelled tasks.

- `star.fill` in `.systemYellow` when `scheduled == today` (regardless of `scheduled_time`)
- `star` in `.tertiaryLabel` color when not scheduled today
- Tap action:
  - If `scheduled != today`: set `scheduled = today`, clear `scheduled_time`
  - If `scheduled == today`: set `scheduled = nil`, clear `scheduled_time`
- Placed after the flag icon (if present) on the trailing edge
- Hit target: minimum 44×44pt (pad with `.contentShape` if needed)
- Accessibility label: `"Schedule for Today"` when unscheduled, `"Remove from Today"` when scheduled today

### Deadline proximity badge `◆`

Added to the metadata line (`.footnote` line below the title in collapsed rows):

- **Orange `◆`** (`diamond.fill`, `.systemOrange`) when `due` is 1–3 days away: `today < due <= today+3`
- **Red `◆`** (`diamond.fill`, `.systemRed`) when `due == today` or `due < today`
- Followed by "Deadline [formatted date]" in the same color, replacing any plain due-date text in the metadata line
- Only shown when `due` is non-nil; the `scheduled` date has no badge
- Shown in all views including the `.overdue` section (redundant but consistent)

---

## Composer Changes

The inline composer and `QuickEntrySheet` currently have a single date chip. Replace it with two independent chips:

### "When" chip

- Icon: `calendar` SF Symbol
- Label: "When" when unset; formatted date when set (e.g. "Mar 17", "Tomorrow", "Mar 17, Evening")
- "Evening" suffix shown when `scheduled_time >= eveningStartTime`
- Tapping opens a picker with shortcuts:
  - **Today** — sets `scheduled = today`, clears `scheduled_time`
  - **This Evening** — sets `scheduled = today`, sets `scheduled_time = eveningStartTime`
  - **Tomorrow** — sets `scheduled = tomorrow`, clears `scheduled_time`
  - **Date picker** — arbitrary date; after picking, show "Morning / Evening" toggle
    - **Morning** = clear `scheduled_time` (nil — task goes to regular Scheduled section)
    - **Evening** = set `scheduled_time = eveningStartTime`
- Maps to `scheduled` + `scheduled_time` frontmatter fields

### "Deadline" chip

- Icon: `diamond.fill` SF Symbol
- Label: "Deadline" when unset; date in warning color when set
- `.systemOrange` tint when set and not yet overdue; `.systemRed` when today or past
- Tapping opens a simple date picker — no time, no shortcuts
- Maps to `due` frontmatter field only — **does not affect `scheduled`**

### Natural language parsing

Existing NLP date parsing currently populates `due` (the deadline field). **This spec does not change NLP behavior** — `due` remains the NLP target. The "When" (`scheduled`) field is set only via the explicit "When" chip or the star icon. Redirecting NLP output to `scheduled` is a future consideration, out of scope here.

---

## Task Detail View Changes

In `TaskDetailView` (the full-screen editor):

- The existing "Due Date" field label is renamed **"Deadline"** — same `due` field, different label only
- A new **"When"** field is added **above** "Deadline", editing `scheduled` + `scheduled_time`
- "When" field: tapping opens the same picker as the composer (Today / This Evening / Tomorrow / date picker with Morning/Evening toggle)
- Field ordering: **When → Deadline** → Reminder → (existing fields unchanged below)

---

## Settings Changes

In `SettingsView`, add a new **Scheduling** section within Task Behavior:

```swift
Section("Scheduling") {
    DatePicker(
        "Evening starts at",
        selection: $container.eveningStartDate,   // Binding<Date> bridging property
        displayedComponents: .hourAndMinute
    )
}
```

`$container.eveningStartDate` is the `Binding<Date>` bridging property defined in `AppContainer` above. Default: 6:00 PM.

---

## Files Changed

| File | Change |
|------|--------|
| `Sources/TodoMDCore/Contracts/TaskFrontmatterV1.swift` | Add `scheduledTime: LocalTime?` field |
| `Sources/TodoMDCore/Parsing/TaskMarkdownCodec.swift` | Parse/serialize `scheduled_time` |
| `Sources/TodoMDCore/Contracts/TaskValidation.swift` | Throw on `scheduled_time` without `scheduled` |
| `Sources/TodoMDCore/Domain/TaskQueryEngine.swift` | Add `.scheduledEvening` to `TodayGroup`, update `todayGroup`, `isToday`, and `matches` signatures with `eveningStart` parameter |
| `Sources/TodoMDApp/App/AppContainer.swift` | Add `eveningStartTime: LocalTime` + `eveningStartDate: Date` with UserDefaults persistence; update `groupOrder` array to include `.scheduledEvening` at the end; update all `isToday`/`matches` call sites to pass `eveningStartTime` |
| `Sources/TodoMDApp/Features/RootView.swift` | Update `groupOrder`, add "This Evening" section header, star icon in active task rows, deadline badge in metadata line |
| `Sources/TodoMDApp/Features/QuickEntrySheet.swift` | Split date chip into "When" + "Deadline" chips |
| `Sources/TodoMDApp/Detail/TaskDetailView.swift` | Rename "Due Date" → "Deadline", add "When" field above it |
| `Sources/TodoMDApp/Settings/SettingsView.swift` | Add "Evening starts at" `DatePicker` in new Scheduling section |
| `Tests/TodoMDCoreTests/TaskQueryEngineTests.swift` | New tests for `scheduledEvening` group and `isToday` integration |
| `Tests/TodoMDCoreTests/TaskMarkdownCodecTests.swift` | New tests for `scheduled_time` parse/serialize/validation |
| `Tests/TodoMDCoreTests/TaskLifecycleServiceTests.swift` | Test that `scheduled_time` survives `completeRepeating` |

---

## Test Cases

### `TaskQueryEngineTests`

| Test | What it verifies |
|------|-----------------|
| `todayGroup_scheduledEvening_atEveningStart` | `scheduled = today`, `scheduled_time = 18:00`, `eveningStart = 18:00` → `.scheduledEvening` |
| `todayGroup_scheduledEvening_afterEveningStart` | `scheduled_time = 21:00`, `eveningStart = 18:00` → `.scheduledEvening` |
| `todayGroup_scheduledDay_beforeEveningStart` | `scheduled_time = 10:00`, `eveningStart = 18:00` → `.scheduled` |
| `todayGroup_scheduledDay_noTime` | `scheduled = today`, `scheduled_time = nil` → `.scheduled` |
| `todayGroup_eveningFuture_notInToday` | `scheduled = tomorrow`, `scheduled_time = 20:00` → `nil` (not in Today) |
| `todayGroup_overdue_takesPrecedence` | `due < today`, `scheduled = today`, `scheduled_time = 20:00` → `.overdue` |
| `isToday_includesScheduledEveningTasks` | `scheduled = today`, `scheduled_time = 20:00`, `eveningStart = 18:00` → `isToday == true` |

### `TaskMarkdownCodecTests`

| Test | What it verifies |
|------|-----------------|
| `roundtrip_scheduledTime` | `scheduled_time: "20:30"` survives encode → decode |
| `scheduledTime_nil_omittedFromOutput` | `scheduledTime = nil` → key absent in serialized YAML |

### `TaskValidationTests`

| Test | What it verifies |
|------|-----------------|
| `scheduledTime_requiresScheduled_throwsWithoutIt` | `scheduled_time` set, `scheduled = nil` → throws `TaskValidationError.invalidFieldValue` |

### `TaskLifecycleServiceTests`

| Test | What it verifies |
|------|-----------------|
| `completeRepeating_preserves_scheduledTime` | `completeRepeating` on a task with `scheduled_time = 20:00` produces a next occurrence with `scheduledTime == 20:00` |
