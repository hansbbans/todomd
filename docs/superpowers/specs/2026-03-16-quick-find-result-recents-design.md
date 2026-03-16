# Quick Find Result-Based Recents Design

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace raw-query recents with rich result-based recents that navigate directly to the clicked destination, plus a setting to opt out of recording task results.

**Architecture:** Upgrade `QuickFindStore` from `[String]` to `[RecentItem]` (a Codable struct encoding label, icon, tintHex, and destination). Recording moves from `dismissRootSearch()` to explicit result-click handlers. `QuickFindCard` receives an `onSelectRecent` callback for direct navigation.

**Tech Stack:** Swift 6, SwiftUI, `@Observable`, `UserDefaults` (JSON-encoded), Swift Testing

---

## Data Model

### `RecentItem`

New `Codable, Hashable` struct defined in `QuickFindStore.swift`:

```swift
struct RecentItem: Codable, Hashable {
    enum Destination: Codable, Hashable {
        case view(String)   // ViewIdentifier.rawValue — covers built-ins, areas, projects, tags, perspectives
        case task(String)   // task file path
    }
    var label: String
    var icon: String        // SF Symbol name or emoji (AppIconToken-compatible)
    var tintHex: String?    // nil = default accent
    var destination: Destination
}
```

`ViewIdentifier` already implements `RawRepresentable<String>` with prefix-based encoding (`"project:Italy"`, `"tag:work"`, `"inbox"`, `"perspective:<id>"`, etc.), so no additional Codable work is needed.

### Deduplication key

Deduplication and pin-exclusion match on `destination`, not `label`. This handles project/tag renames gracefully — a renamed item doesn't create a phantom duplicate.

### Persistence

`recentSearches: [RecentItem]` and `pinnedSearches: [RecentItem]` are persisted as JSON via `JSONEncoder`/`JSONDecoder` into `UserDefaults`. The existing string-based keys (`quickFind.recentSearches`, `quickFind.pinnedSearches`) are reused; on first read, stale `[String]` data simply fails to decode and is treated as empty (silent migration — no crash, no migration code needed).

### Task recording gate

`QuickFindStore` gains a new persisted bool:

```swift
var recordTasks: Bool  // UserDefaults key: "quickFind.recordTasks", default: true
```

When `recordTasks == false`, calls to `record(item:)` with a `.task` destination are silently dropped.

---

## `QuickFindStore` API Changes

| Old | New |
|-----|-----|
| `func record(query: String)` | `func record(item: RecentItem)` |
| `recentSearches: [String]` | `recentSearches: [RecentItem]` |
| `pinnedSearches: [String]` | `pinnedSearches: [RecentItem]` |
| `displayedRecent: [String]` | `displayedRecent: [RecentItem]` |
| `displayedPinned: [String]` | `displayedPinned: [RecentItem]` |
| `func pin(_ query: String)` | `func pin(_ item: RecentItem)` |
| `func unpin(_ query: String)` | `func unpin(_ item: RecentItem)` |
| `func deleteRecent(_ query: String)` | `func deleteRecent(_ item: RecentItem)` |
| _(none)_ | `var recordTasks: Bool` |

All existing behavioural rules (cap 10 recents, cap 3 pinned, case-insensitive dedup on destination, unpin re-inserts at top) remain unchanged — only the stored type changes.

---

## Recording Flow

### What changes

`dismissRootSearch()` in `RootView.swift` **no longer records anything**. Recording moves exclusively to the two result-click handlers:

```swift
private func openSearchResult(_ view: ViewIdentifier, label: String, icon: String, tintHex: String? = nil) {
    let item = RecentItem(label: label, icon: icon, tintHex: tintHex, destination: .view(view.rawValue))
    quickFindStore.record(item: item)
    dismissRootSearch()
    guard container.selectedView != view else { return }
    applyFilter(view)
}

private func openSearchTaskResult(path: String, label: String, icon: String) {
    let item = RecentItem(label: label, icon: icon, tintHex: nil, destination: .task(path))
    quickFindStore.record(item: item)
    dismissRootSearch()
    DispatchQueue.main.async { openFullTaskEditor(path: path) }
}
```

All `searchDestinationButton` and `searchActionButton` call sites pass through the `label`, `icon`, and optional `tintHex` they already have. The task row builder (`searchTaskRow`) passes the task title and `"circle"` / `"checkmark.circle.fill"` icon.

### `dismissRootSearch()` simplified

```swift
private func dismissRootSearch() {
    universalSearchText = ""
    withAnimation(.easeIn(duration: 0.18)) {
        isRootSearchPresented = false
    }
}
```

---

## Navigation from Recents

`QuickFindCard` gains a callback replacing the old `query = item` tap behaviour:

```swift
var onSelectRecent: (RecentItem) -> Void
```

RootView passes:

```swift
onSelectRecent: { item in
    switch item.destination {
    case .view(let raw):
        openSearchResult(ViewIdentifier(rawValue: raw), label: item.label, icon: item.icon, tintHex: item.tintHex)
    case .task(let path):
        openSearchTaskResult(path: path, label: item.label, icon: item.icon)
    }
}
```

Tapping a pinned or recent row fires `onSelectRecent(item)` — no query pre-fill.

---

## `QuickFindCard` Row Rendering

Pinned and recent rows replace the hardcoded `Image(systemName: "pin.fill")` / `Image(systemName: "clock")` with `AppIconGlyph` using the item's stored icon and tintHex:

```swift
AppIconGlyph(
    icon: item.icon,
    fallbackSymbol: "magnifyingglass",
    pointSize: 16,
    weight: .regular,
    tint: tintColor(forHex: item.tintHex)
)
```

`tintColor(forHex:)` is a private helper that calls through to the existing `color(forHex:)` on `RootView` — or duplicated as a free function in `QuickFindCard.swift` since it's a pure hex→Color conversion.

Row label renders `item.label`. Swipe actions remain on `.trailing` (swipe-left) — no change needed.

---

## Settings

A new `Section("Quick Find")` added to `SettingsView`'s general/appearance settings form:

```swift
Section("Quick Find") {
    Toggle("Include tasks in recents", isOn: $quickFindStore.recordTasks)
}
```

`quickFindStore` is passed into `SettingsView` (or accessed via environment) following the same pattern used for other store access in settings.

---

## Files Changed

| File | Change |
|------|--------|
| `Sources/TodoMDApp/Features/QuickFind/QuickFindStore.swift` | Replace `[String]` with `[RecentItem]`, add `recordTasks`, update all mutations |
| `Sources/TodoMDApp/Features/QuickFind/QuickFindCard.swift` | Replace row rendering with `AppIconGlyph`, add `onSelectRecent` callback, remove `query = item` taps |
| `Sources/TodoMDApp/Features/RootView.swift` | Update `openSearchResult`/`openSearchTaskResult` signatures, simplify `dismissRootSearch`, wire `onSelectRecent` |
| `Sources/TodoMDApp/Settings/SettingsView.swift` | Add Quick Find section with `recordTasks` toggle |
| `Tests/TodoMDAppTests/QuickFindStoreTests.swift` | Rewrite tests for `RecentItem`-based API |

---

## Testing

All existing `QuickFindStoreTests` are rewritten with `RecentItem` values. Key new cases:

- `record_deduplicates_onDestination` — same destination, different label → keeps newer label, doesn't add duplicate
- `record_dropsTask_whenRecordTasksDisabled` — `.task` destination dropped when `recordTasks == false`
- `record_keepsView_whenRecordTasksDisabled` — `.view` destination still recorded when `recordTasks == false`
- `unpin_reinserts_withOriginalItem` — unpinned item re-appears in recents with same icon/label/tintHex
