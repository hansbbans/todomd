import XCTest
@testable import TodoMDCore

final class OrderRepositoryTests: XCTestCase {
    func testSaveAndLoadOrderDocument() throws {
        let root = try TestSupport.tempDirectory(prefix: "OrderRepo")
        let repository = OrderRepository()

        var document = OrderDocument(version: 1, views: ["inbox": ["a.md", "b.md"]])
        document.unknownTopLevel["custom"] = .string("value")

        try repository.save(document, rootURL: root)
        let loaded = try repository.load(rootURL: root)

        XCTAssertEqual(loaded.version, 1)
        XCTAssertEqual(loaded.views["inbox"], ["a.md", "b.md"])
        XCTAssertEqual(loaded.unknownTopLevel["custom"], .string("value"))
    }
}
