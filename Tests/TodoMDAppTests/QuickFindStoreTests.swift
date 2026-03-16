// Tests/TodoMDAppTests/QuickFindStoreTests.swift
import XCTest
@testable import TodoMDApp

@MainActor
final class QuickFindStoreTests: XCTestCase {
    private var store: QuickFindStore!
    // Use an isolated UserDefaults suite to prevent cross-test contamination
    private var testDefaults: UserDefaults!
    private var testSuiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        testSuiteName = UUID().uuidString
        testDefaults = UserDefaults(suiteName: testSuiteName)!
        store = QuickFindStore(defaults: testDefaults)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removePersistentDomain(forName: testSuiteName)
        testDefaults = nil
        testSuiteName = nil
        store = nil
        try await super.tearDown()
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
