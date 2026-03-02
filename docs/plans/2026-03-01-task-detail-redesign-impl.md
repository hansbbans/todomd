# Task Detail Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the two-mode (read-only + edit form) `TaskDetailView` with a single unified always-editable view using progressive disclosure.

**Architecture:** Remove `isEditing` state entirely. Replace `readOnlyView` and `editForm` with a single `unifiedView` — a `ScrollView` containing a header, notes area, core property rows, and a collapsible "More details" section. Auto-save on dismiss instead of an explicit Save button.

**Tech Stack:** SwiftUI, existing `TaskEditState`/`AppContainer` binding pattern (`binding(\.keyPath)`), `ThemeManager` for colors.

**Design doc:** `docs/plans/2026-03-01-task-detail-redesign.md`

---

## Background

`TaskDetailView.swift` is ~1085 lines. Key existing patterns to preserve:
- `binding<T>(_ keyPath:)` helper (line ~1070) — two-way binds `TaskEditState` fields to UI
- `container.makeEditState(path:)` — loads task into state
- `container.updateTask(path:editState:) -> Bool` — saves state to file
- `validateLocationReminder()` — returns optional error string
- `ThemeManager` injected as `@EnvironmentObject private var theme: ThemeManager`
- Recurrence sheet, location sheet, and notes full-screen cover — keep these as sheets

**What gets removed:**
- `isEditing: Bool` state
- `readOnlyView` computed property
- `editForm` computed property
- Edit/Done toolbar buttons
- Save button at bottom of form

**What gets added:**
- `expandedRow: ExpandedRow?` state — tracks which inline editor is open (due, scheduled, tags)
- `unifiedView` computed property
- Helper sub-views: `PropertyRow`, `headerSection`, `notesSection`, `corePropertiesSection`, `moreDetailsSection`
- Auto-save on `.onDisappear`

---

## Task 1: Add `ExpandedRow` enum and new state

**Files:**
- Modify: `Sources/TodoMDApp/Detail/TaskDetailView.swift`

**Step 1: Add the enum above `TaskDetailView`**

After the existing `RecurrenceFrequencyOption` enum (around line 24), add:

```swift
private enum ExpandedRow: Equatable {
    case due
    case scheduled
    case tags
    case estimate
    case assignee
    case blockedBy
}
```

**Step 2: Add new state property inside `TaskDetailView`**

After the existing `@State private var showingCustomRepeatEditor` (around line 46), add:

```swift
@State private var expandedRow: ExpandedRow?
```

**Step 3: Build and verify no errors**

Build target in Xcode or: `xcodebuild -scheme TodoMD build 2>&1 | tail -20`

Expected: build succeeds

**Step 4: Commit**

```bash
git add Sources/TodoMDApp/Detail/TaskDetailView.swift
git commit -m "feat: add ExpandedRow enum for unified task detail view"
```

---

## Task 2: Add `autoSave()` and wire `.onDisappear`

**Files:**
- Modify: `Sources/TodoMDApp/Detail/TaskDetailView.swift`

**Step 1: Add `autoSave()` private method**

Add near the existing `save()` method (around line 959):

```swift
private func autoSave() {
    guard let editState else { return }
    if let locationError = validateLocationReminder(editState) {
        errorMessage = locationError
        return
    }
    container.updateTask(path: path, editState: editState)
}
```

**Step 2: Add `.onDisappear` modifier**

In the `body`, find the `.onAppear { ... }` modifier and add after it:

```swift
.onDisappear {
    autoSave()
}
```

**Step 3: Build and verify**

`xcodebuild -scheme TodoMD build 2>&1 | tail -20`

Expected: build succeeds

**Step 4: Commit**

```bash
git add Sources/TodoMDApp/Detail/TaskDetailView.swift
git commit -m "feat: add autoSave on dismiss for unified task detail view"
```

---

## Task 3: Build the `headerSection`

**Files:**
- Modify: `Sources/TodoMDApp/Detail/TaskDetailView.swift`

**Step 1: Add `headerSection` computed property**

Add after the existing `body` (around line 155):

```swift
private var headerSection: some View {
    HStack(alignment: .top, spacing: 12) {
        // Completion circle
        Button {
            guard var s = editState else { return }
            s.status = s.status == .done ? .todo : .done
            editState = s
        } label: {
            Image(systemName: editState?.status == .done ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(editState?.status == .done ? theme.accentColor : theme.textSecondaryColor)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)

        VStack(alignment: .leading, spacing: 4) {
            TextField("Title", text: binding(\.title), axis: .vertical)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .foregroundStyle(theme.textPrimaryColor)

            if let ref = editState?.ref, !ref.isEmpty {
                Text(ref)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondaryColor)
            }
        }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
}
```

**Step 2: Build and verify**

`xcodebuild -scheme TodoMD build 2>&1 | tail -20`

Expected: build succeeds

**Step 3: Commit**

```bash
git add Sources/TodoMDApp/Detail/TaskDetailView.swift
git commit -m "feat: add headerSection for unified task detail view"
```

---

## Task 4: Build the `notesSection`

**Files:**
- Modify: `Sources/TodoMDApp/Detail/TaskDetailView.swift`

**Step 1: Add `notesSection` computed property**

```swift
private var notesSection: some View {
    ZStack(alignment: .topLeading) {
        if editState?.body.isEmpty ?? true {
            Text("Add notes...")
                .font(.body)
                .foregroundStyle(theme.textSecondaryColor)
                .padding(.top, 8)
                .padding(.leading, 4)
                .allowsHitTesting(false)
        }
        TextEditor(text: binding(\.body))
            .font(.body)
            .foregroundStyle(theme.textPrimaryColor)
            .frame(minHeight: 72)
            .scrollContentBackground(.hidden)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
}
```

**Step 2: Build and verify**

`xcodebuild -scheme TodoMD build 2>&1 | tail -20`

**Step 3: Commit**

```bash
git add Sources/TodoMDApp/Detail/TaskDetailView.swift
git commit -m "feat: add notesSection for unified task detail view"
```

---

## Task 5: Build the reusable `PropertyRow` view

**Files:**
- Modify: `Sources/TodoMDApp/Detail/TaskDetailView.swift`

**Step 1: Add `PropertyRow` private struct below `TaskDetailView`**

Add near the bottom of the file (before any `#Preview`):

```swift
private struct PropertyRow<Content: View>: View {
    let icon: String
    let label: String
    let valueText: String
    let isExpanded: Bool
    let onTap: () -> Void
    @ViewBuilder let expandedContent: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .frame(width: 20)
                        .foregroundStyle(.secondary)
                    Text(label)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(valueText.isEmpty ? "—" : valueText)
                        .foregroundStyle(valueText.isEmpty ? .tertiary : .secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if isExpanded {
                expandedContent()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }

            Divider()
                .padding(.leading, 52)
        }
    }
}
```

**Step 2: Build and verify**

`xcodebuild -scheme TodoMD build 2>&1 | tail -20`

**Step 3: Commit**

```bash
git add Sources/TodoMDApp/Detail/TaskDetailView.swift
git commit -m "feat: add reusable PropertyRow for unified task detail view"
```

---

## Task 6: Build `corePropertiesSection` — Status, Priority, Flag

**Files:**
- Modify: `Sources/TodoMDApp/Detail/TaskDetailView.swift`

**Step 1: Add status cycling helper**

```swift
private func cycleStatus() {
    guard var s = editState else { return }
    let order: [TaskStatus] = [.todo, .doing, .done, .cancelled]
    let current = order.firstIndex(of: s.status) ?? 0
    s.status = order[(current + 1) % order.count]
    editState = s
}

private func cyclePriority() {
    guard var s = editState else { return }
    let order: [TaskPriority] = [.none, .low, .medium, .high]
    let current = order.firstIndex(of: s.priority) ?? 0
    s.priority = order[(current + 1) % order.count]
    editState = s
}
```

**Step 2: Add `corePropertiesSection` — start with Status, Priority, Flag rows**

```swift
private var corePropertiesSection: some View {
    VStack(spacing: 0) {
        // Status
        Button(action: cycleStatus) {
            HStack(spacing: 12) {
                Image(systemName: "circle.badge.checkmark")
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                Text("Status")
                    .foregroundStyle(.primary)
                Spacer()
                Text(editState?.status.rawValue.capitalized ?? "—")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        Divider().padding(.leading, 52)

        // Priority
        Button(action: cyclePriority) {
            HStack(spacing: 12) {
                Image(systemName: "flag")
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                Text("Priority")
                    .foregroundStyle(.primary)
                Spacer()
                Text(editState?.priority == .none ? "—" : (editState?.priority.rawValue.capitalized ?? "—"))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        Divider().padding(.leading, 52)

        // Flag
        Button {
            guard var s = editState else { return }
            s.flagged.toggle()
            editState = s
        } label: {
            HStack(spacing: 12) {
                Image(systemName: editState?.flagged == true ? "star.fill" : "star")
                    .frame(width: 20)
                    .foregroundStyle(editState?.flagged == true ? .yellow : .secondary)
                Text("Flagged")
                    .foregroundStyle(.primary)
                Spacer()
                Text(editState?.flagged == true ? "Yes" : "—")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        Divider().padding(.leading, 52)
    }
}
```

**Step 3: Build and verify**

`xcodebuild -scheme TodoMD build 2>&1 | tail -20`

**Step 4: Commit**

```bash
git add Sources/TodoMDApp/Detail/TaskDetailView.swift
git commit -m "feat: add status/priority/flag rows to corePropertiesSection"
```

---

## Task 7: Extend `corePropertiesSection` — Due and Scheduled (inline DatePicker)

**Files:**
- Modify: `Sources/TodoMDApp/Detail/TaskDetailView.swift`

**Step 1: Add due date value text helper**

```swift
private func dueDateText(_ editState: TaskEditState) -> String {
    guard editState.hasDue else { return "" }
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = editState.hasDueTime ? .short : .none
    return formatter.string(from: editState.dueDate)
}

private func scheduledDateText(_ editState: TaskEditState) -> String {
    guard editState.hasScheduled else { return "" }
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter.string(from: editState.scheduledDate)
}
```

**Step 2: Add Due and Scheduled rows to `corePropertiesSection`**

After the Flagged row's Divider, append:

```swift
// Due
PropertyRow(
    icon: "calendar",
    label: "Due",
    valueText: editState.map { dueDateText($0) } ?? "",
    isExpanded: expandedRow == .due,
    onTap: { expandedRow = expandedRow == .due ? nil : .due }
) {
    VStack(alignment: .leading, spacing: 8) {
        Toggle("Set due date", isOn: binding(\.hasDue))
        if editState?.hasDue == true {
            DatePicker("Date", selection: binding(\.dueDate), displayedComponents: .date)
            Toggle("Include time", isOn: binding(\.hasDueTime))
            if editState?.hasDueTime == true {
                DatePicker("Time", selection: binding(\.dueTime), displayedComponents: .hourAndMinute)
            }
        }
    }
}

// Scheduled
PropertyRow(
    icon: "calendar.badge.clock",
    label: "Scheduled",
    valueText: editState.map { scheduledDateText($0) } ?? "",
    isExpanded: expandedRow == .scheduled,
    onTap: { expandedRow = expandedRow == .scheduled ? nil : .scheduled }
) {
    VStack(alignment: .leading, spacing: 8) {
        Toggle("Set scheduled date", isOn: binding(\.hasScheduled))
        if editState?.hasScheduled == true {
            DatePicker("Date", selection: binding(\.scheduledDate), displayedComponents: .date)
        }
    }
}
```

Note: `PropertyRow` requires `editState` to be non-nil here. Since the whole `corePropertiesSection` is only shown when `editState != nil`, force-unwrap with `editState!` or use `guard let` at the top of the section.

**Step 3: Build and verify**

`xcodebuild -scheme TodoMD build 2>&1 | tail -20`

**Step 4: Commit**

```bash
git add Sources/TodoMDApp/Detail/TaskDetailView.swift
git commit -m "feat: add due/scheduled inline DatePicker rows to corePropertiesSection"
```

---

## Task 8: Extend `corePropertiesSection` — Repeat and Tags

**Files:**
- Modify: `Sources/TodoMDApp/Detail/TaskDetailView.swift`

**Step 1: Add Repeat and Tags rows to `corePropertiesSection`**

After the Scheduled row, append:

```swift
// Repeat
Button {
    showingRepeatPresetMenu = true
} label: {
    HStack(spacing: 12) {
        Image(systemName: "arrow.clockwise")
            .frame(width: 20)
            .foregroundStyle(.secondary)
        Text("Repeat")
            .foregroundStyle(.primary)
        Spacer()
        Text(editState?.recurrence.isEmpty == false ? recurrenceSummaryText() : "—")
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
}
.buttonStyle(.plain)
Divider().padding(.leading, 52)

// Tags
PropertyRow(
    icon: "tag",
    label: "Tags",
    valueText: editState?.tagsText ?? "",
    isExpanded: expandedRow == .tags,
    onTap: { expandedRow = expandedRow == .tags ? nil : .tags }
) {
    VStack(alignment: .leading, spacing: 8) {
        // Existing tag chips (copy from current editForm tags section)
        let tags = editState?.tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text(tag).font(.caption)
                    Button { removeTag(tag) } label: {
                        Image(systemName: "xmark").font(.caption2)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(theme.surfaceColor)
                .clipShape(Capsule())
            }
        }
        HStack {
            TextField("Add tag", text: $newTagText)
                .onSubmit { addTag() }
            Button("Add", action: addTag)
                .disabled(newTagText.isEmpty)
        }
    }
}
```

**Step 2: Add `addTag()` and `removeTag()` helpers**

```swift
private func addTag() {
    let tag = newTagText.trimmingCharacters(in: .whitespaces)
    guard !tag.isEmpty, var s = editState else { return }
    var tags = s.tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    if !tags.contains(tag) { tags.append(tag) }
    s.tagsText = tags.joined(separator: ", ")
    editState = s
    newTagText = ""
}

private func removeTag(_ tag: String) {
    guard var s = editState else { return }
    var tags = s.tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    tags.removeAll { $0 == tag }
    s.tagsText = tags.joined(separator: ", ")
    editState = s
}
```

Note: If `FlowLayout` doesn't exist in the codebase, use `LazyVGrid` with adaptive columns instead (copy from existing tags section in `editForm`). Check with `grep -r "FlowLayout" Sources/`.

**Step 3: Build and verify**

`xcodebuild -scheme TodoMD build 2>&1 | tail -20`

**Step 4: Commit**

```bash
git add Sources/TodoMDApp/Detail/TaskDetailView.swift
git commit -m "feat: add repeat/tags rows to corePropertiesSection"
```

---

## Task 9: Build `moreDetailsSection`

**Files:**
- Modify: `Sources/TodoMDApp/Detail/TaskDetailView.swift`

**Step 1: Add `moreDetailsSection` computed property**

```swift
private var moreDetailsSection: some View {
    DisclosureGroup(
        isExpanded: $expandedMetadata,
        content: {
            VStack(spacing: 0) {
                // Assignee
                PropertyRow(
                    icon: "person",
                    label: "Assignee",
                    valueText: editState?.assignee ?? "",
                    isExpanded: expandedRow == .assignee,
                    onTap: { expandedRow = expandedRow == .assignee ? nil : .assignee }
                ) {
                    TextField("Assignee", text: binding(\.assignee))
                        .textFieldStyle(.roundedBorder)
                }

                // Blocked by
                PropertyRow(
                    icon: "link",
                    label: "Blocked by",
                    valueText: editState?.blockedByRefsText ?? "",
                    isExpanded: expandedRow == .blockedBy,
                    onTap: { expandedRow = expandedRow == .blockedBy ? nil : .blockedBy }
                ) {
                    TextField("Refs (comma-separated)", text: binding(\.blockedByRefsText))
                        .textFieldStyle(.roundedBorder)
                }

                // Project (existing picker or text field)
                Button {
                    // open project picker sheet - reuse from existing code
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "folder")
                            .frame(width: 20)
                            .foregroundStyle(.secondary)
                        Text("Project")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(editState?.project.isEmpty == false ? editState!.project : "—")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 52)

                // Estimate
                PropertyRow(
                    icon: "timer",
                    label: "Estimate",
                    valueText: editState?.hasEstimatedMinutes == true ? "\(editState!.estimatedMinutes) min" : "",
                    isExpanded: expandedRow == .estimate,
                    onTap: { expandedRow = expandedRow == .estimate ? nil : .estimate }
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Set estimate", isOn: binding(\.hasEstimatedMinutes))
                        if editState?.hasEstimatedMinutes == true {
                            Stepper("\(editState?.estimatedMinutes ?? 15) minutes",
                                    value: binding(\.estimatedMinutes),
                                    in: 5...480, step: 5)
                        }
                    }
                }

                // Location
                Button {
                    expandedLocationReminder = true
                    // The existing location sheet should be triggered here
                    // Reuse the location DisclosureGroup content wrapped in a sheet
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "location")
                            .frame(width: 20)
                            .foregroundStyle(.secondary)
                        Text("Location")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(editState?.hasLocationReminder == true ? locationSummary() : "—")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 52)

                // Read-only metadata
                if let s = editState {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle")
                            .frame(width: 20)
                            .foregroundStyle(.secondary)
                        Text("Created")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(s.createdAt, style: .date)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    Divider().padding(.leading, 52)

                    if let modified = s.modifiedAt {
                        HStack(spacing: 12) {
                            Image(systemName: "pencil.circle")
                                .frame(width: 20)
                                .foregroundStyle(.secondary)
                            Text("Updated")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(modified, style: .date)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        Divider().padding(.leading, 52)
                    }
                }
            }
        },
        label: {
            Text("More details")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.textSecondaryColor)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
    )
    .disclosureGroupStyle(PlainDisclosureGroupStyle())
}
```

Note: `PlainDisclosureGroupStyle()` may not exist — if not, use `.listRowBackground(Color.clear)` or a custom chevron approach. Check existing code for DisclosureGroup usage patterns.

**Step 2: Build and verify**

`xcodebuild -scheme TodoMD build 2>&1 | tail -20`

**Step 3: Commit**

```bash
git add Sources/TodoMDApp/Detail/TaskDetailView.swift
git commit -m "feat: add moreDetailsSection for unified task detail view"
```

---

## Task 10: Assemble `unifiedView` and wire into `body`

**Files:**
- Modify: `Sources/TodoMDApp/Detail/TaskDetailView.swift`

**Step 1: Add `unifiedView` computed property**

```swift
private var unifiedView: some View {
    ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider()
            notesSection
            Divider()
            corePropertiesSection
            moreDetailsSection
            Spacer(minLength: 40)
        }
    }
    .background(theme.backgroundColor.ignoresSafeArea())
}
```

**Step 2: Update `body` to use `unifiedView` instead of the `if isEditing` branch**

Find the existing `Group { if editState != nil { if isEditing { editForm } else { readOnlyView } } ... }` and replace with:

```swift
Group {
    if editState != nil {
        unifiedView
    } else {
        ContentUnavailableView("Task not found", systemImage: "doc.questionmark")
    }
}
```

**Step 3: Update toolbar — remove Edit/Done buttons, keep Delete**

Find the existing toolbar with Edit/Done buttons and replace with just:

```swift
.toolbar {
    ToolbarItem(placement: .destructiveAction) {
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Image(systemName: "trash")
        }
    }
}
```

**Step 4: Build and verify the app launches and the detail view renders**

`xcodebuild -scheme TodoMD build 2>&1 | tail -20`

Run in simulator, tap a task — verify the unified view appears.

**Step 5: Commit**

```bash
git add Sources/TodoMDApp/Detail/TaskDetailView.swift
git commit -m "feat: wire unifiedView into body, remove isEditing mode"
```

---

## Task 11: Remove dead code

**Files:**
- Modify: `Sources/TodoMDApp/Detail/TaskDetailView.swift`

**Step 1: Delete these now-unused items:**
- `isEditing: Bool` state declaration
- `readOnlyView` computed property (entire block)
- `editForm` computed property (entire block)
- `showNotesEditor: Bool` state (if no longer used)
- The `save()` function (replaced by `autoSave()`)
- Any `isEditing = false` or `isEditing = true` assignments

Use Xcode's "Find in File" or grep to locate:
```bash
grep -n "isEditing\|readOnlyView\|editForm\|showNotesEditor" Sources/TodoMDApp/Detail/TaskDetailView.swift
```

**Step 2: Build — fix any remaining compile errors from removed code**

`xcodebuild -scheme TodoMD build 2>&1 | tail -20`

**Step 3: Commit**

```bash
git add Sources/TodoMDApp/Detail/TaskDetailView.swift
git commit -m "refactor: remove isEditing, readOnlyView, editForm dead code"
```

---

## Task 12: Polish and test

**Step 1: Manual test checklist**
- [ ] Tap a task → unified view shows with correct data
- [ ] Edit title → tap elsewhere → dismiss → title saved
- [ ] Toggle completion circle → status cycles
- [ ] Tap Due row → DatePicker expands inline
- [ ] Tap another row → Due DatePicker collapses
- [ ] Tap Repeat → sheet opens
- [ ] Tap Tags row → chip list + add field expands
- [ ] Add and remove a tag
- [ ] Expand "More details" → Assignee, Blocked by, Location, Estimate shown
- [ ] Edit Estimate stepper → dismiss → value saved
- [ ] Tap delete → confirmation alert appears → confirms → task deleted
- [ ] Notes TextEditor → type → dismiss → notes saved

**Step 2: Fix any visual polish issues**

Common things to check:
- Spacing feels consistent (aim for 12-20pt horizontal padding, 10-14pt vertical per row)
- Dividers align to the icon width (52pt leading padding)
- Dark mode: verify `theme.backgroundColor` / `theme.textPrimaryColor` colors look right
- Placeholder text in notes shows when body is empty

**Step 3: Final commit**

```bash
git add Sources/TodoMDApp/Detail/TaskDetailView.swift
git commit -m "polish: task detail unified view spacing and dark mode"
```

---

## Notes for Implementer

- **`PropertyRow` with conditional content**: The generic `Content: View` in `PropertyRow` requires a concrete type. If you hit a "type cannot be inferred" error, use `AnyView` wrapping or `@ViewBuilder` on a helper function.
- **Location**: The existing location editor is complex (lat/lng fields, preset picker, radius stepper). For the "More details" section, the simplest approach is to open the existing location `DisclosureGroup` content in a sheet rather than rewriting it.
- **`recurrenceSummaryText()`**: This already exists in the current file — reuse it directly.
- **`locationSummary()`**: This already exists in the current file — reuse it directly.
- **Tags FlowLayout**: Check if `FlowLayout` exists with `grep -r "FlowLayout" Sources/`. If not, use the existing `LazyVGrid` from the current `editForm` tags section.
- **`expandedMetadata` AppStorage**: This state already exists and is persisted. Reuse it for the "More details" disclosure group.
