# Quick Find Result-Based Recents Design

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace raw-query recents with rich result-based recents that navigate directly to the clicked destination, plus a setting to opt out of recording task results.

**Architecture:** Upgrade `QuickFindStore` from `[String]` to `[RecentItem]` (a Codable struct encoding label, icon, tintHex, and destination). Recording moves from `dismissRootSearch()` to explicit result-click handlers. `QuickFindCard` receives an `onSelectRecent` callback for direct navigation.

**Tech Stack:** Swift 6, SwiftUI, `@Observable`, `UserDefaults` (JSON-encoded via `Data`), Swift Testing

---

## Data Model

### `RecentItem`

Defined in `QuickFindStore.swift`:

```swift
struct RecentItem: Codable, Hashable {
    enum Destination: Codable, Hashable {
        case view(String)   // ViewIdentifier.rawValue, e.g. "project:Italy", "inbox", "tag:work"
        case task(String)   // task file path
    }
    var label: String       // display text, e.g. "Italy"
    var icon: String        // SF Symbol name, e.g. "folder", "number", "doc.text"
    var tintHex: String?    // nil = no tint (renders with .primary via AppIconGlyph). May have # prefix or not.
    var destination: Destination
}
```

### `Destination` Codable encoding

`Destination` requires a manual `Codable` implementation using a `"type"` discriminant key. JSON format:
- `{"type":"view","value":"project:Italy"}`
- `{"type":"task","value":"/path/to/task.md"}`

For unknown `"type"` values during decoding (future-proofing): throw `DecodingError.dataCorrupted`. The outer `[RecentItem]` decode will then fail and be caught by the `try?` in `init`, silently resetting the list to empty. This is acceptable — unknown types only arise after a downgrade, and the reset is the same as the initial migration.

`Destination` is `Hashable` via synthesised conformance (both associated values are `String`, which is `Hashable`).

### `icon` field

Always an SF Symbol name (e.g. `"folder"`, `"number"`, `"doc.text"`). Never an emoji. `AppIconGlyph` is called with `fallbackSymbol: "magnifyingglass"` for all `RecentItem` rows.

### `tintHex` field

`String?`. `nil` means no custom tint — `AppIconGlyph(tint: nil)` falls back to `.primary` (per its implementation: `foregroundStyle(tint ?? .primary)`). Non-nil holds the raw hex string as returned by `container.projectColorHex(for:)` or `perspective.color`. The `color(forHex:)` helper strips `#` before parsing, so both `"#FF0000"` and `"FF0000"` are handled correctly. **No coalesce to `.accentColor` at the call site** — nil tint passes through as nil.

### Deduplication key

All dedup and delete operations match on `destination` using **case-sensitive equality** on the `Destination` enum. This is a deliberate change from the previous case-insensitive label matching. Task file paths on macOS are canonical (same case as on disk), so case-sensitive path matching is correct. `ViewIdentifier.rawValue` strings are always lower-snake-case for built-ins and exact-match for project/tag names.

### Persistence

Both `recentSearches` and `pinnedSearches` are stored as JSON-encoded `Data` in `UserDefaults`:

```swift
// Writing
defaults.set(try? JSONEncoder().encode(recentSearches), forKey: Self.recentKey)

// Reading in init
if let data = defaults.data(forKey: Self.recentKey),
   let decoded = try? JSONDecoder().decode([RecentItem].self, from: data) {
    self.recentSearches = decoded
} else {
    self.recentSearches = []
}
```

Keys reused: `"quickFind.recentSearches"`, `"quickFind.pinnedSearches"`. Old `stringArray(forKey:)` writes a `[String]` plist value under these keys. `data(forKey:)` returns `nil` for plist-encoded values, so the decode silently returns `[]`. **No cleanup of old keys required.**

**Migration on first launch after upgrade:** both recents and pinned silently reset to empty. Acceptable — convenience feature, not critical data.

### Task recording gate

```swift
private static let recordTasksKey = "quickFind.recordTasks"
var recordTasks: Bool {
    didSet { defaults.set(recordTasks, forKey: Self.recordTasksKey) }
}
// init: self.recordTasks = defaults.object(forKey: Self.recordTasksKey) as? Bool ?? true
```

When `recordTasks == false`, `record(item:)` silently drops items with a `.task` destination. `.view` destinations are always recorded.

---

## `QuickFindStore` API

### Mutations (full signatures)

```swift
func record(item: RecentItem)
func pin(_ item: RecentItem)
func unpin(_ item: RecentItem)
func deleteRecent(_ item: RecentItem)
```

### `record` behaviour

1. Guard `!item.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty` — if label is empty/whitespace, return immediately without recording.
2. If `item.destination` is `.task` and `recordTasks == false` → return immediately.
3. If `item.destination` already exists in `pinnedSearches` → return immediately (no-op; the item is already prominent as a pin, adding it to recents would pollute the backing array even though `displayedRecent` would filter it out).
4. Remove any existing entry from `recentSearches` where `entry.destination == item.destination`.
5. Insert `item` at index 0.
6. If `recentSearches.count > 10` → trim to first 10.
7. Persist.

### `pin` behaviour

1. Guard `pinnedSearches.count < 3`.
2. Guard no existing entry in `pinnedSearches` where `entry.destination == item.destination`.
3. Insert `item` at index 0 of `pinnedSearches`.
4. **Does not modify `recentSearches`** — pin does not clean up recents. `displayedRecent` filters pinned destinations at display time.
5. Persist.

### `unpin` behaviour

1. Remove all entries from `pinnedSearches` where `entry.destination == item.destination`.
2. Remove any existing entry from `recentSearches` where `entry.destination == item.destination`.
3. Insert the full `item` at index 0 of `recentSearches` (preserving label, icon, tintHex, destination).
4. If `recentSearches.count > 10` → trim to first 10.
5. Persist.

### `deleteRecent` behaviour

Remove all entries from `recentSearches` where `entry.destination == item.destination`. Persist.

### Computed display properties

```swift
var displayedPinned: [RecentItem] { pinnedSearches }  // up to 3 enforced by pin cap

var displayedRecent: [RecentItem] {
    let pinnedDestinations = Set(pinnedSearches.map(\.destination))
    return recentSearches
        .filter { !pinnedDestinations.contains($0.destination) }
        .prefix(3)
        .map { $0 }
}

var isPinFull: Bool { pinnedSearches.count >= 3 }
```

Display cap for recents: **3** (unchanged).

---

## RootView Changes

### What to remove

**Remove** the recording call from `dismissRootSearch()`:

```swift
// REMOVE these lines from dismissRootSearch():
let query = universalSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
if !query.isEmpty { quickFindStore.record(query: query) }
```

`dismissRootSearch()` after this change:

```swift
private func dismissRootSearch() {
    universalSearchText = ""
    withAnimation(.easeIn(duration: 0.18)) {
        isRootSearchPresented = false
    }
}
```

When the user dismisses without clicking a result (backdrop tap, Cancel, navigation change), **nothing is recorded**. The raw query is silently discarded.

### Updated click handlers

```swift
private func openSearchResult(
    _ view: ViewIdentifier,
    label: String,
    icon: String,
    tintHex: String? = nil
) {
    let item = RecentItem(label: label, icon: icon, tintHex: tintHex, destination: .view(view.rawValue))
    quickFindStore.record(item: item)
    dismissRootSearch()
    guard container.selectedView != view else { return }
    applyFilter(view)
}

private func openSearchTaskResult(path: String, label: String) {
    let item = RecentItem(label: label, icon: "doc.text", tintHex: nil, destination: .task(path))
    quickFindStore.record(item: item)
    dismissRootSearch()
    DispatchQueue.main.async { openFullTaskEditor(path: path) }
}
```

All `searchDestinationButton` call sites updated to pass `label`, `icon`, and optionally `tintHex` to `openSearchResult`. The task row builder passes `label: record.document.frontmatter.title` (display title string) and always `icon: "doc.text"`.

### `onSelectRecent` wiring — no re-recording from recents

When the user taps a recent or pinned item, navigate directly **without calling `store.record` again**:

```swift
onSelectRecent: { [self] item in
    switch item.destination {
    case .view(let raw):
        // Navigate without recording
        dismissRootSearch()
        let view = ViewIdentifier(rawValue: raw)
        guard container.selectedView != view else { return }
        applyFilter(view)
    case .task(let path):
        // Navigate without recording
        dismissRootSearch()
        DispatchQueue.main.async { openFullTaskEditor(path: path) }
    }
}
```

Rationale: the item is already in recents/pinned; re-recording would promote it to position 0 in the backing array (harmless but unnecessary), and for pinned items `record()` would silently no-op anyway (per the pinned-destination guard). Keeping navigation clean here avoids any confusion.

---

## `QuickFindCard` Changes

### New parameter

```swift
var onSelectRecent: (RecentItem) -> Void
```

### Row rendering

Both pinned and recent rows fire `onSelectRecent(item)` on tap. No `query = item` assignment.

```swift
AppIconGlyph(
    icon: item.icon,
    fallbackSymbol: "magnifyingglass",
    pointSize: 16,
    weight: .regular,
    tint: color(forHex: item.tintHex)   // nil passes through; AppIconGlyph renders .primary
)
Text(item.label).foregroundStyle(.primary)
```

### `color(forHex:)` helper

Add as `private func` in `QuickFindCard.swift` (copied from `RootView`):

```swift
private func color(forHex hex: String?) -> Color? {
    guard let hex else { return nil }
    let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
    guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return nil }
    return Color(
        red: Double((value & 0xFF0000) >> 16) / 255.0,
        green: Double((value & 0x00FF00) >> 8) / 255.0,
        blue: Double(value & 0x0000FF) / 255.0
    )
}
```

### Swipe & context menu affordances (same gestures, updated types)

**Pinned rows:**
- Trailing swipe: "Unpin" → `store.unpin(item)`. `.tint(.gray)`.
- Context menu: "Unpin" → `store.unpin(item)`.

**Recent rows:**
- Trailing swipe: "Pin" → `store.pin(item)`. `.tint(store.isPinFull ? .gray : .blue)`. When `isPinFull`, haptic only (UIKit-guarded).
- Context menu: "Pin" → `store.pin(item)` (`.disabled(store.isPinFull)`); "Delete" (`.destructive`) → `store.deleteRecent(item)`.

---

## Settings

`SettingsView` uses `@EnvironmentObject private var container: AppContainer` and `@AppStorage` for all its current state — it has no explicit init. Add `quickFindStore` as a stored property injected via init:

```swift
struct SettingsView: View {
    var quickFindStore: QuickFindStore   // added
    @EnvironmentObject private var container: AppContainer
    // ... rest unchanged
}
```

Three call sites in `RootView.swift` (lines 1298, 1419, 2677) all instantiate `SettingsView()` with no args. All three must be updated to `SettingsView(quickFindStore: quickFindStore)`.

New section added within the existing settings `Form` (place alongside other behavioural settings):

```swift
Section("Quick Find") {
    Toggle("Include tasks in recents", isOn: $quickFindStore.recordTasks)
}
```

`$quickFindStore.recordTasks` is bindable because `QuickFindStore` is `@Observable` and `recordTasks` is a stored property.

---

## Files Changed

| File | Change |
|------|--------|
| `Sources/TodoMDApp/Features/QuickFind/QuickFindStore.swift` | `RecentItem` + `Destination` types, `recordTasks`, updated mutations, JSON persistence |
| `Sources/TodoMDApp/Features/QuickFind/QuickFindCard.swift` | `AppIconGlyph` rows, `onSelectRecent` param, `color(forHex:)` helper, updated swipe/context menus |
| `Sources/TodoMDApp/Features/RootView.swift` | Remove recording from `dismissRootSearch`, update `openSearchResult`/`openSearchTaskResult`, wire `onSelectRecent` without re-recording, update all 3 `SettingsView()` call sites |
| `Sources/TodoMDApp/Settings/SettingsView.swift` | Add `quickFindStore` stored property, add Quick Find section |
| `Tests/TodoMDAppTests/QuickFindStoreTests.swift` | Full rewrite for `RecentItem` API |

---

## Test Cases

All tests use the `makeStore()` helper pattern (isolated `UserDefaults` UUID suite, `defer` cleanup). `RecentItem` factory helper:

```swift
private func item(_ label: String, icon: String = "folder", destination: RecentItem.Destination) -> RecentItem {
    RecentItem(label: label, icon: icon, tintHex: nil, destination: destination)
}
```

| Test name | What it verifies |
|-----------|-----------------|
| `record_addsToRecents` | Item appears at index 0 of `recentSearches` |
| `record_deduplicates_onDestination` | Same destination, new label → single entry, new label wins |
| `record_promotesExistingEntry` | Re-recording same destination promotes to front |
| `record_trimsToTen` | 11 records → count == 10, newest first |
| `record_ignoresEmptyLabel` | Empty / whitespace-only label → not recorded |
| `record_dropsTask_whenRecordTasksDisabled` | `.task` destination dropped when `recordTasks == false` |
| `record_keepsView_whenRecordTasksDisabled` | `.view` destination recorded when `recordTasks == false` |
| `record_noopsIfAlreadyPinned` | Destination already in pinnedSearches → `recentSearches` unchanged |
| `pin_movesItemToPinned` | Item appears at index 0 of `pinnedSearches` |
| `pin_deduplicates_onDestination` | Pinning same destination twice → count stays 1 |
| `pin_capsAtThree` | Fourth pin ignored; count stays 3 |
| `pin_doesNotRemoveFromRecents` | `recentSearches` unchanged after pin |
| `pin_preservesFullItem` | Pinned item in `pinnedSearches` has same label, icon, tintHex, destination as the item passed to `pin(_:)` |
| `unpin_removesFromPinned` | Item gone from `pinnedSearches` after unpin |
| `unpin_reinserts_withFullItem` | Re-inserted recent has same label/icon/tintHex/destination as the unpinned item |
| `unpin_capsRecentsAtTen` | Unpin into 10-item recents trims to 10; unpinned item is at index 0 |
| `deleteRecent_matchesOnDestination` | Deletes entry with matching destination; other entries unaffected |
| `displayedRecent_excludesPinned` | Pinned destinations absent from `displayedRecent` |
| `displayedRecent_clampsToThree` | 5 recents → `displayedRecent.count == 3` |
| `record_persistsAcrossInstances` | Item recorded on store1 is decoded correctly by store2 sharing the same `UserDefaults` |
