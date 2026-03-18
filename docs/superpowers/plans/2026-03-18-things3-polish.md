# Things 3 Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship three Things 3 parity polish items: project progress ring in the sidebar, sequenced checkbox completion animation, and per-view illustrated empty states.

**Architecture:** All changes are confined to two files — `AppContainer.swift` (one new public method) and `RootView.swift` (three new private view components + wiring into existing view functions). No new files needed; the three features are independent and can be implemented in any order.

**Tech Stack:** SwiftUI, Swift Testing (for AppContainer unit test), `@testable import TodoMDApp`

---

## File Map

| File | Role |
|------|------|
| `Sources/TodoMDApp/App/AppContainer.swift` | Add `projectProgress(for:)` public method |
| `Sources/TodoMDApp/Features/RootView.swift` | Add `ProjectProgressRing`, wire into `navButton`; update `TaskCheckbox`; add `IllustratedEmptyState`, replace `emptyTasksUnavailableView` |
| `Tests/TodoMDAppTests/AppContainerProgressTests.swift` | Unit tests for `projectProgress(for:)` |

---

## Task 1: `projectProgress(for:)` in AppContainer

**Files:**
- Modify: `Sources/TodoMDApp/App/AppContainer.swift` (add after `projectsByArea()` around line 1465)
- Create: `Tests/TodoMDAppTests/AppContainerProgressTests.swift`

### Step 1 — Write the failing test

Create `Tests/TodoMDAppTests/AppContainerProgressTests.swift`:

```swift
import Foundation
import Testing
@testable import TodoMDApp

@Suite(.serialized)
@MainActor
struct AppContainerProgressTests {
    private func makeContainer(tasks: [(title: String, project: String?, status: TaskStatus)]) throws -> AppContainer {
        let root = try makeTempDirectory()
        let repository = FileTaskRepository(rootURL: root)
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        for task in tasks {
            _ = try repository.create(
                document: .init(
                    frontmatter: TaskFrontmatterV1(
                        title: task.title,
                        status: task.status,
                        project: task.project,
                        priority: .none,
                        flagged: false,
                        tags: [],
                        created: referenceDate,
                        modified: referenceDate,
                        source: "user"
                    ),
                    body: ""
                ),
                preferredFilename: "\(task.title.replacingOccurrences(of: " ", with: "-")).md"
            )
        }
        let originalOverride = ProcessInfo.processInfo.environment["TODOMD_STORAGE_OVERRIDE_PATH"]
        setenv("TODOMD_STORAGE_OVERRIDE_PATH", root.path, 1)
        defer {
            if let o = originalOverride { setenv("TODOMD_STORAGE_OVERRIDE_PATH", o, 1) }
            else { unsetenv("TODOMD_STORAGE_OVERRIDE_PATH") }
        }
        let container = AppContainer()
        container.refresh(forceFullScan: true)
        return container
    }

    @Test("Returns 0/0 for project with no tasks")
    func emptyProject() throws {
        let container = try makeContainer(tasks: [])
        let result = container.projectProgress(for: "NonExistent")
        #expect(result.completed == 0)
        #expect(result.total == 0)
    }

    @Test("Counts only non-cancelled tasks as total")
    func totalExcludesCancelled() throws {
        let container = try makeContainer(tasks: [
            (title: "A", project: "P", status: .todo),
            (title: "B", project: "P", status: .done),
            (title: "C", project: "P", status: .cancelled),
        ])
        let result = container.projectProgress(for: "P")
        #expect(result.total == 2)   // todo + done, not cancelled
        #expect(result.completed == 1)
    }

    @Test("Counts only done tasks as completed")
    func completedCountsOnlyDone() throws {
        let container = try makeContainer(tasks: [
            (title: "A", project: "P", status: .todo),
            (title: "B", project: "P", status: .done),
            (title: "C", project: "P", status: .inProgress),
            (title: "D", project: "P", status: .someday),
        ])
        let result = container.projectProgress(for: "P")
        #expect(result.total == 4)
        #expect(result.completed == 1)
    }

    @Test("Ignores tasks from other projects")
    func ignoresOtherProjects() throws {
        let container = try makeContainer(tasks: [
            (title: "A", project: "P1", status: .done),
            (title: "B", project: "P2", status: .todo),
        ])
        let result = container.projectProgress(for: "P1")
        #expect(result.total == 1)
        #expect(result.completed == 1)
    }
}

private func makeTempDirectory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("AppContainerProgressTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
```

- [ ] **Step 2 — Run the test to verify it fails**

```bash
swift test --filter AppContainerProgressTests 2>&1 | tail -20
```

Expected: compile error — `value of type 'AppContainer' has no member 'projectProgress'`

- [ ] **Step 3 — Add `projectProgress(for:)` to AppContainer**

Open `Sources/TodoMDApp/App/AppContainer.swift`. Find `projectsByArea()` (around line 1461) and add immediately after it:

```swift
func projectProgress(for project: String) -> (completed: Int, total: Int) {
    let normalizedProject = project.trimmingCharacters(in: .whitespacesAndNewlines)
    let projectTasks = allIndexedRecords.filter {
        $0.document.frontmatter.project?.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedProject
    }
    let total = projectTasks.filter { $0.document.frontmatter.status != .cancelled }.count
    let completed = projectTasks.filter { $0.document.frontmatter.status == .done }.count
    return (completed: completed, total: total)
}
```

- [ ] **Step 4 — Run the test to verify it passes**

```bash
swift test --filter AppContainerProgressTests 2>&1 | tail -20
```

Expected: `Test run with 4 tests passed.`

- [ ] **Step 5 — Commit**

```bash
git add Sources/TodoMDApp/App/AppContainer.swift Tests/TodoMDAppTests/AppContainerProgressTests.swift
git commit -m "feat: add projectProgress(for:) to AppContainer"
```

---

## Task 2: `ProjectProgressRing` component + sidebar wiring

**Files:**
- Modify: `Sources/TodoMDApp/Features/RootView.swift`

The `navButton` function lives around line 4567. `TaskCheckbox` struct starts around line 6030. Add `ProjectProgressRing` as a new private struct near the other private view structs at the bottom of the file.

- [ ] **Step 1 — Add `ProjectProgressRing` struct**

Find the line after `private struct TaskCheckbox` closes (around line 6112) and add:

```swift
private struct ProjectProgressRing: View {
    let progress: Double  // 0.0 ... 1.0
    let tint: Color

    var body: some View {
        let isComplete = progress >= 1.0
        let arcColor = isComplete ? Color(.systemGreen) : tint
        ZStack {
            Circle()
                .stroke(Color(.secondarySystemFill), lineWidth: 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(arcColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 18, height: 18)
    }
}
```

- [ ] **Step 2 — Wire it into `navButton`**

Find `navButton` (around line 4567). Inside the `HStack` label, the current structure is:

```swift
HStack(spacing: 10) {
    AppIconGlyph(...)
    Text(label)
    Spacer()
    if isSelected {
        Image(systemName: "checkmark")
            .font(.caption.weight(.bold))
            .foregroundStyle(theme.accentColor)
    }
}
```

Replace the `Spacer()` + `if isSelected` block with:

```swift
Spacer()
// Progress ring for project views; suppress checkmark when ring is shown
if case .project(let projectName) = view {
    let (completed, total) = container.projectProgress(for: projectName)
    if total > 0 {
        let progress = Double(completed) / Double(total)
        ProjectProgressRing(progress: progress, tint: tint ?? theme.accentColor)
    }
} else if isSelected {
    Image(systemName: "checkmark")
        .font(.caption.weight(.bold))
        .foregroundStyle(theme.accentColor)
}
```

- [ ] **Step 3 — Build to confirm it compiles**

```bash
xcodebuild -scheme TodoMD -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E "error:|Build succeeded|Build FAILED"
```

Expected: `Build succeeded`

- [ ] **Step 4 — Commit**

```bash
git add Sources/TodoMDApp/Features/RootView.swift
git commit -m "feat: add project progress ring to sidebar"
```

---

## Task 3: Sequenced checkbox animation

**Files:**
- Modify: `Sources/TodoMDApp/Features/RootView.swift` — `TaskCheckbox` struct (around line 6030–6112)

The animation is purely visual — no logic tests possible. Build and manually verify.

- [ ] **Step 1 — Add `checkmarkProgress` state and update `init`**

In `TaskCheckbox`, find the `@State private var fillProgress: CGFloat` line and the `init` body. Make these changes:

**Add the new state property** (right after `fillProgress`):
```swift
@State private var checkmarkProgress: CGFloat
```

**In the `init` body**, add after `_fillProgress = State(initialValue: isCompleted ? 1 : 0)`:
```swift
_checkmarkProgress = State(initialValue: 0)
```

- [ ] **Step 2 — Replace `checkboxBody` with sequenced version**

Find `private var checkboxBody: some View` and replace the entire property:

```swift
private var checkboxBody: some View {
    ZStack {
        // Stroke ring (always visible, dashed when in-progress)
        Circle()
            .stroke(
                tint,
                style: StrokeStyle(lineWidth: 1.5, dash: isDashed && fillProgress == 0 ? [3, 2] : [])
            )
            .frame(width: 22, height: 22)

        // Filled circle — scales in during phase 1
        Circle()
            .fill(tint)
            .frame(width: 22, height: 22)
            .scaleEffect(fillProgress)
            .opacity(fillProgress)

        // Checkmark path — strokes in during phase 2
        Path { path in
            path.move(to: CGPoint(x: 9, y: 15))
            path.addLine(to: CGPoint(x: 13, y: 19))
            path.addLine(to: CGPoint(x: 21, y: 11))
        }
        .trim(from: 0, to: checkmarkProgress)
        .stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        .frame(width: 22, height: 22)
    }
    .frame(width: 22, height: 22)
}
```

- [ ] **Step 3 — Update `onChange` to sequence the two phases**

Find the `onChange(of: isCompleted)` block. Replace it entirely:

```swift
.onChange(of: isCompleted) { _, completed in
    if completed {
        // Phase 1: fill the circle
        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
            fillProgress = 1
        }
        // Phase 2: draw the checkmark after fill completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            withAnimation(.easeOut(duration: 0.2)) {
                checkmarkProgress = 1
            }
        }
    } else {
        // Undo: reset both immediately
        withAnimation(nil) {
            fillProgress = 0
            checkmarkProgress = 0
        }
    }
}
```

- [ ] **Step 4 — Build to confirm it compiles**

```bash
xcodebuild -scheme TodoMD -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E "error:|Build succeeded|Build FAILED"
```

Expected: `Build succeeded`

- [ ] **Step 5 — Manual smoke test**

Run the app in the simulator. Open any list with tasks. Tap a task checkbox. Verify:
1. The circle fills (spring, ~280ms)
2. Then the checkmark strokes in from left to right (~200ms)
3. Then the row slides out (existing behavior, unchanged)
4. Unchecking a task in the Logbook resets the checkbox instantly with no animation

- [ ] **Step 6 — Commit**

```bash
git add Sources/TodoMDApp/Features/RootView.swift
git commit -m "feat: sequence checkbox animation (fill then checkmark draw)"
```

---

## Task 4: Illustrated empty states

**Files:**
- Modify: `Sources/TodoMDApp/Features/RootView.swift` — `IllustratedEmptyState` struct + three empty state content vars (around lines 1547–1609)

- [ ] **Step 1 — Add `IllustratedEmptyState` struct**

Add as a new private struct near the bottom of the file (alongside `TaskCheckbox`, `ProjectProgressRing`):

```swift
private struct IllustratedEmptyState: View {
    let symbol: String
    let glowColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [glowColor, .clear]),
                            center: .center,
                            startRadius: 0,
                            endRadius: 36
                        )
                    )
                    .frame(width: 72, height: 72)

                Image(systemName: symbol)
                    .font(.system(size: 52, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 8)
    }
}
```

- [ ] **Step 2 — Replace `emptyTasksUnavailableView` with per-view instances**

Find the three content vars and `emptyTasksUnavailableView`. Make these targeted replacements:

**In `todayEmptyStateContent`**: replace `emptyTasksUnavailableView` with:
```swift
IllustratedEmptyState(
    symbol: "star.fill",
    glowColor: Color(.systemYellow).opacity(0.2),
    title: "You're all caught up",
    subtitle: "Enjoy the rest of your day."
)
```

**In `inboxEmptyStateContent`**: replace `emptyTasksUnavailableView` with:
```swift
IllustratedEmptyState(
    symbol: "tray.fill",
    glowColor: Color.accentColor.opacity(0.18),
    title: "Inbox is clear",
    subtitle: "New tasks land here first."
)
```

**In `genericEmptyStateContent`**: replace `emptyTasksUnavailableView` with:
```swift
IllustratedEmptyState(
    symbol: "checkmark.circle",
    glowColor: Color.teal.opacity(0.15),
    title: "Nothing here",
    subtitle: "Tap + to add a task."
)
```

**Delete `emptyTasksUnavailableView`** (the entire `private var emptyTasksUnavailableView: some View { ... }` property).

- [ ] **Step 3 — Build to confirm it compiles**

```bash
xcodebuild -scheme TodoMD -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E "error:|Build succeeded|Build FAILED"
```

Expected: `Build succeeded`

- [ ] **Step 4 — Manual smoke test**

Run the app in the simulator. Navigate to:
- **Today** with no tasks → see star + "You're all caught up"
- **Inbox** with no tasks → see tray + "Inbox is clear"
- Any **project** with no tasks → see checkmark.circle + "Nothing here"

Confirm the `unparseableFilesSummary` (if there are any unparseable files) still appears below the illustration.

- [ ] **Step 5 — Commit**

```bash
git add Sources/TodoMDApp/Features/RootView.swift
git commit -m "feat: add illustrated empty states for Today, Inbox, and generic views"
```

---

## Task 5: Full test run + wrap-up

- [ ] **Step 1 — Run all tests**

```bash
swift test 2>&1 | tail -20
```

Expected: all tests pass, no regressions.

- [ ] **Step 2 — Run a simulator build**

```bash
xcodebuild -scheme TodoMD -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E "error:|warning:|Build succeeded|Build FAILED"
```

Expected: `Build succeeded`

- [ ] **Step 3 — Final smoke test checklist**

Run the app in the simulator and verify:

| Feature | Check |
|---------|-------|
| Progress ring | Sidebar shows ring next to projects with tasks; hidden for zero-task projects; turns green at 100%; no checkmark shown when ring is present |
| Checkbox animation | Tap checkbox: fill → checkmark stroke → row slides out |
| Today empty state | `star.fill` + yellow glow + "You're all caught up" |
| Inbox empty state | `tray.fill` + blue glow + "Inbox is clear" |
| Generic empty state | `checkmark.circle` + teal glow + "Nothing here" |
| Undo completion | Tapping a completed task in Logbook resets checkbox instantly |
