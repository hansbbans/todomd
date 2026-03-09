import XCTest
@testable import TodoMDCore

final class TriageRulesRepositoryTests: XCTestCase {
    func testSaveAndLoadRoundTrip() throws {
        let root = try TestSupport.tempDirectory(prefix: "TriageRulesRepo")
        let repository = TriageRulesRepository()

        var document = TriageRulesDocument(
            version: 1,
            keywordProjectWeights: [
                "invoice": ["Finance": 4],
                "qa": ["Release": 2]
            ]
        )
        document.unknownTopLevel["custom"] = .string("keep-me")

        try repository.save(document, rootURL: root)
        let loaded = try repository.load(rootURL: root)

        XCTAssertEqual(loaded.version, 1)
        XCTAssertEqual(loaded.keywordProjectWeights["invoice"]?["Finance"], 4)
        XCTAssertEqual(loaded.keywordProjectWeights["qa"]?["Release"], 2)
        XCTAssertEqual(loaded.unknownTopLevel["custom"], .string("keep-me"))
    }

    func testLoadMissingFileReturnsEmptyDocument() throws {
        let root = try TestSupport.tempDirectory(prefix: "TriageRulesRepoMissing")
        let repository = TriageRulesRepository()

        let loaded = try repository.load(rootURL: root)

        XCTAssertEqual(loaded.version, 1)
        XCTAssertTrue(loaded.keywordProjectWeights.isEmpty)
    }
}
