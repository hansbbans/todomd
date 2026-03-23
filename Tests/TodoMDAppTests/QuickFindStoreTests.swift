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

    @Test("pin caps at five entries")
    func pin_capsAtFive() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.pin(item("A", destination: .view("inbox")))
        store.pin(item("B", destination: .view("today")))
        store.pin(item("C", destination: .view("anytime")))
        store.pin(item("D", destination: .view("someday")))
        store.pin(item("E", destination: .view("flagged")))
        store.pin(item("F", destination: .view("review")))
        #expect(store.pinnedSearches.count == 5)
        #expect(!store.pinnedSearches.contains(where: { $0.label == "F" }))
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

    @Test("pinned items persist across separate store instances using the same defaults")
    func pin_persistsAcrossInstances() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let original = RecentItem(label: "Italy", icon: "folder", tintHex: "E53935", destination: .view("project:Italy"))
        store.pin(original)

        let store2 = QuickFindStore(defaults: defaults)
        #expect(store2.pinnedSearches.count == 1)
        #expect(store2.pinnedSearches.first?.label == "Italy")
        #expect(store2.pinnedSearches.first?.icon == "folder")
        #expect(store2.pinnedSearches.first?.tintHex == "E53935")
        #expect(store2.pinnedSearches.first?.destination == .view("project:Italy"))
    }

    @Test("pinned task items persist across separate store instances using the same defaults")
    func pin_taskPersistsAcrossInstances() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let original = RecentItem(
            label: "File taxes",
            icon: "doc.text",
            tintHex: nil,
            destination: .task("/tasks/file-taxes.md")
        )
        store.pin(original)

        let store2 = QuickFindStore(defaults: defaults)
        #expect(store2.pinnedSearches.count == 1)
        #expect(store2.pinnedSearches.first?.label == "File taxes")
        #expect(store2.pinnedSearches.first?.icon == "doc.text")
        #expect(store2.pinnedSearches.first?.destination == .task("/tasks/file-taxes.md"))
    }

    @Test("shared defaults can migrate pinned items from legacy defaults")
    func init_migratesPinnedItemsFromLegacyDefaults() throws {
        let defaultsSuite = "QuickFindStoreTests.Shared.\(UUID().uuidString)"
        let legacySuite = "QuickFindStoreTests.Legacy.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: defaultsSuite),
              let legacyDefaults = UserDefaults(suiteName: legacySuite) else {
            Issue.record("Failed to create isolated UserDefaults suites")
            throw CancellationError()
        }
        defer {
            defaults.removePersistentDomain(forName: defaultsSuite)
            legacyDefaults.removePersistentDomain(forName: legacySuite)
        }

        let original = RecentItem(label: "Inbox", icon: "tray", tintHex: nil, destination: .view("inbox"))
        legacyDefaults.set(try JSONEncoder().encode([original]), forKey: "quickFind.pinnedSearches")

        let store = QuickFindStore(defaults: defaults, legacyDefaults: legacyDefaults)
        #expect(store.pinnedSearches.count == 1)
        #expect(store.pinnedSearches.first?.destination == .view("inbox"))

        let store2 = QuickFindStore(defaults: defaults, legacyDefaults: nil)
        #expect(store2.pinnedSearches.count == 1)
        #expect(store2.pinnedSearches.first?.destination == .view("inbox"))
    }
}
