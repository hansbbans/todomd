# Quick Find Modal — Design Spec
_Date: 2026-03-16_

## Overview

Replace the current bottom-sheet search presentation with a Things 3-style "Quick Find" floating modal positioned near the top of the screen. The modal appears over existing content with a semi-transparent backdrop, shows pinned and recent searches before the user starts typing, and reuses all existing search result logic once a query is entered.

---

## Visual Design

### Card
- Rounded rectangle, 16pt corner radius
- Positioned ~60pt below the screen top (below the navigation bar / safe area top)
- Full width minus 32pt horizontal margins (16pt each side)
- Background: app background color
- Drop shadow to lift card off backdrop

### Backdrop
- `Color.black.opacity(0.35)` covering the full screen behind the card (`.ignoresSafeArea()`)
- Tap-to-dismiss

### Card Sizing
- **Height**: intrinsic (auto-sized to content)
- **Max height**: 55% of the enclosing container height, determined via `GeometryReader` (not `UIScreen.main.bounds.height`, which is deprecated on iOS 16+)
- When results overflow, the results list is scrollable within the card; the search field row stays pinned at the top

---

## Card Layout — States

### State A: Empty (no pinned, no recents — first launch or cleared history)
```
[ 🔍  Quick Find                              × ]
─────────────────────────────────────────────────
  Quickly find tasks, lists, tags…
```

### State B: Pre-query with recents/pins present
```
[ 🔍  Quick Find                              × ]
─────────────────────────────────────────────────
  Pinned              (section header, only if pinnedSearches.count > 0)
  📌  "overdue review"
  📌  "high priority"

  Recent              (section header, only if displayedRecent.count > 0)
  🕐  "sprint tasks"
  🕐  "today email"

  Quickly find tasks, lists, tags…
```

### State C: Active query (universalSearchText non-empty)
```
[ 🔍  sprint                                  × ]
─────────────────────────────────────────────────
  (existing rootSearchResultsContent results — scrollable)
```
Sections from State B are replaced entirely by results. If no results: `ContentUnavailableView("No Results", systemImage: "magnifyingglass")`.

---

## Row Interactions

### Tapping a pinned or recent row
Populates `universalSearchText` with that query string → immediately transitions to State C (results). Does **not** dismiss the modal.

### Swipe actions (trailing swipe — iOS standard)
- **Recent row → "Pin"**: moves to `pinnedSearches`. If `pinnedSearches.count == 3`, button is disabled (greyed); fire `UIImpactFeedbackGenerator(.light)` haptic. No tooltip text — disabled visual state is sufficient feedback.
- **Pinned row → "Unpin"**: removes from `pinnedSearches`, inserts at top of `recentSearches`.

### Long-press context menu
- **Recent row**: "Pin" (same as swipe, same disabled rule) + "Delete" (removes from recents)
- **Pinned row**: "Unpin" (same as swipe)

### Submit / Return key
`.submitLabel(.search)`. Pressing return does **not** dismiss. Identical to current implementation.

---

## State & Persistence

### `QuickFindStore`
`@Observable` final class, `@MainActor`-isolated. Owned as `@State private var quickFindStore = QuickFindStore()` on `RootView`.

**UserDefaults keys:**
```
"quickFind.recentSearches"   // [String], max 10 stored
"quickFind.pinnedSearches"   // [String], max 3
```

**Deduplication (recents):** Case-insensitive. On `record(query:)`: remove any existing entry where `entry.lowercased() == query.lowercased()`, then insert `query` at index 0. Trim to 10.

**Display logic:**
```swift
var displayedPinned: [String] { pinnedSearches }  // up to 3

var displayedRecent: [String] {
    let pinnedLowered = Set(pinnedSearches.map { $0.lowercased() })
    return recentSearches
        .filter { !pinnedLowered.contains($0.lowercased()) }
        .prefix(3)
        .map { $0 }
}
```

**Pin cap:** `pinnedSearches.count == 3` → Pin swipe action and context menu item are visually disabled. A `UIImpactFeedbackGenerator(.light)` haptic fires on tap attempt.

---

## Animation

### Present
- Overlay fades in: `opacity(0)` → `opacity(1)`, 0.22s `easeOut`
- Card slides down 12pt + fades: `offset(y: -12) + opacity(0)` → `offset(y: 0) + opacity(1)`, 0.22s `easeOut`
- Use `withAnimation(.easeOut(duration: 0.22))` at the `presentRootSearch()` call site

### Dismiss
- Reverse: card slides up 12pt + fades out, 0.18s `easeIn`
- Use `withAnimation(.easeIn(duration: 0.18))` at each `dismissRootSearch()` call site

### Keyboard
Focus is set inside `QuickFindCard.onAppear` using an async dispatch to ensure the view is in the responder chain before focus is assigned:
```swift
.onAppear {
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        isSearchFieldFocused = true
    }
}
```
(The current sheet presentation relies on sheet's own animation to gain focus; explicit `FocusState` management is required for the overlay approach.)

### Pull-to-search
The existing `RootPullToSearchGestureModifier` indicator is unchanged. On release it calls `presentRootSearch()` as today; the overlay then animates in. No card-origin tracking.

---

## Trigger Points & Dismissal Paths

| Path | Records query? | Clears `universalSearchText`? |
|---|---|---|
| Pull-to-search release / search button | — (present) | only if `resetQuery: true` |
| Backdrop tap | Yes, if non-empty | Yes |
| × button tap | Yes, if non-empty | Yes |
| Tapping a search result row (calls `dismissRootSearch`) | Yes, if non-empty | Yes |
| `applyFilter(_:)` called while search open | Yes, if non-empty | Yes |
| `container.selectedView` change observer | Yes, if non-empty | Yes |
| `activeNavigationDepth > 0` observer | Yes, if non-empty | Yes |

**Updated `dismissRootSearch()`:**
```swift
private func dismissRootSearch() {
    let query = universalSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !query.isEmpty {
        quickFindStore.record(query: query)
    }
    universalSearchText = ""
    isRootSearchPresented = false
    // Note: isRootSearchFieldFocused removed — focus lives in QuickFindCard
    // Note: rootSearchPresentationDetent removed — sheet-only state, deleted
}
```

**Updated `applyFilter(_:)`** — route dismissal through `dismissRootSearch()`:
```swift
private func applyFilter(_ view: ViewIdentifier) {
    if isRootSearchPresented {
        dismissRootSearch()  // records query, clears state
    }
    withAnimation(.easeInOut(duration: 0.18)) {
        container.selectedView = view
    }
    // isRootSearchFieldFocused removed
    // UIApplication.resignFirstResponder call remains (still valid for other fields)
#if canImport(UIKit)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
}
```

**No swipe-to-dismiss** (overlay, not sheet). Dismissal is via backdrop tap or × only.

---

## Architecture

### New files

| File | Contents |
|---|---|
| `Sources/TodoMDApp/Features/QuickFind/QuickFindCard.swift` | SwiftUI card view: field, pinned rows, recent rows, hint, results |
| `Sources/TodoMDApp/Features/QuickFind/QuickFindStore.swift` | `@Observable @MainActor` class, UserDefaults persistence |

### Changes to `RootView`

**State variables — delete:**
```swift
// DELETE these (sheet-only state):
@State private var rootSearchPresentationDetent: PresentationDetent
@FocusState private var isRootSearchFieldFocused: Bool
```

**State variables — add:**
```swift
@State private var quickFindStore = QuickFindStore()
```

**`rootPresentedView` — in `Sources/TodoMDApp/Features/RootView.swift`:**

Remove the search `.sheet` block (lines ~726–733):
```swift
// DELETE:
.sheet(
    isPresented: $isRootSearchPresented,
    onDismiss: { universalSearchText = "" }
) {
    NavigationStack { rootSearchSheet }
}
```

Add a `.overlay` **after** the existing `expandedTaskDateModal` overlay, **before** the QuickEntry sheet:
```swift
.overlay {
    if isRootSearchPresented {
        ZStack(alignment: .top) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeIn(duration: 0.18)) { dismissRootSearch() }
                }

            GeometryReader { geo in
                QuickFindCard(
                    query: $universalSearchText,
                    store: quickFindStore,
                    maxHeight: geo.size.height * 0.55,
                    onDismiss: {
                        withAnimation(.easeIn(duration: 0.18)) { dismissRootSearch() }
                    },
                    resultsContent: { query in
                        AnyView(rootSearchResultsContent(query: query))
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, 60)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .transition(
            .asymmetric(
                insertion: .offset(y: -12).combined(with: .opacity),
                removal: .offset(y: -12).combined(with: .opacity)
            )
        )
    }
}
```

The overlay is placed on `rootPresentedView`, which is inside `rootAlertedView` and `rootLifecycleView`. This ensures system alerts (on the outer `rootAlertedView`) still render above the Quick Find overlay as expected.

**`presentRootSearch()`** — remove `rootSearchPresentationDetent` reset and `isRootSearchFieldFocused = false`:
```swift
@MainActor
private func presentRootSearch(resetQuery: Bool = true) {
    if resetQuery { universalSearchText = "" }
    withAnimation(.easeOut(duration: 0.22)) {
        isRootSearchPresented = true
    }
}
```

### Deleted dead code
- `rootSearchSheet` computed var (the old sheet content)
- `rootSearchFieldBar` computed var (moves into `QuickFindCard`)
- All `#if os(iOS) rootSearchPresentationDetent` guards

### Reused unchanged
- `rootSearchResultsContent(query:)` — passed as closure into `QuickFindCard`
- `AppContainer.searchRecords(query:limit:)` — backend search
- `universalSearchText` state on `RootView`

---

## Swift 6 / iOS 17 Notes

- `QuickFindStore` is `@MainActor`-isolated; no background access to its state
- `GeometryReader` used for `maxHeight` instead of deprecated `UIScreen.main`
- `@FocusState` lives entirely inside `QuickFindCard` — not passed from `RootView`
- Animations are `withAnimation` at call sites, not `.animation(value:)` on the outer view, to avoid animating background content on every state change

---

## Out of Scope

- Syncing pinned/recent searches across devices (UserDefaults is local only)
- Searching from widgets or share extension
- Animating individual result row insertions
- Card origin tracking the pull-to-search finger position

---

## Success Criteria

1. Modal appears near top of screen with keyboard raised within ~50ms of presentation
2. Pinned searches appear above recents; recents exclude pinned queries (case-insensitive)
3. Tapping a recent/pinned row populates the search field and shows results without dismissing
4. Typing produces identical results to the current search implementation
5. Pin/unpin interactions persist correctly across app launches
6. All dismissal paths record a non-empty query before clearing state
7. Pull-to-search gesture and search button both trigger the new modal
8. System alerts (rate limit, etc.) continue to render above the Quick Find overlay
9. QuickEntry and VoiceRamble sheets are unaffected
10. No compile errors from deleted `isRootSearchFieldFocused` or `rootSearchPresentationDetent` references
