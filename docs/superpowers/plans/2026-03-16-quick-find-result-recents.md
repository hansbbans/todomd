# Quick Find Result-Based Recents Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace raw-query `[String]` recents with `[RecentItem]` recents that store the clicked result (label, icon, tint, destination) and navigate directly on tap.

**Architecture:** `QuickFindStore` is rewritten with a new `RecentItem` Codable type. `QuickFindCard` gets an `onSelectRecent` callback. `RootView` moves recording from `dismissRootSearch` into click handlers, and wires direct navigation from recents. `SettingsView` gets a "Include tasks in recents" toggle.

**Tech Stack:** Swift 6, SwiftUI, `@Observable`, `UserDefaults` (JSON `Data`), Swift Testing

**Spec:** `docs/superpowers/specs/2026-03-16-quick-find-result-recents-design.md`

---

## Chunk 1: QuickFindStore — model, mutations, persistence

### Task 1: Rewrite `QuickFindStore.swift`

**Files:**
- Modify: `Sources/TodoMDApp/Features/QuickFind/QuickFindStore.swift`

The current file stores `[String]`. Replace it entirely with the implementation below.

- [ ] **Step 1: Replace the file contents**

Replace `Sources/TodoMDApp/Features/QuickFind/QuickFindStore.swift` with:

```swift
// Sources/TodoMDApp/Features/QuickFind/QuickFindStore.swift
import Foundation
import Observation

// MARK: - RecentItem

struct RecentItem: Codable, Hashable {

    // MARK: Destination

    enum Destination: Hashable {
        case view(String)   // ViewIdentifier.rawValue, e.g. "project:Italy", "inbox", "tag:work"
        case task(String)   // task file path
    }

    var label: String       // display text shown in the row
    var icon: String        // SF Symbol name; always non-empty
    var tintHex: String?    // nil = .primary via AppIconGlyph; strips # in color(forHex:)
    var destination: Destination
}

// MARK: - RecentItem.Destination: Codable

extension RecentItem.Destination: Codable {
    private enum CodingKeys: String, CodingKey { case type, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        let value = try c.decode(String.self, forKey: .value)
        switch type {
        case "view": self = .view(value)
        case "task": self = .task(value)
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath,
                                      debugDescription: "Unknown destination type: \(type)")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .view(let v):
            try c.encode("view", forKey: .type)
            try c.encode(v, forKey: .value)
        case .task(let v):
            try c.encode("task", forKey: .type)
            try c.encode(v, forKey: .value)
        }
    }
}

// MARK: - QuickFindStore

@Observable
@MainActor
final class QuickFindStore {
    private static let recentKey = "quickFind.recentSearches"
    private static let pinnedKey = "quickFind.pinnedSearches"
    private static let recordTasksKey = "quickFind.recordTasks"
    private let defaults: UserDefaults

    private(set) var recentSearches: [RecentItem]
    private(set) var pinnedSearches: [RecentItem]
    var recordTasks: Bool {
        didSet { defaults.set(recordTasks, forKey: Self.recordTasksKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.recentSearches = Self.load([RecentItem].self, key: Self.recentKey, from: defaults)
        self.pinnedSearches = Self.load([RecentItem].self, key: Self.pinnedKey, from: defaults)
        self.recordTasks = defaults.object(forKey: Self.recordTasksKey) as? Bool ?? true
    }

    // MARK: - Computed display lists

    var displayedPinned: [RecentItem] { pinnedSearches }

    var displayedRecent: [RecentItem] {
        let pinnedDestinations = Set(pinnedSearches.map(\.destination))
        return recentSearches
            .filter { !pinnedDestinations.contains($0.destination) }
            .prefix(3)
            .map { $0 }
    }

    var isPinFull: Bool { pinnedSearches.count >= 3 }

    // MARK: - Mutations

    func record(item: RecentItem) {
        guard !item.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if case .task = item.destination, !recordTasks { return }
        guard !pinnedSearches.contains(where: { $0.destination == item.destination }) else { return }
        recentSearches.removeAll { $0.destination == item.destination }
        recentSearches.insert(item, at: 0)
        if recentSearches.count > 10 { recentSearches = Array(recentSearches.prefix(10)) }
        persist()
    }

    func pin(_ item: RecentItem) {
        guard pinnedSearches.count < 3 else { return }
        guard !pinnedSearches.contains(where: { $0.destination == item.destination }) else { return }
        pinnedSearches.insert(item, at: 0)
        persist()
    }

    func unpin(_ item: RecentItem) {
        pinnedSearches.removeAll { $0.destination == item.destination }
        recentSearches.removeAll { $0.destination == item.destination }
        recentSearches.insert(item, at: 0)
        if recentSearches.count > 10 { recentSearches = Array(recentSearches.prefix(10)) }
        persist()
    }

    func deleteRecent(_ item: RecentItem) {
        recentSearches.removeAll { $0.destination == item.destination }
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        defaults.set(try? JSONEncoder().encode(recentSearches), forKey: Self.recentKey)
        defaults.set(try? JSONEncoder().encode(pinnedSearches), forKey: Self.pinnedKey)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T where T: ExpressibleByArrayLiteral {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(T.self, from: data) else { return [] }
        return decoded
    }
}
```

- [ ] **Step 2: Build to confirm it compiles (both schemes)**

```bash
xcodebuild -scheme TodoMDApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
xcodebuild -scheme TodoMDMacApp -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

Expected: both `BUILD SUCCEEDED`. If there are errors about `record(query:)` call sites in `RootView.swift` or `QuickFindCard.swift`, that's expected — those will be fixed in later tasks. For now, fix only compile errors in `QuickFindStore.swift` itself.

**Note:** `RootView.swift` calls `quickFindStore.record(query:)` and `QuickFindCard.swift` uses `[String]` APIs. These will produce errors. Add a temporary shim in `QuickFindStore.swift` to unblock compilation while later tasks migrate the callers:

```swift
// TEMPORARY SHIM — remove in Task 4
@available(*, deprecated, message: "Migrate callers to record(item:)")
func record(query: String) {}
```

- [ ] **Step 3: Commit**

```bash
git add Sources/TodoMDApp/Features/QuickFind/QuickFindStore.swift
git commit -m "feat: rewrite QuickFindStore with RecentItem model"
```

---

### Task 2: Rewrite `QuickFindStoreTests.swift`

**Files:**
- Modify: `Tests/TodoMDAppTests/QuickFindStoreTests.swift`

- [ ] **Step 1: Replace the test file**

Replace `Tests/TodoMDAppTests/QuickFindStoreTests.swift` with:

```swift
// Tests/TodoMDAppTests/QuickFindStoreTests.swift
import Foundation
import Testing
@testable import TodoMDApp

@MainActor
struct QuickFindStoreTests {

    // MARK: - Helpers

    private func makeStore() throws -> (QuickFindStore, UserDefaults, String) {
        let suiteName = "QuickFindStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite")
            throw CancellationError()
        }
        let store = QuickFindStore(defaults: defaults)
        return (store, defaults, suiteName)
    }

    private func item(
        _ label: String,
        icon: String = "folder",
        tintHex: String? = nil,
        destination: RecentItem.Destination
    ) -> RecentItem {
        RecentItem(label: label, icon: icon, tintHex: tintHex, destination: destination)
    }

    // MARK: - record

    @Test("record adds item to the top of recentSearches")
    func record_addsToRecents() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.record(item: item("Inbox", destination: .view("inbox")))
        #expect(store.recentSearches.count == 1)
        #expect(store.recentSearches.first?.label == "Inbox")
        #expect(store.recentSearches.first?.destination == .view("inbox"))
    }

    @Test("record deduplicates on destination, keeping newer label")
    func record_deduplicates_onDestination() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.record(item: item("Inbox Old", destination: .view("inbox")))
        store.record(item: item("Inbox New", destination: .view("inbox")))
        #expect(store.recentSearches.count == 1)
        #expect(store.recentSearches.first?.label == "Inbox New")
    }

    @Test("record promotes an existing entry to the front")
    func record_promotesExistingEntry() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.record(item: item("Alpha", destination: .view("inbox")))
        store.record(item: item("Beta", destination: .view("today")))
        store.record(item: item("Alpha", destination: .view("inbox")))
        #expect(store.recentSearches.first?.label == "Alpha")
        #expect(store.recentSearches.count == 2)
    }

    @Test("record trims list to a maximum of 10 entries, newest first")
    func record_trimsToTen() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for i in 1...11 {
            store.record(item: item("Item \(i)", destination: .view("view\(i)")))
        }
        #expect(store.recentSearches.count == 10)
        #expect(store.recentSearches.first?.label == "Item 11")
    }

    @Test("record ignores empty or whitespace-only labels")
    func record_ignoresEmptyLabel() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.record(item: item("", destination: .view("inbox")))
        store.record(item: item("   ", destination: .view("today")))
        #expect(store.recentSearches.isEmpty)
    }

    @Test("record drops task items when recordTasks is false")
    func record_dropsTask_whenRecordTasksDisabled() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.recordTasks = false
        store.record(item: item("My Task", icon: "doc.text", destination: .task("/tasks/my-task.md")))
        #expect(store.recentSearches.isEmpty)
    }

    @Test("record keeps view items when recordTasks is false")
    func record_keepsView_whenRecordTasksDisabled() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.recordTasks = false
        store.record(item: item("Inbox", destination: .view("inbox")))
        #expect(store.recentSearches.count == 1)
    }

    @Test("record is a no-op when destination is already pinned")
    func record_noopsIfAlreadyPinned() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.pin(item("Inbox", destination: .view("inbox")))
        store.record(item: item("Inbox", destination: .view("inbox")))
        #expect(store.recentSearches.isEmpty)
    }

    // MARK: - pin

    @Test("pin moves item into pinnedSearches at the front")
    func pin_movesItemToPinned() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.pin(item("Inbox", destination: .view("inbox")))
        #expect(store.pinnedSearches.count == 1)
        #expect(store.pinnedSearches.first?.destination == .view("inbox"))
    }

    @Test("pin deduplicates on destination")
    func pin_deduplicates_onDestination() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.pin(item("Inbox", destination: .view("inbox")))
        store.pin(item("Inbox Again", destination: .view("inbox")))
        #expect(store.pinnedSearches.count == 1)
    }

    @Test("pin caps at three entries")
    func pin_capsAtThree() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.pin(item("A", destination: .view("inbox")))
        store.pin(item("B", destination: .view("today")))
        store.pin(item("C", destination: .view("anytime")))
        store.pin(item("D", destination: .view("someday")))
        #expect(store.pinnedSearches.count == 3)
        #expect(!store.pinnedSearches.contains(where: { $0.label == "D" }))
    }

    @Test("pin does not modify recentSearches")
    func pin_doesNotRemoveFromRecents() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.record(item: item("Inbox", destination: .view("inbox")))
        store.pin(item("Inbox", destination: .view("inbox")))
        #expect(store.recentSearches.count == 1)
    }

    @Test("pin preserves full item data")
    func pin_preservesFullItem() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let original = RecentItem(label: "Italy", icon: "folder", tintHex: "E53935", destination: .view("project:Italy"))
        store.pin(original)
        let pinned = store.pinnedSearches.first
        #expect(pinned?.label == "Italy")
        #expect(pinned?.icon == "folder")
        #expect(pinned?.tintHex == "E53935")
        #expect(pinned?.destination == .view("project:Italy"))
    }

    // MARK: - unpin

    @Test("unpin removes from pinnedSearches")
    func unpin_removesFromPinned() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let it = item("Inbox", destination: .view("inbox"))
        store.pin(it)
        store.unpin(it)
        #expect(store.pinnedSearches.isEmpty)
    }

    @Test("unpin re-inserts full item at top of recentSearches")
    func unpin_reinserts_withFullItem() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let original = RecentItem(label: "Italy", icon: "folder", tintHex: "E53935", destination: .view("project:Italy"))
        store.pin(original)
        store.unpin(original)
        let reinserted = store.recentSearches.first
        #expect(reinserted?.label == "Italy")
        #expect(reinserted?.icon == "folder")
        #expect(reinserted?.tintHex == "E53935")
        #expect(reinserted?.destination == .view("project:Italy"))
    }

    @Test("unpin caps recentSearches at 10, unpinned item at index 0")
    func unpin_capsRecentsAtTen() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for i in 1...10 {
            store.record(item: item("Item \(i)", destination: .view("view\(i)")))
        }
        let pinned = item("Pinned", destination: .view("pinned"))
        store.pin(pinned)
        store.unpin(pinned)
        #expect(store.recentSearches.count == 10)
        #expect(store.recentSearches.first?.label == "Pinned")
    }

    // MARK: - deleteRecent

    @Test("deleteRecent removes entry matching on destination")
    func deleteRecent_matchesOnDestination() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let alpha = item("Alpha", destination: .view("inbox"))
        let beta = item("Beta", destination: .view("today"))
        store.record(item: alpha)
        store.record(item: beta)
        store.deleteRecent(alpha)
        #expect(!store.recentSearches.contains(where: { $0.destination == .view("inbox") }))
        #expect(store.recentSearches.contains(where: { $0.destination == .view("today") }))
    }

    // MARK: - displayedRecent

    @Test("displayedRecent excludes pinned destinations")
    func displayedRecent_excludesPinned() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.record(item: item("Alpha", destination: .view("inbox")))
        store.record(item: item("Beta", destination: .view("today")))
        store.pin(item("Alpha", destination: .view("inbox")))
        #expect(store.displayedRecent.count == 1)
        #expect(store.displayedRecent.first?.destination == .view("today"))
    }

    @Test("displayedRecent shows at most three entries")
    func displayedRecent_clampsToThree() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for i in 1...5 {
            store.record(item: item("Item \(i)", destination: .view("view\(i)")))
        }
        #expect(store.displayedRecent.count == 3)
    }

    // MARK: - Persistence

    @Test("recorded items persist across separate store instances using the same defaults")
    func record_persistsAcrossInstances() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let original = RecentItem(label: "Italy", icon: "folder", tintHex: "E53935", destination: .view("project:Italy"))
        store.record(item: original)

        let store2 = QuickFindStore(defaults: defaults)
        #expect(store2.recentSearches.count == 1)
        #expect(store2.recentSearches.first?.label == "Italy")
        #expect(store2.recentSearches.first?.icon == "folder")
        #expect(store2.recentSearches.first?.tintHex == "E53935")
        #expect(store2.recentSearches.first?.destination == .view("project:Italy"))
    }
}
```

- [ ] **Step 2: Run the tests**

```bash
xcodebuild test -scheme TodoMDApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TodoMDAppTests/QuickFindStoreTests 2>&1 | grep -E "passed|failed|error:" | tail -20
```

Expected: all 20 tests pass. If any fail, read the failure message and fix the implementation in `QuickFindStore.swift`.

- [ ] **Step 3: Commit**

```bash
git add Tests/TodoMDAppTests/QuickFindStoreTests.swift
git commit -m "test: rewrite QuickFindStoreTests for RecentItem API"
```

---

## Chunk 2: QuickFindCard, RootView, SettingsView

### Task 3: Update `QuickFindCard.swift`

**Files:**
- Modify: `Sources/TodoMDApp/Features/QuickFind/QuickFindCard.swift`

- [ ] **Step 1: Replace the file contents**

Replace `Sources/TodoMDApp/Features/QuickFind/QuickFindCard.swift` with:

```swift
// Sources/TodoMDApp/Features/QuickFind/QuickFindCard.swift
import SwiftUI

struct QuickFindCard<Results: View>: View {
    @Binding var query: String
    var store: QuickFindStore
    var maxHeight: CGFloat
    var onDismiss: () -> Void
    var onSelectRecent: (RecentItem) -> Void
    @ViewBuilder var resultsContent: (String) -> Results

    @FocusState private var isSearchFieldFocused: Bool
    private var normalizedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var cardBackground: Color {
#if canImport(UIKit)
        Color(uiColor: .secondarySystemGroupedBackground)
#else
        Color(nsColor: .controlBackgroundColor)
#endif
    }

    private var pillBackground: Color {
#if canImport(UIKit)
        Color(uiColor: .tertiarySystemGroupedBackground)
#else
        Color(nsColor: .textBackgroundColor)
#endif
    }

    var body: some View {
        VStack(spacing: 0) {
            searchFieldRow
            Divider()
            cardContent
        }
        .frame(maxHeight: maxHeight, alignment: .top)
        .background(cardBackground)
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
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Quick Find", text: $query)
                    .focused($isSearchFieldFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("quickFind.searchField")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(pillBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Close Quick Find")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Card body

    // Note: rootSearchResultsContent already renders ContentUnavailableView("No Results", ...)
    // when query matches nothing. No wrapper needed here.
    @ViewBuilder
    private var cardContent: some View {
        if normalizedQuery.isEmpty {
            preQueryContent
        } else {
            List {
                resultsContent(normalizedQuery)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var preQueryContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !store.displayedPinned.isEmpty {
                sectionHeader("Pinned")
                ForEach(store.displayedPinned, id: \.destination) { pinned in
                    pinnedRow(pinned)
                }
            }
            if !store.displayedRecent.isEmpty {
                sectionHeader("Recent")
                ForEach(store.displayedRecent, id: \.destination) { recent in
                    recentRow(recent)
                }
            }
            Text("Quickly find tasks, lists, tags…")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
        }
    }

    // MARK: - Rows

    private func pinnedRow(_ item: RecentItem) -> some View {
        Button {
            onSelectRecent(item)
        } label: {
            HStack {
                AppIconGlyph(
                    icon: item.icon,
                    fallbackSymbol: "magnifyingglass",
                    pointSize: 16,
                    weight: .regular,
                    tint: color(forHex: item.tintHex)
                )
                Text(item.label)
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

    private func recentRow(_ item: RecentItem) -> some View {
        Button {
            onSelectRecent(item)
        } label: {
            HStack {
                AppIconGlyph(
                    icon: item.icon,
                    fallbackSymbol: "magnifyingglass",
                    pointSize: 16,
                    weight: .regular,
                    tint: color(forHex: item.tintHex)
                )
                Text(item.label)
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
#if canImport(UIKit)
                    Task { @MainActor in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
#endif
                } else {
                    store.pin(item)
                }
            }
            .tint(store.isPinFull ? .gray : .blue)
        }
        .contextMenu {
            Button("Pin") {
                store.pin(item)
            }
            .disabled(store.isPinFull)
            Button("Delete", role: .destructive) {
                store.deleteRecent(item)
            }
        }
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)
            Divider()
        }
    }

    // MARK: - Color helper

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
}
```

- [ ] **Step 2: Build to confirm QuickFindCard compiles**

```bash
xcodebuild -scheme TodoMDApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

Expected: `BUILD SUCCEEDED` (or only errors in `RootView.swift` due to the old `onSelectRecent` wiring not yet updated — that's fine).

- [ ] **Step 3: Commit**

```bash
git add Sources/TodoMDApp/Features/QuickFind/QuickFindCard.swift
git commit -m "feat: update QuickFindCard rows to use RecentItem and onSelectRecent"
```

---

### Task 4: Update `RootView.swift`

**Files:**
- Modify: `Sources/TodoMDApp/Features/RootView.swift`

This task has six numbered steps:
1. Simplify `dismissRootSearch` (remove recording) + remove temp shim from QuickFindStore
2. Replace `openSearchResult` signature (gains label/icon/tintHex)
3. Replace `openSearchTaskResult` signature (gains label)
4. Update `searchDestinationButton` Button action
5. Update `searchTaskResultButton` Button action
6. Wire `onSelectRecent` in the `QuickFindCard` overlay

**Context for the implementer:**

- `dismissRootSearch()` is at approximately line 4043 — it currently calls `quickFindStore.record(query:)`. Remove those recording lines.
- `openSearchResult(_ view: ViewIdentifier)` is at approximately line 4054. Replace with the new signature.
- `openSearchTaskResult(path: String)` is at approximately line 4060. Replace with the new signature.
- `searchDestinationButton` is at approximately line 3293. Its inner Button calls `openSearchResult(view)` — update to pass label, icon, tintHex.
- `searchTaskResultButton` is at approximately line 3359. Its inner Button calls `openSearchTaskResult(path:)` — update to pass label.
- The `QuickFindCard(...)` overlay is at approximately line 731. Add `onSelectRecent:` parameter.

- [ ] **Step 1: Simplify `dismissRootSearch`**

Find the current `dismissRootSearch()` implementation (search for `func dismissRootSearch`). Remove the query-recording lines:

```swift
// REMOVE these two lines:
let query = universalSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
if !query.isEmpty { quickFindStore.record(query: query) }
```

After the change, `dismissRootSearch()` should look like:

```swift
private func dismissRootSearch() {
    universalSearchText = ""
    withAnimation(.easeIn(duration: 0.18)) {
        isRootSearchPresented = false
    }
}
```

Also remove the temporary shim from `QuickFindStore.swift` that was added in Task 1 Step 2:

```swift
// REMOVE from QuickFindStore.swift:
@available(*, deprecated, message: "Migrate callers to record(item:)")
func record(query: String) {}
```

- [ ] **Step 2: Replace `openSearchResult` and `openSearchTaskResult`**

Replace the existing `openSearchResult`:

```swift
private func openSearchResult(_ view: ViewIdentifier) {
    dismissRootSearch()
    guard container.selectedView != view else { return }
    applyFilter(view)
}
```

With:

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
```

Replace the existing `openSearchTaskResult`:

```swift
private func openSearchTaskResult(path: String) {
    dismissRootSearch()
    DispatchQueue.main.async {
        openFullTaskEditor(path: path)
    }
}
```

With:

```swift
private func openSearchTaskResult(path: String, label: String) {
    let item = RecentItem(label: label, icon: "doc.text", tintHex: nil, destination: .task(path))
    quickFindStore.record(item: item)
    dismissRootSearch()
    DispatchQueue.main.async {
        openFullTaskEditor(path: path)
    }
}
```

- [ ] **Step 3: Update `searchDestinationButton` call site**

Inside `searchDestinationButton`, find the Button action:

```swift
Button {
    openSearchResult(view)
} label: {
```

Replace with:

```swift
Button {
    openSearchResult(view, label: label, icon: icon, tintHex: tintHex)
} label: {
```

- [ ] **Step 4: Update `searchTaskResultButton` call site**

Inside `searchTaskResultButton`, find the Button action:

```swift
return Button {
    openSearchTaskResult(path: record.identity.path)
} label: {
```

Replace with:

```swift
return Button {
    openSearchTaskResult(path: record.identity.path, label: frontmatter.title)
} label: {
```

- [ ] **Step 5: Wire `onSelectRecent` in the QuickFindCard overlay**

Find the `QuickFindCard(...)` call inside the `.overlay` (around line 731). It currently has these parameters:

```swift
QuickFindCard(
    query: $universalSearchText,
    store: quickFindStore,
    maxHeight: geo.size.height * 0.55,
    onDismiss: { dismissRootSearch() },
    resultsContent: { query in AnyView(rootSearchResultsContent(query: query)) }
)
```

Add `onSelectRecent` between `onDismiss` and `resultsContent`:

```swift
QuickFindCard(
    query: $universalSearchText,
    store: quickFindStore,
    maxHeight: geo.size.height * 0.55,
    onDismiss: { dismissRootSearch() },
    onSelectRecent: { item in
        switch item.destination {
        case .view(let raw):
            dismissRootSearch()
            let view = ViewIdentifier(rawValue: raw)
            guard container.selectedView != view else { return }
            applyFilter(view)
        case .task(let path):
            dismissRootSearch()
            DispatchQueue.main.async { openFullTaskEditor(path: path) }
        }
    },
    resultsContent: { query in AnyView(rootSearchResultsContent(query: query)) }
)
```

- [ ] **Step 6: Build both schemes**

```bash
xcodebuild -scheme TodoMDApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
xcodebuild -scheme TodoMDMacApp -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

Expected: both `BUILD SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
git add Sources/TodoMDApp/Features/RootView.swift Sources/TodoMDApp/Features/QuickFind/QuickFindStore.swift
git commit -m "feat: wire result-based recording and direct navigation from recents in RootView"
```

---

### Task 5: Update `SettingsView.swift`

**Files:**
- Modify: `Sources/TodoMDApp/Settings/SettingsView.swift`
- Modify: `Sources/TodoMDApp/Features/RootView.swift` (3 call sites)

- [ ] **Step 1: Add `quickFindStore` property to `SettingsView`**

Find the `struct SettingsView: View {` declaration. Add a stored property right after the opening brace, before `@EnvironmentObject`:

```swift
struct SettingsView: View {
    var quickFindStore: QuickFindStore   // injected from RootView
    @EnvironmentObject private var container: AppContainer
    // ... rest unchanged
```

- [ ] **Step 2: Add Quick Find section to `taskBehaviorSettingsView`**

Find `private var taskBehaviorSettingsView: some View {` (around line 541). Inside the `Form {`, add a new `Section` at the end, just before the closing `}` of the `Form`:

```swift
Section("Quick Find") {
    Toggle("Include tasks in recents", isOn: $quickFindStore.recordTasks)
}
```

- [ ] **Step 3: Update the three `SettingsView()` call sites in `RootView.swift`**

Search `RootView.swift` for all occurrences of `SettingsView()` (there are 3: around lines 1298, 1419, 2677). Replace each with:

```swift
SettingsView(quickFindStore: quickFindStore)
```

- [ ] **Step 4: Build both schemes**

```bash
xcodebuild -scheme TodoMDApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
xcodebuild -scheme TodoMDMacApp -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

Expected: both `BUILD SUCCEEDED`.

- [ ] **Step 5: Run full test suite**

```bash
xcodebuild test -scheme TodoMDApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TodoMDAppTests 2>&1 | grep -E "passed|failed after|error:" | tail -20
```

Expected: all unit tests pass (the 3 pre-existing natural-language date test failures are expected and unrelated to this change).

- [ ] **Step 6: Commit**

```bash
git add Sources/TodoMDApp/Settings/SettingsView.swift Sources/TodoMDApp/Features/RootView.swift
git commit -m "feat: add Quick Find settings toggle for task recording"
```

---

## Final verification

- [ ] **Build both schemes one final time**

```bash
xcodebuild -scheme TodoMDApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
xcodebuild -scheme TodoMDMacApp -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

- [ ] **Run all unit tests**

```bash
xcodebuild test -scheme TodoMDApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TodoMDAppTests 2>&1 | grep -E "Test run|passed|failed after" | tail -5
```

Expected: `Test run with N tests in M suites passed` (3 pre-existing failures in `AppContainerProjectAssignmentTests` are known and unrelated).
