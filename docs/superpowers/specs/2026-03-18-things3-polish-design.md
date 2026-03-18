# Things 3 Polish: Progress Ring, Checkbox Animation, Empty States

Date: 2026-03-18

## Scope

Three UI polish items from the Things 3 parity list:

1. **#3** — Project progress ring in the sidebar
2. **#12** — Sequenced checkbox completion animation
3. **#20** — Empty state illustrations (SF Symbol + colored glow)

---

## 1. Project Progress Ring (#3)

### What

A small circular progress ring (18×18pt) trailing each project row in the sidebar. Shows what fraction of the project's tasks are done.

### Design decisions

- **Style B selected**: Circular arc ring, accent-colored, turns green at 100%.
- Ring is 18pt, stroke width 2pt, track color `secondarySystemFill`.
- Arc color: project's tint color (or accent if none). At 100%, color shifts to green (`systemGreen`).
- Hidden when a project has zero tasks (nothing to show).
- Replaces the current selected-state checkmark in project rows (which moves to a different affordance — or the ring itself signals selection via highlight).

### Data

Add a new public method to `AppContainer`:

```swift
func projectProgress(for project: String) -> (completed: Int, total: Int)
```

- `total` = tasks in project where `status != .cancelled` (active task universe)
- `completed` = tasks in project where `status == .done`
- Uses `allIndexedRecords` internally; must be made accessible (either expose the method or make `allIndexedRecords` internal).

### Component

New private `ProjectProgressRing` SwiftUI view (lives in `RootView.swift` alongside other private view helpers):

```
ProjectProgressRing(progress: Double, tint: Color)
```

Caller passes `progress: Double?` and only renders `ProjectProgressRing` when non-nil.

- `progress` is `Double` in [0, 1]
- Renders background track circle + foreground arc (stroke trim from 0→progress, rotated -90°)
- At `progress == 1.0`, foreground stroke is `.systemGreen`
- Accepts `Double` in [0, 1] (caller guarantees non-nil / valid range; hidden via `Optional` at the call site — see Integration)
- Hidden entirely when caller passes `nil` (total == 0 case); do not pass `NaN`

### Integration

In `navButton(view:label:icon:...)`:

1. When `view` is a `.project(name)` case, compute progress:
   ```swift
   let (completed, total) = container.projectProgress(for: projectName)
   let progress: Double? = total > 0 ? Double(completed) / Double(total) : nil
   ```
2. After the `Spacer()`, show the ring if `progress != nil`:
   ```swift
   if let progress {
       ProjectProgressRing(progress: progress, tint: tint ?? theme.accentColor)
   }
   ```
3. **Suppress the selected-state checkmark for project rows** — when the ring is shown, omit the `Image(systemName: "checkmark")` block. List row highlighting provides the selection affordance; the ring should not compete with a floating checkmark. Concretely: only show the selected checkmark when `view` is NOT a project view, or when `progress == nil` (zero-task project).

The `tint` used is the already-computed `let tint = color(forHex: tintHex)` inside `navButton`; fall back to `theme.accentColor` when nil.

---

## 2. Sequenced Checkbox Animation (#12)

### What

The `TaskCheckbox` currently animates `fillProgress` (0→1) which drives both the circle fill scale and checkmark opacity simultaneously. The new behavior sequences them:

- **Phase 1** (~280ms): Circle fills via scale spring
- **Phase 2** (~200ms, starts after phase 1): Checkmark strokes in via `trim(from:to:)` on a custom `Path`

### Design decisions

- **Style B selected**: Fill completes, then checkmark draws itself in.
- Replace `Image(systemName: "checkmark")` with a custom `Path` for the checkmark stroke so `trim` animation is possible.
- Checkmark path: `M9 15 L13 19 L21 11` hardcoded in 22×22 coordinate space. The `TaskCheckbox` frame is fixed at `.frame(width: 22, height: 22)` — this is a known constant, not a dynamic value. If the frame ever changes, the path coordinates must be updated to match.
- Add `@State private var checkmarkProgress: CGFloat` and initialize it in the existing custom `init` alongside `_fillProgress`: `_checkmarkProgress = State(initialValue: 0)`. (In Swift, `@State` default values are ignored when a custom `init` exists — the property must be explicitly set in the init body.)
- Animation sequence on `isCompleted` becoming `true`:
  1. Animate `fillProgress` 0→1 with `.spring(response: 0.28, dampingFraction: 0.75)`
  2. After 260ms delay, animate `checkmarkProgress` 0→1 with `.easeOut(duration: 0.2)`
- On `isCompleted` becoming `false` (undo): reset both `fillProgress = 0` and `checkmarkProgress = 0` immediately inside `withAnimation(nil) { }` (no transition). This replaces the existing `onChange` false-branch behavior.

### No behavior change

The outer `completeWithAnimation` in `RootView` (which handles the slide-out and timing) is unchanged. Only the visual inside `TaskCheckbox.checkboxBody` changes.

---

## 3. Empty State Illustrations (#20)

### What

Replace the generic `ContentUnavailableView("No Tasks", systemImage: "checkmark.circle")` with per-view illustrated empty states using large SF Symbols and a soft radial glow.

### Design decisions

- **Style A selected**: Large SF Symbol (~52pt) centered, with a `RadialGradient` circle behind it for a soft colored halo. No custom SVG assets needed.
- Three variants:

| View | Symbol | Glow color |
|------|--------|------------|
| Today | `star.fill` | Yellow (`systemYellow` @ 20% opacity) |
| Inbox | `tray.fill` | Blue (accent @ 18% opacity) |
| Generic (projects, tags, anytime, etc.) | `checkmark.circle` | Teal (`systemTeal` @ 15% opacity) |

- Title and subtitle text remain per-view (see below).
- Component is a private `IllustratedEmptyState` view replacing `emptyTasksUnavailableView`.

### Copy

| View | Title | Subtitle |
|------|-------|---------|
| Today | "You're all caught up" | "Enjoy the rest of your day." |
| Inbox | "Inbox is clear" | "New tasks land here first." |
| Generic | "Nothing here" | "Tap + to add a task." |

### Component

```swift
private struct IllustratedEmptyState: View {
    let symbol: String
    let glowColor: Color
    let title: String
    let subtitle: String
}
```

Renders: `ZStack` with radial gradient circle (72×72) behind a large SF Symbol image, then `VStack` with title and subtitle below.

### Integration

`IllustratedEmptyState` is a plain View struct — it does not do its own dispatch. Replace usage at the leaf level only:

- In `todayEmptyStateContent`: replace `emptyTasksUnavailableView` with `IllustratedEmptyState(symbol: "star.fill", glowColor: .yellow.opacity(0.2), title: "You're all caught up", subtitle: "Enjoy the rest of your day.")`
- In `inboxEmptyStateContent`: replace with `IllustratedEmptyState(symbol: "tray.fill", glowColor: Color.accentColor.opacity(0.18), title: "Inbox is clear", subtitle: "New tasks land here first.")`
- In `genericEmptyStateContent`: replace with `IllustratedEmptyState(symbol: "checkmark.circle", glowColor: Color.teal.opacity(0.15), title: "Nothing here", subtitle: "Tap + to add a task.")`
- Delete the `emptyTasksUnavailableView` property entirely.
- The existing dispatch logic in `emptyStateMainContent()` and the `unparseableFilesSummary` wiring in each content var are **unchanged**.

The two other `ContentUnavailableView` usages in RootView (search results and task detail not-found) are explicitly **out of scope** — they are different contexts, not task list empty states.

---

## Files Changed

| File | Change |
|------|--------|
| `Sources/TodoMDApp/App/AppContainer.swift` | Add `projectProgress(for:) -> (completed: Int, total: Int)` |
| `Sources/TodoMDApp/Features/RootView.swift` | Add `ProjectProgressRing`, update `navButton`, update `TaskCheckbox`, add `IllustratedEmptyState`, update empty state methods |

No new files needed. All changes confined to two files.

---

## Out of Scope

- Progress ring for areas (not per-spec, would need aggregate logic)
- Animating the progress ring fill (static display only)
- Custom lottie/animated illustrations for empty states
- Logbook grouping, tag pill bar (separate items)
