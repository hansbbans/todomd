# Visual Refresh Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Full visual refresh inspired by Things 3 — warmer palette, round checkboxes, inline metadata, tighter animations, cleaner toolbar and tab bar.

**Architecture:** All visual changes stay in the presentation layer. Token values live in `ThemeTokens.swift` (core) and are surfaced via `ThemeManager.swift` (app). Row layout and all task list chrome live in `RootView.swift`. No data model or business logic changes.

**Tech Stack:** SwiftUI, SF Symbols, `ThemeTokens` / `ThemeManager` design token system already in place.

**Design doc:** `docs/plans/2026-03-02-visual-refresh-design.md`

---

## Task 1: Add separator tokens to ThemeTokens

**Files:**
- Modify: `Sources/TodoMDCore/Theme/ThemeTokens.swift`

The `Colors` struct is missing separator tokens. Add them now so later tasks can use `theme.separatorColor`.

**Step 1: Add fields to `Colors` struct**

In `ThemeTokens.Colors`, after `priorityLowDark`, add:

```swift
public var separatorLight: String
public var separatorDark: String
```

**Step 2: Update `Colors.init`**

Add the two new parameters after `priorityLowDark`:

```swift
separatorLight: String,
separatorDark: String
```

And assign them in the body:

```swift
self.separatorLight = separatorLight
self.separatorDark = separatorDark
```

**Step 3: Update classic preset in `ThemeTokenStore.loadPreset`**

Replace the entire `ThemeTokens(...)` call with updated values:

```swift
return ThemeTokens(
    colors: .init(
        backgroundPrimaryLight: "#F2F2F7",
        backgroundPrimaryDark: "#1C1C1E",
        surfaceLight: "#FFFFFF",
        surfaceDark: "#2C2C2E",
        textPrimaryLight: "#1C1C1E",
        textPrimaryDark: "#F2F2F7",
        textSecondary: "#8E8E93",
        accentLight: "#4A7FD4",
        accentDark: "#5E9BF5",
        overdueLight: "#D94F3D",
        overdueDark: "#FF6B6B",
        priorityMediumLight: "#F5A623",
        priorityMediumDark: "#FFB84D",
        priorityLowLight: "#7ED321",
        priorityLowDark: "#98E44A",
        separatorLight: "#E5E5EA",
        separatorDark: "#38383A"
    ),
    spacing: .init(rowVertical: 14, rowHorizontal: 16, sectionGap: 28),
    shape: .init(cornerRadius: 12),
    motion: .init(completionSpringResponse: 0.28, completionSpringDamping: 0.78)
)
```

**Step 4: Build to verify no compile errors**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

**Step 5: Commit**

```bash
git add Sources/TodoMDCore/Theme/ThemeTokens.swift
git commit -m "feat: add separator tokens, update classic preset to Things 3 palette"
```

---

## Task 2: Add separatorColor to ThemeManager

**Files:**
- Modify: `Sources/TodoMDApp/App/ThemeManager.swift`

**Step 1: Add the computed property**

After `var overdueColor: Color { ... }`, add:

```swift
var separatorColor: Color {
    dynamic(lightHex: tokens.colors.separatorLight, darkHex: tokens.colors.separatorDark)
}
```

**Step 2: Build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

**Step 3: Commit**

```bash
git add Sources/TodoMDApp/App/ThemeManager.swift
git commit -m "feat: expose separatorColor in ThemeManager"
```

---

## Task 3: Redesign TaskRow

**Files:**
- Modify: `Sources/TodoMDApp/Features/RootView.swift` (the `TaskRow` struct at line ~1400)

`TaskRow` currently shows a 5px coloured project bar on the left, a large `size: 18 .rounded` title, and a due date on the same line. The new design replaces the bar with a tappable round checkbox and adds an inline metadata caption line below the title.

**Step 1: Add `onComplete` parameter to TaskRow**

Change the struct definition from:

```swift
private struct TaskRow: View {
    let record: TaskRecord
    let isCompleting: Bool
```

to:

```swift
private struct TaskRow: View {
    let record: TaskRecord
    let isCompleting: Bool
    let onComplete: () -> Void
```

**Step 2: Replace `body` entirely**

Replace the entire `var body: some View { ... }` block (currently lines ~1406–1444) with:

```swift
var body: some View {
    let frontmatter = record.document.frontmatter

    HStack(alignment: .top, spacing: 12) {
        Button(action: onComplete) {
            checkboxImage(frontmatter: frontmatter)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)

        VStack(alignment: .leading, spacing: 3) {
            Text(frontmatter.title)
                .font(.body)
                .foregroundStyle(isCompleting ? theme.textSecondaryColor : theme.textPrimaryColor)
                .strikethrough(isCompleting, color: theme.textSecondaryColor)
                .lineLimit(2)

            let meta = metadataLine(frontmatter: frontmatter)
            if !meta.isEmpty {
                Text(meta)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondaryColor)
                    .lineLimit(1)
            }
        }

        Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .opacity(isCompleting ? 0.86 : 1.0)
}
```

**Step 3: Add checkbox helper**

Add this private method inside `TaskRow` (after `body`):

```swift
@ViewBuilder
private func checkboxImage(frontmatter: TaskFrontmatterV1) -> some View {
    let (symbol, tint): (String, Color) = {
        if isCompleting || frontmatter.status == .done || frontmatter.status == .cancelled {
            return ("checkmark.circle.fill", theme.textSecondaryColor)
        }
        let priorityTint: Color = {
            switch frontmatter.priority {
            case .high: return theme.overdueColor
            case .medium: return theme.priorityColor(.medium)
            case .low: return theme.priorityColor(.low)
            case .none: return theme.accentColor
            }
        }()
        if frontmatter.status == .inProgress {
            return ("circle.dashed", priorityTint)
        }
        return ("circle", priorityTint)
    }()

    Image(systemName: symbol)
        .font(.system(size: 22, weight: .light))
        .foregroundStyle(tint)
        .frame(width: 28, height: 28)
}
```

**Step 4: Add metadata helper**

Add this private method inside `TaskRow`:

```swift
private func metadataLine(frontmatter: TaskFrontmatterV1) -> String {
    var parts: [String] = []
    if let dueText = dueDisplayText(for: frontmatter) {
        parts.append(dueText)
    }
    if let project = frontmatter.project?.trimmingCharacters(in: .whitespacesAndNewlines),
       !project.isEmpty {
        parts.append(project)
    }
    let tagParts = frontmatter.tags.prefix(2).map { "#\($0)" }
    parts.append(contentsOf: tagParts)
    return parts.joined(separator: "  ·  ")
}
```

**Step 5: Remove now-unused helpers from TaskRow**

Delete `projectBarColor(for:)` — it's no longer called. Keep `dueDisplayText`, `recurrenceDisplayText`, and all other helpers.

**Step 6: Build**

```bash
swift build 2>&1 | tail -5
```

You'll get a compile error because `taskRowItem` still calls `TaskRow` without `onComplete`. That's expected — fix in Task 4.

---

## Task 4: Wire TaskRow into taskRowItem

**Files:**
- Modify: `Sources/TodoMDApp/Features/RootView.swift` (the `taskRowItem` function at line ~1159)

**Step 1: Pass `onComplete` and update row modifiers**

In `taskRowItem`, find the `return TaskRow(...)` call and update it:

```swift
return TaskRow(
    record: record,
    isCompleting: isCompleting || isSlidingOut,
    onComplete: { completeWithAnimation(path: path) }
)
```

**Step 2: Update listRowBackground**

Still in `taskRowItem`, change:

```swift
.listRowBackground(Color.clear)
```

to:

```swift
.listRowBackground(theme.surfaceColor)
```

**Step 3: Update row animation spring values**

Change:

```swift
.animation(.spring(response: 0.34, dampingFraction: 0.82), value: pathsCompleting)
.animation(.spring(response: 0.35, dampingFraction: 0.86), value: pathsSlidingOut)
```

to:

```swift
.animation(.spring(response: 0.28, dampingFraction: 0.78), value: pathsCompleting)
.animation(.spring(response: 0.28, dampingFraction: 0.78), value: pathsSlidingOut)
```

**Step 4: Update completeWithAnimation spring values**

In `completeWithAnimation` (line ~1113), update both `withAnimation` calls:

```swift
// First animation (checkbox fill):
withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {

// Second animation (slide out):
withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
```

**Step 5: Build and verify**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

**Step 6: Commit**

```bash
git add Sources/TodoMDApp/Features/RootView.swift
git commit -m "feat: redesign TaskRow with round checkbox and inline metadata"
```

---

## Task 5: Style section headers

**Files:**
- Modify: `Sources/TodoMDApp/Features/RootView.swift`

List section headers are plain strings. Replace with a custom view that's uppercase, caption weight, shows count, and has generous top padding.

**Step 1: Add SectionHeaderView struct**

Add this private struct near the top of the file (after the existing private structs around line 1–30):

```swift
private struct SectionHeaderView: View {
    let title: String
    let count: Int?
    @EnvironmentObject private var theme: ThemeManager

    init(_ title: String, count: Int? = nil) {
        self.title = title
        self.count = count
    }

    var body: some View {
        HStack {
            Text(displayText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.textSecondaryColor)
                .textCase(nil)
                .tracking(0.4)
            Spacer()
        }
        .padding(.top, 16)
        .padding(.bottom, 2)
    }

    private var displayText: String {
        let upper = title.uppercased()
        if let count {
            return "\(upper)  \(count)"
        }
        return upper
    }
}
```

**Step 2: Update Today sections**

Find the `ForEach(container.todaySections())` loop (line ~471). Change:

```swift
Section(section.group.rawValue) {
    ForEach(section.records) { record in
        taskRowItem(record)
    }
}
```

to:

```swift
Section {
    ForEach(section.records) { record in
        taskRowItem(record)
    }
} header: {
    SectionHeaderView(section.group.rawValue, count: section.records.count)
}
```

**Step 3: Update Upcoming sections**

Find `Section(formattedDate(section.date))` (line ~481). Change to:

```swift
Section {
    ForEach(section.records) { record in
        taskRowItem(record)
    }
} header: {
    SectionHeaderView(formattedDate(section.date))
}
```

**Step 4: Update generic single-section views**

Find `Section(titleForCurrentView())` (line ~488). Change to:

```swift
Section {
    ForEach(records) { record in
        taskRowItem(record)
    }
    .onMove { source, destination in
        guard container.canManuallyReorderSelectedView() else { return }
        var reordered = records
        reordered.move(fromOffsets: source, toOffset: destination)
        container.saveManualOrder(filenames: reordered.map { $0.identity.filename })
    }
} header: {
    SectionHeaderView(titleForCurrentView())
}
```

**Step 5: Build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

**Step 6: Commit**

```bash
git add Sources/TodoMDApp/Features/RootView.swift
git commit -m "feat: custom section headers — uppercase caption with count"
```

---

## Task 6: Clean up toolbar

**Files:**
- Modify: `Sources/TodoMDApp/Features/RootView.swift`
- Modify: `Sources/TodoMDApp/Settings/SettingsView.swift`

The debug `ladybug` button and `EditButton` are in the top toolbar. Remove both. Reorder mode is triggered by long-press. Move debug link to Settings.

**Step 1: Remove ladybug and EditButton from toolbar**

In `detailPane`'s `.toolbar { }` block (lines ~88–119), delete these two `ToolbarItem` blocks entirely:

```swift
// DELETE THIS:
ToolbarItem(placement: .topBarLeading) {
    EditButton()
}

// DELETE THIS:
ToolbarItem(placement: .topBarLeading) {
    NavigationLink {
        DebugView()
    } label: {
        Image(systemName: "ladybug")
    }
}
```

Keep the browse grid button and the settings gear.

**Step 2: Add debug link to SettingsView**

Open `Sources/TodoMDApp/Settings/SettingsView.swift`. Find the last `Section` in the `Form` or `List` and add a debug row. Search for where other navigation links are defined (look for `NavigationLink` in the settings view). Add at the bottom of the settings list:

```swift
Section {
    NavigationLink {
        DebugView()
    } label: {
        Label("Debug", systemImage: "ladybug")
            .foregroundStyle(.secondary)
    }
}
```

**Step 3: Build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

**Step 4: Commit**

```bash
git add Sources/TodoMDApp/Features/RootView.swift Sources/TodoMDApp/Settings/SettingsView.swift
git commit -m "feat: remove debug button and EditButton from toolbar, move debug to Settings"
```

---

## Task 7: Update bottom tab bar — icons only, blur background

**Files:**
- Modify: `Sources/TodoMDApp/Features/RootView.swift` (`compactBottomNavigationBar` at line ~929)

Currently each tab item is `VStack { icon + label }`. Strip the label, increase icon size, switch background to `.ultraThinMaterial`.

**Step 1: Simplify tab items**

In `compactBottomNavigationBar`, find the `Button { applyFilter(...) } label: { VStack(...) { ... } }` block. Replace the `label` content:

```swift
// Replace:
VStack(spacing: 2) {
    Image(systemName: item.icon)
        .font(.system(size: 15, weight: .semibold))
    Text(item.title)
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
}
.frame(maxWidth: .infinity)
.padding(.vertical, 6)
.foregroundStyle(
    container.selectedView == section.view
        ? (color(forHex: item.tintHex) ?? theme.accentColor)
        : theme.textSecondaryColor
)

// With:
Image(systemName: item.icon)
    .font(.system(size: 22, weight: .regular))
    .frame(maxWidth: .infinity)
    .padding(.vertical, 10)
    .foregroundStyle(
        container.selectedView == section.view
            ? (color(forHex: item.tintHex) ?? theme.accentColor)
            : theme.textSecondaryColor
    )
```

**Step 2: Swap background and remove divider**

At the bottom of `compactBottomNavigationBar`, replace:

```swift
.background(theme.surfaceColor.opacity(0.96))
.overlay(alignment: .top) {
    Divider()
}
```

with:

```swift
.background(.ultraThinMaterial)
```

**Step 3: Build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

**Step 4: Commit**

```bash
git add Sources/TodoMDApp/Features/RootView.swift
git commit -m "feat: tab bar icons only with ultraThinMaterial background"
```

---

## Task 8: Update floating add button shadow

**Files:**
- Modify: `Sources/TodoMDApp/Features/RootView.swift` (`floatingAddButton` at line ~1012)

Minor: tune shadow to be softer and slightly smaller radius.

**Step 1: Update shadow**

In `floatingAddButton`, change:

```swift
.shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
```

to:

```swift
.shadow(color: .black.opacity(0.14), radius: 12, x: 0, y: 5)
```

**Step 2: Build**

```bash
swift build 2>&1 | tail -5
```

**Step 3: Commit**

```bash
git add Sources/TodoMDApp/Features/RootView.swift
git commit -m "polish: softer shadow on floating add button"
```

---

## Task 9: Tune view transition animations

**Files:**
- Modify: `Sources/TodoMDApp/Features/RootView.swift`

**Step 1: Update RootView body animation**

In `var body: some View`, change:

```swift
.animation(.easeInOut(duration: 0.22), value: container.selectedView)
```

to:

```swift
.animation(.easeInOut(duration: 0.18), value: container.selectedView)
```

**Step 2: Update applyFilter animation**

In `applyFilter(_:)`, change:

```swift
withAnimation(.easeInOut(duration: 0.2)) {
```

to:

```swift
withAnimation(.easeInOut(duration: 0.18)) {
```

**Step 3: Build and run**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

**Step 4: Commit**

```bash
git add Sources/TodoMDApp/Features/RootView.swift
git commit -m "polish: tighten view transition animations to 0.18s"
```

---

## Task 10: Token test smoke check

**Files:**
- Read: `Tests/TodoMDCoreTests/` (find an existing test file to add to)

No view snapshot tests exist. Add a quick sanity test that the classic preset values match the expected hex strings, so a future token edit can't silently break the palette.

**Step 1: Find an existing test file to add to**

```bash
ls Tests/TodoMDCoreTests/
```

Pick any existing test file (e.g. the one with the most general utilities).

**Step 2: Add token test**

```swift
func testClassicPresetTokenValues() {
    let tokens = ThemeTokenStore().loadPreset(.classic)
    XCTAssertEqual(tokens.colors.backgroundPrimaryLight, "#F2F2F7")
    XCTAssertEqual(tokens.colors.surfaceLight, "#FFFFFF")
    XCTAssertEqual(tokens.colors.accentLight, "#4A7FD4")
    XCTAssertEqual(tokens.colors.separatorLight, "#E5E5EA")
    XCTAssertEqual(tokens.spacing.rowVertical, 14)
    XCTAssertEqual(tokens.motion.completionSpringResponse, 0.28)
}
```

**Step 3: Run tests**

```bash
swift test 2>&1 | tail -10
```

Expected: all pass including the new test.

**Step 4: Commit**

```bash
git add Tests/
git commit -m "test: smoke check classic preset token values"
```

---

## Verification

After all tasks, build and run on a simulator:

```bash
xcodebuild -project TodoMD.xcodeproj -scheme TodoMDApp -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Check visually:
- [ ] Task list background is light gray (`#F2F2F7`), rows are white
- [ ] Round checkbox on every row, colored by priority
- [ ] Metadata (due, project, tags) appears as caption line below title
- [ ] Section headers are uppercase caption with count
- [ ] No ladybug button in toolbar
- [ ] Bottom tab bar shows icons only with blur background
- [ ] Completion animation feels snappier
- [ ] Dark mode looks correct (darker surface, correct accent)
