import XCTest
@testable import TodoMDCore

final class PerspectivesRepositoryTests: XCTestCase {
    func testSaveAndLoadPerspectivesDocument() throws {
        let root = try TestSupport.tempDirectory(prefix: "PerspectivesRepo")
        let repository = PerspectivesRepository()

        let perspective = PerspectiveDefinition(
            id: "work",
            name: "Work - Available",
            icon: "briefcase",
            color: "#4A90D9",
            sort: PerspectiveSort(field: .due, direction: .asc),
            groupBy: .project,
            layout: .comfortable,
            manualOrder: ["a.md", "b.md"],
            allRules: [PerspectiveRule(field: .area, operator: .equals, value: "Work")]
        )

        var document = PerspectivesDocument(
            version: 1,
            order: ["work"],
            perspectives: ["work": perspective]
        )
        document.unknownTopLevel["custom"] = .string("keep-me")

        try repository.save(document, rootURL: root)
        let loaded = try repository.load(rootURL: root)

        XCTAssertEqual(loaded.version, 1)
        XCTAssertEqual(loaded.order, ["work"])
        XCTAssertEqual(loaded.unknownTopLevel["custom"], .string("keep-me"))
        XCTAssertEqual(loaded.perspectives["work"]?.name, "Work - Available")
        XCTAssertEqual(loaded.perspectives["work"]?.icon, "briefcase")
        XCTAssertEqual(loaded.perspectives["work"]?.groupBy, .project)
    }

    func testLoadMissingFileReturnsEmptyDocument() throws {
        let root = try TestSupport.tempDirectory(prefix: "PerspectivesRepoMissing")
        let repository = PerspectivesRepository()

        let loaded = try repository.load(rootURL: root)
        XCTAssertEqual(loaded.version, 1)
        XCTAssertTrue(loaded.order.isEmpty)
        XCTAssertTrue(loaded.perspectives.isEmpty)
    }
}
