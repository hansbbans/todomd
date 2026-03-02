# Visual Refresh Design — Things 3 Inspired

**Date:** 2026-03-02
**Scope:** Full app visual refresh — task list, navigation, tab bar, animations
**Primary reference:** Things 3 (clean, minimal, warm iOS aesthetic)
**Focus screen:** Task list (most-used)

---

## Goals

- Clean, minimal aesthetic modelled on Things 3
- Warmer, softer palette — no pure black/white
- Better visual hierarchy through typography contrast, not decoration
- Snappier animations
- Reduce visual noise (toolbar cleanup, no row separators)

---

## 1. Color Tokens

Replace the "classic" preset values. Add two new tokens (`separatorLight`/`separatorDark`, `priorityHighLight`/`priorityHighDark`).

| Token | Light | Dark |
|---|---|---|
| `backgroundPrimary` | `#F2F2F7` | `#1C1C1E` |
| `surface` | `#FFFFFF` | `#2C2C2E` |
| `textPrimary` | `#1C1C1E` | `#F2F2F7` |
| `textSecondary` | `#8E8E93` | `#8E8E93` |
| `accent` | `#4A7FD4` | `#5E9BF5` |
| `overdue` | `#D94F3D` | `#FF6B6B` |
| `priorityHigh` | `#D94F3D` | `#FF6B6B` |
| `priorityMedium` | `#F5A623` | `#FFB84D` |
| `priorityLow` | `#7ED321` | `#98E44A` |
| `separator` | `#E5E5EA` | `#38383A` |

Add `separator` light/dark fields to `ThemeTokens.Colors`.
Add `separatorColor` computed property to `ThemeManager`.

---

## 2. Typography

No custom fonts. SF Pro only — contrast achieved through weight and size.

| Element | SwiftUI style | Weight | Notes |
|---|---|---|---|
| Navigation title | `.largeTitle` | `.bold` | Collapses on scroll |
| Section header | `.caption` | `.semibold` | Uppercase, letter-spaced, secondary color |
| Task title | `.body` | `.regular` | |
| Task title (completed) | `.body` | `.regular` | Strikethrough, secondary color |
| Task metadata | `.caption` | `.regular` | Secondary color, inline suffix |
| Tab bar labels | Hidden | — | Icons only |

Metadata (due date, project, tags) moves inline onto the title row as a dimmed suffix. No second line unless title wraps.

---

## 3. Task Rows

### Layout
```
[ ○ ]  Buy groceries  ·  Today  #errands
[ ○ ]  Review PR
[◉ ]  Write tests  ·  Overdue             ← in-progress = dashed circle
```

- Checkbox: 22pt outlined circle, left-aligned
- Priority colour applied to circle border (high = red, medium = orange, low = green, none = secondary)
- In-progress: dashed/partial circle (`circle.dashed` SF Symbol)
- Completed: filled checkmark (`checkmark.circle.fill`), secondary color
- Metadata shown as `· date  #tag  project` suffix on the title line, `.caption`, secondary
- No row separator lines — vertical padding (`rowVertical: 14`) provides rhythm
- Rows sit on white surface (`#FFFFFF`) in inset grouped style against `#F2F2F7` background

### Completion animation
- Checkbox fills with spring (`response: 0.28, damping: 0.78`)
- Row fades out and slides down, then removes from list
- Same spring parameters for both steps

### Swipe actions
- Leading: complete (green checkmark)
- Trailing: defer (orange clock), delete (red trash)

---

## 4. Navigation Bar & Toolbar

- Large title style on all main views, collapses on scroll
- **Remove** debug `ladybug` button from toolbar (move to Settings > Debug)
- **Remove** `EditButton` from top bar — long-press on row triggers edit/reorder mode instead
- Top-left (compact only): browse grid icon
- Top-right: settings gear only
- Search: pull-down to reveal (no persistent search bar)

---

## 5. Section Headers

- Text: uppercase, `.caption`, `.semibold`, `textSecondary` color
- Show count suffix: `OVERDUE · 3`, `DUE TODAY · 2`, `SCHEDULED`
- Top spacing: `sectionGap: 28`
- No background fill or capsule decoration — plain text, flush with row indent

---

## 6. Bottom Tab Bar & Add Button

### Tab bar
- SF Symbols icons, no labels
- Selected: accent color
- Unselected: secondary color

### Add button
- 56pt circular floating button
- Accent fill, `cornerRadius: 28` (full circle)
- Subtle drop shadow (`opacity: 0.18, radius: 8, y: 4`)
- Tap → open quick entry directly (no intermediate menu)

---

## 7. Animations

| Parameter | Old | New |
|---|---|---|
| Completion spring response | 0.34 | 0.28 |
| Completion spring damping | 0.82 | 0.78 |
| View transition duration | 0.22 | 0.18 |
| Tab switch | easeInOut | `.opacity` crossfade |

---

## Spacing Tokens (updated)

| Token | Old | New |
|---|---|---|
| `rowVertical` | 10 | 14 |
| `rowHorizontal` | 14 | 16 |
| `sectionGap` | 18 | 28 |
| `cornerRadius` | 10 | 12 |

---

## Files Affected

- `Sources/TodoMDCore/Theme/ThemeTokens.swift` — add separator tokens, update classic preset values, update spacing/motion
- `Sources/TodoMDApp/App/ThemeManager.swift` — add `separatorColor` property
- `Sources/TodoMDApp/Features/RootView.swift` — task rows, section headers, toolbar cleanup, add button, tab bar, animations
- `Sources/TodoMDApp/App/TodoMDApp.swift` / `AppContainer.swift` — animation constants
