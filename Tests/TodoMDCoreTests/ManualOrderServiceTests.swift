import XCTest
@testable import TodoMDCore

final class ManualOrderServiceTests: XCTestCase {
    func testOrderedReturnsRecordsInCreationOrderWhenNoSavedOrderExists() throws {
        let root = try TestSupport.tempDirectory(prefix: "ManualOrderDefaults")
        let repository = FileTaskRepository(rootURL: root)

        let first = try repository.create(
            document: TaskDocument(frontmatter: frontmatter(title: "First", createdAt: 1_700_000_000), body: ""),
            preferredFilename: "first.md"
        )
        let second = try repository.create(
            document: TaskDocument(frontmatter: frontmatter(title: "Second", createdAt: 1_700_000_100), body: ""),
            preferredFilename: "second.md"
        )
        let third = try repository.create(
            document: TaskDocument(frontmatter: frontmatter(title: "Third", createdAt: 1_700_000_200), body: ""),
            preferredFilename: "third.md"
        )

        let service = ManualOrderService(rootURL: root)
        let ordered = service.ordered(records: [third, first, second], view: .builtIn(.inbox))

        XCTAssertEqual(
            ordered.map(\.identity.filename),
            [first.identity.filename, second.identity.filename, third.identity.filename]
        )
    }

    func testOrderedAppendsUnsavedRecordsAfterSavedOrderInCreationOrder() throws {
        let root = try TestSupport.tempDirectory(prefix: "ManualOrderAppend")
        let repository = FileTaskRepository(rootURL: root)

        let existing = try repository.create(
            document: TaskDocument(frontmatter: frontmatter(title: "Existing", createdAt: 1_700_000_000), body: ""),
            preferredFilename: "existing.md"
        )
        let appendedFirst = try repository.create(
            document: TaskDocument(frontmatter: frontmatter(title: "Appended First", createdAt: 1_700_000_100), body: ""),
            preferredFilename: "appended-first.md"
        )
        let appendedSecond = try repository.create(
            document: TaskDocument(frontmatter: frontmatter(title: "Appended Second", createdAt: 1_700_000_200), body: ""),
            preferredFilename: "appended-second.md"
        )

        let service = ManualOrderService(rootURL: root)
        try service.saveOrder(view: .builtIn(.inbox), filenames: [existing.identity.filename])

        let ordered = service.ordered(
            records: [appendedSecond, existing, appendedFirst],
            view: .builtIn(.inbox)
        )

        XCTAssertEqual(
            ordered.map(\.identity.filename),
            [existing.identity.filename, appendedFirst.identity.filename, appendedSecond.identity.filename]
        )
    }

    private func frontmatter(title: String, createdAt timestamp: TimeInterval) -> TaskFrontmatterV1 {
        TaskFrontmatterV1(
            title: title,
            status: .todo,
            priority: .none,
            flagged: false,
            tags: [],
            created: Date(timeIntervalSince1970: timestamp),
            modified: Date(timeIntervalSince1970: timestamp),
            source: "test"
        )
    }
}
