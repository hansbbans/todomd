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

    // MARK: - record

    @Test("record adds query to the top of recentSearches")
    func record_addsToRecents() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.record(query: "inbox")
        #expect(store.recentSearches == ["inbox"])
    }

    @Test("record deduplicates case-insensitively, keeping newer casing")
    func record_deduplicates_caseInsensitive() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.record(query: "Inbox")
        store.record(query: "inbox")
        #expect(store.recentSearches == ["inbox"])
    }

    @Test("record promotes an existing entry to the front")
    func record_promotesExistingEntry() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.record(query: "alpha")
        store.record(query: "beta")
        store.record(query: "alpha")
        #expect(store.recentSearches == ["alpha", "beta"])
    }

    @Test("record trims list to a maximum of 10 entries, newest first")
    func record_trimsToTen() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for i in 1...11 {
            store.record(query: "query\(i)")
        }
        #expect(store.recentSearches.count == 10)
        #expect(store.recentSearches.first == "query11")
    }

    @Test("record ignores empty strings and whitespace-only input")
    func record_doesNotRecordEmptyOrWhitespace() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.record(query: "")
        store.record(query: "   ")
        #expect(store.recentSearches.isEmpty)
    }

    // MARK: - pin / unpin

    @Test("pin moves the query out of displayedRecent into pinnedSearches")
    func pin_movesPinnedOutOfRecents() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.record(query: "sprint")
        store.pin("sprint")
        #expect(store.pinnedSearches == ["sprint"])
        #expect(store.displayedRecent == [])
    }

    @Test("pin excludes matching recents case-insensitively")
    func pin_caseInsensitiveExclusionFromRecents() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.record(query: "Sprint")
        store.pin("sprint")
        #expect(store.displayedRecent.isEmpty)
    }

    @Test("pin caps at three entries and ignores further additions")
    func pin_capsAtThree() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.pin("a")
        store.pin("b")
        store.pin("c")
        store.pin("d")
        #expect(store.pinnedSearches.count == 3)
        #expect(!store.pinnedSearches.contains("d"))
    }

    @Test("unpin removes from pinnedSearches and inserts back at top of recents")
    func unpin_addsBackToRecentsAtTop() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.pin("sprint")
        store.unpin("sprint")
        #expect(store.pinnedSearches.isEmpty)
        #expect(store.recentSearches.first == "sprint")
    }

    // MARK: - displayedPinned / displayedRecent

    @Test("displayedPinned returns up to three pinned entries")
    func displayedPinned_returnsUpToThree() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.pin("a"); store.pin("b"); store.pin("c")
        #expect(store.displayedPinned.count == 3)
    }

    @Test("displayedRecent excludes pinned queries case-insensitively")
    func displayedRecent_excludesPinned() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.record(query: "alpha")
        store.record(query: "beta")
        store.pin("alpha")
        #expect(store.displayedRecent == ["beta"])
    }

    @Test("displayedRecent shows at most three entries")
    func displayedRecent_clampsToThree() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for i in 1...5 { store.record(query: "q\(i)") }
        #expect(store.displayedRecent.count == 3)
    }

    // MARK: - deleteRecent

    @Test("deleteRecent removes the specified entry")
    func deleteRecent_removesEntry() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.record(query: "alpha")
        store.record(query: "beta")
        store.deleteRecent("alpha")
        #expect(!store.recentSearches.contains("alpha"))
        #expect(store.recentSearches.contains("beta"))
    }

    @Test("deleteRecent matches case-insensitively")
    func deleteRecent_caseInsensitive() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.record(query: "Alpha")
        store.deleteRecent("ALPHA")
        #expect(store.recentSearches.isEmpty)
    }

    @Test("recorded queries persist across separate store instances using the same defaults")
    func record_persistsAcrossInstances() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.record(query: "persisted")
        let store2 = QuickFindStore(defaults: defaults)
        #expect(store2.recentSearches == ["persisted"])
    }
}
