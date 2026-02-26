import XCTest
@testable import TodoMDCore

final class IntegrationScenarioTests: XCTestCase {
    func testExternalAddIsIngestedAndQueryableInTodayView() throws {
        let root = try TestSupport.tempDirectory(prefix: "IntegrationAdd")
        let repository = FileTaskRepository(rootURL: root)
        let watcher = FileWatcherService(rootURL: root, repository: repository)
        let query = TaskQueryEngine()

        let today = try LocalDate(isoDate: "2026-02-26")
        let frontmatter = TaskFrontmatterV1(
            title: "External task",
            status: .todo,
            due: today,
            created: Date(timeIntervalSince1970: 1_700_000_000),
            modified: Date(timeIntervalSince1970: 1_700_000_000),
            source: "external-tool"
        )

        _ = try repository.create(
            document: TaskDocument(frontmatter: frontmatter, body: "from external"),
            preferredFilename: "external.md"
        )

        let sync = try watcher.synchronize(now: Date(timeIntervalSince1970: 1_700_000_010))
        let records = try repository.loadAll()

        XCTAssertEqual(sync.summary.ingestedCount, 1)
        XCTAssertTrue(sync.events.contains { event in
            if case .created(let path, let source, _) = event {
                return path.hasSuffix("external.md") && source == "external-tool"
            }
            return false
        })
        XCTAssertTrue(records.contains { query.matches($0, view: .builtIn(.today), today: today) })
    }

    func testExternalDeleteIsReflectedInWatcherSummary() throws {
        let root = try TestSupport.tempDirectory(prefix: "IntegrationDelete")
        let repository = FileTaskRepository(rootURL: root)
        let watcher = FileWatcherService(rootURL: root, repository: repository)
        let fileIO = TaskFileIO()

        let record = try repository.create(
            document: TaskDocument(frontmatter: TestSupport.sampleFrontmatter(title: "Delete me"), body: ""),
            preferredFilename: "delete-me.md"
        )
        _ = try watcher.synchronize(now: Date(timeIntervalSince1970: 1_700_000_000))

        try fileIO.delete(path: record.identity.path)
        let sync = try watcher.synchronize(now: Date(timeIntervalSince1970: 1_700_000_030))

        XCTAssertEqual(sync.summary.deletedCount, 1)
        XCTAssertTrue(sync.events.contains { event in
            if case .deleted(let path, _) = event {
                return path == record.identity.path
            }
            return false
        })
    }

    func testRepositoryUpdatePreservesUnknownFrontmatterFields() throws {
        let root = try TestSupport.tempDirectory(prefix: "IntegrationUnknown")
        let fileIO = TaskFileIO()
        let repository = FileTaskRepository(rootURL: root)

        let path = root.appendingPathComponent("unknown.md").path
        let markdown = """
        ---
        title: Unknown preservation
        status: todo
        created: "2026-02-26T10:00:00Z"
        source: user
        custom_field: keep-me
        nested:
          value: 42
        ---
        body
        """
        try fileIO.write(path: path, content: markdown)

        _ = try repository.update(path: path) { document in
            document.frontmatter.description = "updated"
        }

        let updatedRaw = try fileIO.read(path: path)
        XCTAssertTrue(updatedRaw.contains("custom_field: keep-me"))
        XCTAssertTrue(updatedRaw.contains("nested:"))
        XCTAssertTrue(updatedRaw.contains("value: 42"))
    }

    func testManualOrderPersistsAcrossServiceInstances() throws {
        let root = try TestSupport.tempDirectory(prefix: "IntegrationOrder")
        let repository = FileTaskRepository(rootURL: root)

        let a = try repository.create(
            document: TaskDocument(frontmatter: TestSupport.sampleFrontmatter(title: "A"), body: ""),
            preferredFilename: "a.md"
        )
        let b = try repository.create(
            document: TaskDocument(frontmatter: TestSupport.sampleFrontmatter(title: "B"), body: ""),
            preferredFilename: "b.md"
        )

        let firstService = ManualOrderService(rootURL: root)
        try firstService.saveOrder(view: .builtIn(.inbox), filenames: [b.identity.filename, a.identity.filename])

        let secondService = ManualOrderService(rootURL: root)
        let ordered = secondService.ordered(records: [a, b], view: .builtIn(.inbox))
        XCTAssertEqual(ordered.map(\.identity.filename), [b.identity.filename, a.identity.filename])
    }
}
