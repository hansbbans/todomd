# Quick Find Modal Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the bottom-sheet search presentation with a Things 3-style floating modal near the top of the screen, with pinned/recent search history and a semi-transparent backdrop.

**Architecture:** Two new files (`QuickFindStore` for persistence, `QuickFindCard` for the view) are introduced as a self-contained `QuickFind` feature module. `RootView` is surgically modified to remove the old search sheet, add the overlay, and update three functions (`presentRootSearch`, `dismissRootSearch`, `applyFilter`). All existing search result logic is reused unchanged.

**Tech Stack:** Swift 6, SwiftUI, iOS 17+, `@Observable`, `UserDefaults`, `@FocusState`

---

## Chunk 1: QuickFindStore — persistence layer

### Task 1: Create `QuickFindStore` with tests

**Files:**
- Create: `Sources/TodoMDApp/Features/QuickFind/QuickFindStore.swift`
- Create: `Tests/TodoMDAppTests/QuickFindStoreTests.swift`

- [ ] **Step 1: Create the test file**

```swift
// Tests/TodoMDAppTests/QuickFindStoreTests.swift
import XCTest
@testable import TodoMDApp

@MainActor
final class QuickFindStoreTests: XCTestCase {
    private var store: QuickFindStore!
    private let recentKey = "quickFind.recentSearches"
    private let pinnedKey = "quickFind.pinnedSearches"
    private let defaults = UserDefaults.standard

    // Use an isolated UserDefaults suite to prevent cross-test contamination
    private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        let suiteName = UUID().uuidString
        testDefaults = UserDefaults(suiteName: suiteName)!
        store = QuickFindStore(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removeSuite(named: testDefaults.description)
        testDefaults = nil
        store = nil
        super.tearDown()
    }

    // MARK: - record

    func testRecord_addsToRecents() {
        store.record(query: "inbox")
        XCTAssertEqual(store.recentSearches, ["inbox"])
    }

    func testRecord_deduplicates_caseInsensitive() {
        store.record(query: "Inbox")
        store.record(query: "inbox")
        XCTAssertEqual(store.recentSearches, ["inbox"])
    }

    func testRecord_promotesExistingEntry() {
        store.record(query: "alpha")
        store.record(query: "beta")
        store.record(query: "alpha")
        XCTAssertEqual(store.recentSearches, ["alpha", "beta"])
    }

    func testRecord_trimsToTen() {
        for i in 1...11 {
            store.record(query: "query\(i)")
        }
        XCTAssertEqual(store.recentSearches.count, 10)
        XCTAssertEqual(store.recentSearches.first, "query11")
    }

    func testRecord_doesNotRecordEmptyOrWhitespace() {
        store.record(query: "")
        store.record(query: "   ")
        XCTAssertTrue(store.recentSearches.isEmpty)
    }

    // MARK: - pin / unpin

    func testPin_movesPinnedOutOfRecents() {
        store.record(query: "sprint")
        store.pin("sprint")
        XCTAssertEqual(store.pinnedSearches, ["sprint"])
        XCTAssertEqual(store.displayedRecent, [])
    }

    func testPin_caseInsensitiveExclusionFromRecents() {
        store.record(query: "Sprint")
        store.pin("sprint")
        XCTAssertTrue(store.displayedRecent.isEmpty)
    }

    func testPin_capsAtThree() {
        store.pin("a")
        store.pin("b")
        store.pin("c")
        store.pin("d")
        XCTAssertEqual(store.pinnedSearches.count, 3)
        XCTAssertFalse(store.pinnedSearches.contains("d"))
    }

    func testUnpin_addsBackToRecentsAtTop() {
        store.pin("sprint")
        store.unpin("sprint")
        XCTAssertTrue(store.pinnedSearches.isEmpty)
        XCTAssertEqual(store.recentSearches.first, "sprint")
    }

    // MARK: - displayedPinned / displayedRecent

    func testDisplayedPinned_returnsUpToThree() {
        store.pin("a"); store.pin("b"); store.pin("c")
        XCTAssertEqual(store.displayedPinned.count, 3)
    }

    func testDisplayedRecent_excludesPinned() {
        store.record(query: "alpha")
        store.record(query: "beta")
        store.pin("alpha")
        XCTAssertEqual(store.displayedRecent, ["beta"])
    }

    func testDisplayedRecent_clampsToThree() {
        for i in 1...5 { store.record(query: "q\(i)") }
        XCTAssertEqual(store.displayedRecent.count, 3)
    }

    // MARK: - deleteRecent

    func testDeleteRecent_removesEntry() {
        store.record(query: "alpha")
        store.record(query: "beta")
        store.deleteRecent("alpha")
        XCTAssertFalse(store.recentSearches.contains("alpha"))
        XCTAssertTrue(store.recentSearches.contains("beta"))
    }

    func testDeleteRecent_caseInsensitive() {
        store.record(query: "Alpha")
        store.deleteRecent("ALPHA")
        XCTAssertTrue(store.recentSearches.isEmpty)
    }

    func testRecord_persistsAcrossInstances() {
        store.record(query: "persisted")
        let store2 = QuickFindStore(defaults: testDefaults)
        XCTAssertEqual(store2.recentSearches, ["persisted"])
    }
}
```

- [ ] **Step 2: Run the tests to confirm they all fail (QuickFindStore not yet created)**

```bash
cd /Users/hans/code/todomd
xcodebuild test -scheme TodoMDApp -only-testing:TodoMDAppTests/QuickFindStoreTests 2>&1 | tail -30
```

Expected: compile error — `QuickFindStore` undefined.

- [ ] **Step 3: Create `QuickFindStore`**

```swift
// Sources/TodoMDApp/Features/QuickFind/QuickFindStore.swift
import Foundation
import Observation

@Observable
@MainActor
final class QuickFindStore {
    private let recentKey = "quickFind.recentSearches"
    private let pinnedKey = "quickFind.pinnedSearches"
    private let defaults: UserDefaults

    private(set) var recentSearches: [String]
    private(set) var pinnedSearches: [String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.recentSearches = defaults.stringArray(forKey: "quickFind.recentSearches") ?? []
        self.pinnedSearches = defaults.stringArray(forKey: "quickFind.pinnedSearches") ?? []
    }

    // MARK: - Computed display lists

    var displayedPinned: [String] { pinnedSearches }

    var displayedRecent: [String] {
        let pinnedLowered = Set(pinnedSearches.map { $0.lowercased() })
        return recentSearches
            .filter { !pinnedLowered.contains($0.lowercased()) }
            .prefix(3)
            .map { $0 }
    }

    var isPinFull: Bool { pinnedSearches.count >= 3 }

    // MARK: - Mutations

    func record(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentSearches.removeAll { $0.lowercased() == trimmed.lowercased() }
        recentSearches.insert(trimmed, at: 0)
        if recentSearches.count > 10 { recentSearches = Array(recentSearches.prefix(10)) }
        persist()
    }

    func pin(_ query: String) {
        guard pinnedSearches.count < 3 else { return }
        guard !pinnedSearches.map({ $0.lowercased() }).contains(query.lowercased()) else { return }
        pinnedSearches.insert(query, at: 0)
        persist()
    }

    func unpin(_ query: String) {
        pinnedSearches.removeAll { $0.lowercased() == query.lowercased() }
        recentSearches.insert(query, at: 0)
        persist()
    }

    func deleteRecent(_ query: String) {
        recentSearches.removeAll { $0.lowercased() == query.lowercased() }
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        defaults.set(recentSearches, forKey: recentKey)
        defaults.set(pinnedSearches, forKey: pinnedKey)
    }
}
```

- [ ] **Step 4: Run the tests — expect all pass**

```bash
cd /Users/hans/code/todomd
xcodebuild test -scheme TodoMDApp -only-testing:TodoMDAppTests/QuickFindStoreTests 2>&1 | grep -E "PASS|FAIL|error:|warning:" | head -40
```

Expected: all tests PASS, zero errors.

- [ ] **Step 5: Commit**

```bash
git add Sources/TodoMDApp/Features/QuickFind/QuickFindStore.swift Tests/TodoMDAppTests/QuickFindStoreTests.swift
git commit -m "feat: add QuickFindStore with persistence and tests"
```

---

## Chunk 2: QuickFindCard view

### Task 2: Create `QuickFindCard`

**Files:**
- Create: `Sources/TodoMDApp/Features/QuickFind/QuickFindCard.swift`

The card has no business logic — all state comes from `QuickFindStore`. Unit tests for the store cover correctness; the card is exercised through UI/manual testing.

- [ ] **Step 1: Create the card view**

```swift
// Sources/TodoMDApp/Features/QuickFind/QuickFindCard.swift
import SwiftUI

struct QuickFindCard<Results: View>: View {
    @Binding var query: String
    var store: QuickFindStore
    var maxHeight: CGFloat
    var onDismiss: () -> Void
    @ViewBuilder var resultsContent: (String) -> Results

    @FocusState private var isSearchFieldFocused: Bool
    private var normalizedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            searchFieldRow
            Divider()
            cardContent
        }
        .frame(maxHeight: maxHeight, alignment: .top)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 4)
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                isSearchFieldFocused = true
            }
        }
    }

    // MARK: - Search field

    private var searchFieldRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Quick Find", text: $query)
                .focused($isSearchFieldFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityIdentifier("quickFind.searchField")
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Close Quick Find")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    // MARK: - Card body

    // Note: rootSearchResultsContent already renders ContentUnavailableView("No Results", ...)
    // when query matches nothing (verified at RootView.swift:2873). No wrapper needed here.
    @ViewBuilder
    private var cardContent: some View {
        if normalizedQuery.isEmpty {
            preQueryContent
        } else {
            ScrollView {
                resultsContent(normalizedQuery)
            }
        }
    }

    private var preQueryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !store.displayedPinned.isEmpty {
                    sectionHeader("Pinned")
                    ForEach(store.displayedPinned, id: \.self) { pinned in
                        pinnedRow(pinned)
                    }
                }
                if !store.displayedRecent.isEmpty {
                    sectionHeader("Recent")
                    ForEach(store.displayedRecent, id: \.self) { recent in
                        recentRow(recent)
                    }
                }
                Text("Quickly find tasks, lists, tags…")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Rows

    private func pinnedRow(_ item: String) -> some View {
        Button {
            query = item
        } label: {
            HStack {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                Text(item)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button("Unpin") {
                store.unpin(item)
            }
            .tint(.gray)
        }
        .contextMenu {
            Button("Unpin") { store.unpin(item) }
        }
    }

    private func recentRow(_ item: String) -> some View {
        Button {
            query = item
        } label: {
            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                Text(item)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button("Pin") {
                if store.isPinFull {
                    Task { @MainActor in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                } else {
                    store.pin(item)
                }
            }
            .tint(store.isPinFull ? .gray : .blue)
        }
        .contextMenu {
            Button("Pin") {
                if store.isPinFull {
                    Task { @MainActor in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                } else {
                    store.pin(item)
                }
            }
            .disabled(store.isPinFull)
            Button("Delete", role: .destructive) {
                store.deleteRecent(item)
            }
        }
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}
```

- [ ] **Step 2: Build to confirm no compile errors**

```bash
cd /Users/hans/code/todomd
xcodebuild build -scheme TodoMDApp -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E "error:|Build succeeded|Build FAILED" | head -20
```

Expected: `Build succeeded` (or only warnings, zero errors).

- [ ] **Step 3: Commit**

```bash
git add Sources/TodoMDApp/Features/QuickFind/QuickFindCard.swift
git commit -m "feat: add QuickFindCard view"
```

---

## Chunk 3: RootView migration

### Task 3: Wire QuickFindCard into RootView and remove the old sheet

**Files:**
- Modify: `Sources/TodoMDApp/Features/RootView.swift` — multiple targeted edits

Work through the edits below in order. Each is small and independent; compile after each one.

- [ ] **Step 1: Delete the two sheet-only state variables (lines 643, 655)**

Find and remove:
```swift
// line 643 — DELETE this line:
@State private var rootSearchPresentationDetent: PresentationDetent = .fraction(0.58)

// line 655 — DELETE this line:
@FocusState private var isRootSearchFieldFocused: Bool
```

Add the store variable near line 640 (with the other search state):
```swift
@State private var quickFindStore = QuickFindStore()
```

- [ ] **Step 2: Build — expect compile errors about the deleted vars (expected at this stage)**

```bash
xcodebuild build -scheme TodoMDApp -destination 'generic/platform=iOS Simulator' 2>&1 | grep "error:" | head -20
```

Expected: errors at lines 3421, 3426, 3447, 4107, 4120, 4122, 4128, 4131. This is the checklist of places to fix next.

- [ ] **Step 3: Update `dismissRootSearch()` (lines ~4127–4134)**

Replace the existing body:
```swift
private func dismissRootSearch() {
    isRootSearchFieldFocused = false
    universalSearchText = ""
#if os(iOS)
    rootSearchPresentationDetent = .fraction(0.58)
#endif
    isRootSearchPresented = false
}
```

With:
```swift
private func dismissRootSearch() {
    let query = universalSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !query.isEmpty {
        quickFindStore.record(query: query)
    }
    universalSearchText = ""
    isRootSearchPresented = false
}
```

- [ ] **Step 4: Update `presentRootSearch()` (lines ~4115–4125)**

Replace:
```swift
@MainActor
private func presentRootSearch(resetQuery: Bool = true) {
    if resetQuery {
        universalSearchText = ""
    }
    isRootSearchFieldFocused = false
#if os(iOS)
    rootSearchPresentationDetent = .fraction(0.58)
#endif
    isRootSearchPresented = true
}
```

With:
```swift
@MainActor
private func presentRootSearch(resetQuery: Bool = true) {
    if resetQuery { universalSearchText = "" }
    withAnimation(.easeOut(duration: 0.22)) {
        isRootSearchPresented = true
    }
}
```

- [ ] **Step 5: Update `applyFilter(_:)` (lines ~4103–4113)**

Replace:
```swift
private func applyFilter(_ view: ViewIdentifier) {
    withAnimation(.easeInOut(duration: 0.18)) {
        container.selectedView = view
    }
    isRootSearchFieldFocused = false
    universalSearchText = ""
    isRootSearchPresented = false
#if canImport(UIKit)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
}
```

With:
```swift
private func applyFilter(_ view: ViewIdentifier) {
    if isRootSearchPresented {
        dismissRootSearch()
    }
    withAnimation(.easeInOut(duration: 0.18)) {
        container.selectedView = view
    }
#if canImport(UIKit)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
}
```

- [ ] **Step 6: Fix `rootSearchSheet` — remove references to deleted state (lines ~3381–3432)**

In the `rootSearchSheet` computed var, remove:
```swift
// In .presentationDetents line (~3421):
.presentationDetents([.fraction(0.58), .large], selection: $rootSearchPresentationDetent)

// In toolbar dismissal (~3426):
isRootSearchFieldFocused = false  // remove this line from the Done button action
```

And in `rootSearchFieldBar` (~3447):
```swift
// Remove the .focused modifier referencing the deleted FocusState:
.focused($isRootSearchFieldFocused)
```

- [ ] **Step 7: Build — expect clean compile**

```bash
xcodebuild build -scheme TodoMDApp -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E "error:|Build succeeded" | head -20
```

Expected: `Build succeeded`, zero errors.

- [ ] **Step 8: Replace the search `.sheet` with the Quick Find `.overlay` in `rootPresentedView` (lines ~715–733)**

In `rootPresentedView`, find and **remove** the search sheet block:
```swift
.sheet(
    isPresented: $isRootSearchPresented,
    onDismiss: { universalSearchText = "" }
) {
    NavigationStack {
        rootSearchSheet
    }
}
```

**Add** the overlay in its place (right after the existing `expandedTaskDateModal` overlay, before `.sheet(isPresented: $showingQuickEntry)`):
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

- [ ] **Step 9: Build to confirm clean compile**

```bash
xcodebuild build -scheme TodoMDApp -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E "error:|Build succeeded" | head -20
```

Expected: `Build succeeded`.

- [ ] **Step 10: Delete dead code — `rootSearchSheet` and `rootSearchFieldBar`**

The following computed vars are no longer referenced and should be deleted:
- `rootSearchSheet` (starts at line ~3381, ends before `rootSearchFieldBar`)
- `rootSearchFieldBar` (starts at line ~3434)

Use search to find and remove both vars entirely. They were only used by the old `.sheet` block. After deletion:

```bash
xcodebuild build -scheme TodoMDApp -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E "error:|Build succeeded" | head -20
```

Expected: `Build succeeded`. If there are "unused" warnings for the vars, you've found more references to clean up.

- [ ] **Step 11: Run existing tests to confirm no regressions**

```bash
cd /Users/hans/code/todomd
xcodebuild test -scheme TodoMDApp 2>&1 | grep -E "PASS|FAIL|error:" | tail -30
```

Expected: all tests pass, including `QuickFindStoreTests`.

- [ ] **Step 12: Commit**

```bash
git add Sources/TodoMDApp/Features/RootView.swift
git commit -m "feat: replace search bottom sheet with Quick Find top modal"
```

---

## Manual Verification Checklist

After the build is on simulator or device, verify each success criterion from the spec:

- [ ] Modal appears near top of screen (not bottom) when search button tapped
- [ ] Keyboard raises within ~50ms of modal appearance
- [ ] Pull-to-search gesture triggers the new modal (not old sheet)
- [ ] Empty state shows hint text only
- [ ] Record 2+ searches → "Recent" section appears with correct queries
- [ ] Pin a search → moves to "Pinned" section, disappears from "Recent"
- [ ] Unpin → moves back to "Recent"
- [ ] 4th pin attempt → haptic fires, item stays in Recent
- [ ] Tapping a pinned/recent row fills search field without dismissing
- [ ] Typing produces results matching the old sheet (spot-check 3 queries)
- [ ] Backdrop tap dismisses and records the query
- [ ] × button dismisses and records the query
- [ ] Navigating to a result dismisses and records the query
- [ ] Kill and relaunch app → pinned and recent searches still present
- [ ] Open Quick Entry sheet (+ button) — unaffected, opens normally
- [ ] Open VoiceRamble — unaffected
- [ ] Trigger rate-limit alert (if possible) — appears above the Quick Find overlay
