# Task Detail View Redesign

**Date:** 2026-03-01
**Status:** Approved
**Style:** Things 3-inspired, progressive disclosure (Option B)

## Goal

Replace the current two-mode (read-only + edit form) `TaskDetailView` with a single unified `ScrollView` that is always editable. Eliminate the `isEditing` state and the "Edit"/"Done" toolbar buttons.

## Overall Structure

Single `ScrollView` with four zones top to bottom:

1. Header (title + completion toggle)
2. Notes (always visible text area)
3. Core properties (always visible tappable rows)
4. More details (collapsed disclosure for advanced fields)

---

## Zone 1: Header

- **Completion circle** (left): tappable button, toggles done/not-done. Outlined when incomplete, filled checkmark when complete.
- **Title**: large `TextField` using `.title` font weight, rounded design. Always editable — tap to focus.
- **Subtitle**: ref/file path in small dim text below the title (read-only).
- Toolbar retains only a **Delete** button (with confirmation) and dismiss.

```
○  Buy groceries
   ref: groceries.md
```

---

## Zone 2: Notes

- `TextEditor` directly below the header, no section label.
- Placeholder: "Add notes..." when empty.
- Minimum height ~3 lines so it feels inviting.
- No border — blends into scroll view background.
- Body font, secondary color for placeholder.

---

## Zone 3: Core Properties

Always-visible tappable rows. Format: `[icon]  [label]     [value or —]`

| Field      | Interaction |
|------------|-------------|
| Due        | Tap expands `DatePicker` inline below the row |
| Scheduled  | Tap expands `DatePicker` inline below the row |
| Repeat     | Tap opens a sheet (existing recurrence editor) |
| Tags       | Tap expands inline: chips with ✕ + add field |
| Status     | Tap cycles values; long-press for full picker |
| Priority   | Tap cycles None → Low → Medium → High → None |

- Empty rows show `—` in secondary color (not hidden).
- Inline expansions (DatePicker, tags editor) appear below the tapped row and collapse when the row is tapped again or another row is tapped.

---

## Zone 4: More Details (Collapsed by Default)

`DisclosureGroup` labeled "More details". Expansion state persisted in `@AppStorage`.

**Editable advanced fields** (same tappable row style):

| Field      | Interaction |
|------------|-------------|
| Assignee   | Tap to edit inline text field |
| Blocked by | Tap to edit inline text field |
| Project    | Tap to open picker |
| Estimate   | Tap expands inline stepper |
| Location   | Tap opens location sheet |

**Read-only metadata** (dim, non-interactive):
- Created date
- Updated date

---

## Behavior Notes

- **No `isEditing` state** — remove entirely along with Edit/Done toolbar buttons.
- **Auto-save** — changes save on every field change (existing `saveTask()` pattern), or on dismiss.
- **Only one inline expansion open at a time** — opening a new inline editor collapses any currently open one.
- **Sheets** that remain: Repeat editor, Location editor, Notes full-screen editor (optional, keep for long notes).
- **Delete** still requires confirmation alert.

---

## Files to Modify

- `Sources/TodoMDApp/Detail/TaskDetailView.swift` — primary file, full rewrite of body/layout
- Potentially extract sub-views into separate files if the file grows too large

## What Gets Removed

- `isEditing` state and all conditional branches on it
- `readOnlyView` computed property
- `editForm` computed property
- Edit/Done toolbar buttons
- `showNotesEditor` full-screen cover (can keep as optional enhancement)
