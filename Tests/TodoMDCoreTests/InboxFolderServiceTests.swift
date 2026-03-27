import XCTest
@testable import TodoMDCore

final class InboxFolderServiceTests: XCTestCase {
    private var rootURL: URL!
    private var inboxURL: URL!
    private var repository: FileTaskRepository!

    override func setUpWithError() throws {
        rootURL = try TestSupport.tempDirectory(prefix: "InboxFolder")
        inboxURL = rootURL.appendingPathComponent(".inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        repository = FileTaskRepository(rootURL: rootURL)
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
    }

    func testPlainMarkdownFileBecomesTaskWithDefaults() throws {
        let droppedFile = inboxURL.appendingPathComponent("buy-milk.md", isDirectory: false)
        try "Buy milk and eggs".write(to: droppedFile, atomically: true, encoding: .utf8)
        try ageFile(droppedFile, byAtLeast: 3)

        let results = try makeService().processInbox(now: Date())

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].task.frontmatter.title, "buy-milk")
        XCTAssertEqual(results[0].task.frontmatter.status, TaskStatus.todo)
        XCTAssertEqual(results[0].task.frontmatter.priority, TaskPriority.none)
        XCTAssertEqual(results[0].task.frontmatter.flagged, false)
        XCTAssertEqual(results[0].task.frontmatter.source, "inbox-drop")
        XCTAssertEqual(results[0].task.body, "Buy milk and eggs")
        XCTAssertFalse(FileManager.default.fileExists(atPath: droppedFile.path))
        XCTAssertTrue(results[0].createdPath.hasPrefix(rootURL.path))
        XCTAssertFalse(results[0].createdPath.contains("/.inbox/"))
    }

    func testPartialFrontmatterGetsRecoveredWithDefaults() throws {
        let droppedFile = inboxURL.appendingPathComponent("call-dentist.md", isDirectory: false)
        try """
        ---
        title: "Call dentist"
        tags:
          - health
        ---
        Schedule a cleaning appointment.
        """.write(to: droppedFile, atomically: true, encoding: .utf8)
        try ageFile(droppedFile, byAtLeast: 3)

        let now = Date()
        let results = try makeService().processInbox(now: now)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].task.frontmatter.title, "Call dentist")
        XCTAssertEqual(results[0].task.frontmatter.tags, ["health"])
        XCTAssertEqual(results[0].task.frontmatter.status, TaskStatus.todo)
        XCTAssertEqual(results[0].task.frontmatter.source, "inbox-drop")
        XCTAssertEqual(results[0].task.body, "Schedule a cleaning appointment.")
        XCTAssertLessThan(abs(results[0].task.frontmatter.created.timeIntervalSince(now)), 1)
    }

    func testValidFrontmatterPreservesProvidedValues() throws {
        let droppedFile = inboxURL.appendingPathComponent("perfect.md", isDirectory: false)
        try """
        ---
        title: "Already perfect"
        status: todo
        priority: high
        flagged: true
        created: "2026-03-24T10:00:00.000Z"
        source: claude-agent
        custom_field: keep-me
        ---
        This file has complete frontmatter.
        """.write(to: droppedFile, atomically: true, encoding: .utf8)
        try ageFile(droppedFile, byAtLeast: 3)

        let results = try makeService().processInbox(now: Date())
        let createdPath = try XCTUnwrap(results.first?.createdPath)
        let loaded = try repository.load(path: createdPath)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].task.frontmatter.title, "Already perfect")
        XCTAssertEqual(results[0].task.frontmatter.priority, TaskPriority.high)
        XCTAssertEqual(results[0].task.frontmatter.flagged, true)
        XCTAssertEqual(results[0].task.frontmatter.source, "claude-agent")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(results[0].task.frontmatter.created, formatter.date(from: "2026-03-24T10:00:00.000Z"))
        XCTAssertEqual(loaded.document.unknownFrontmatter["custom_field"], .string("keep-me"))
    }

    func testEmptyFileMovesToErrorsFolder() throws {
        let droppedFile = inboxURL.appendingPathComponent("empty.md", isDirectory: false)
        try "".write(to: droppedFile, atomically: true, encoding: .utf8)
        try ageFile(droppedFile, byAtLeast: 3)

        let results = try makeService().processInbox(now: Date())

        XCTAssertTrue(results.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: droppedFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: inboxURL.appendingPathComponent(".errors/empty.md").path))
    }

    func testCorruptFrontmatterMovesToErrorsFolder() throws {
        let droppedFile = inboxURL.appendingPathComponent("broken.md", isDirectory: false)
        try """
        ---
        title: Broken
        flagged: maybe
        created: "2026-03-24T10:00:00.000Z"
        source: claude-agent
        ---
        still broken
        """.write(to: droppedFile, atomically: true, encoding: .utf8)
        try ageFile(droppedFile, byAtLeast: 3)

        let results = try makeService().processInbox(now: Date())

        XCTAssertTrue(results.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: droppedFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: inboxURL.appendingPathComponent(".errors/broken.md").path))
    }

    func testRecentlyModifiedFileIsSkippedUntilNextSync() throws {
        let droppedFile = inboxURL.appendingPathComponent("fresh.md", isDirectory: false)
        try "Fresh draft".write(to: droppedFile, atomically: true, encoding: .utf8)

        let results = try makeService().processInbox(now: Date())

        XCTAssertTrue(results.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: droppedFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: inboxURL.appendingPathComponent(".errors/fresh.md").path))
    }

    func testRepositoryCreateFailureLeavesValidDropInInbox() throws {
        let droppedFile = inboxURL.appendingPathComponent("write-later.md", isDirectory: false)
        try "Write this later".write(to: droppedFile, atomically: true, encoding: .utf8)
        try ageFile(droppedFile, byAtLeast: 3)

        let service = InboxFolderService(
            inboxURL: inboxURL,
            repository: FailingCreateRepository()
        )

        XCTAssertThrowsError(try service.processInbox(now: Date())) { error in
            XCTAssertEqual(error as? TaskError, .ioFailure("simulated create failure"))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: droppedFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: inboxURL.appendingPathComponent(".errors/write-later.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: inboxURL.appendingPathComponent(".processing/write-later.md").path))
    }

    func testDeleteFailureAfterCreateDoesNotReimportValidDrop() throws {
        let droppedFile = inboxURL.appendingPathComponent("keep-source.md", isDirectory: false)
        try "Keep source file".write(to: droppedFile, atomically: true, encoding: .utf8)
        try ageFile(droppedFile, byAtLeast: 3)

        let service = InboxFolderService(
            inboxURL: inboxURL,
            repository: repository,
            deleteInboxFile: { path in
                throw TaskError.ioFailure("Failed to delete file at \(path): simulated delete failure")
            }
        )

        let firstResults = try service.processInbox(now: Date())
        let secondResults = try service.processInbox(now: Date().addingTimeInterval(3))

        XCTAssertEqual(firstResults.count, 1)
        XCTAssertTrue(secondResults.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: droppedFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: inboxURL.appendingPathComponent(".errors/keep-source.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: inboxURL.appendingPathComponent(".processing/keep-source.md").path))

        let createdTaskURLs = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "md" }
        XCTAssertEqual(createdTaskURLs.count, 1)
    }

    func testQuarantineFailureDoesNotStopLaterValidIngest() throws {
        let invalidFile = inboxURL.appendingPathComponent("broken.md", isDirectory: false)
        try """
        ---
        title: Broken
        flagged: maybe
        ---
        """.write(to: invalidFile, atomically: true, encoding: .utf8)
        try ageFile(invalidFile, byAtLeast: 3)

        let validFile = inboxURL.appendingPathComponent("follow-up.md", isDirectory: false)
        try "Follow up".write(to: validFile, atomically: true, encoding: .utf8)
        try ageFile(validFile, byAtLeast: 3)

        let service = InboxFolderService(
            inboxURL: inboxURL,
            repository: repository,
            deleteInboxFile: nil,
            quarantineInvalidInboxFile: { _ in
                throw TaskError.ioFailure("simulated quarantine failure")
            }
        )

        let results = try service.processInbox(now: Date())

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].task.frontmatter.title, "follow-up")
        XCTAssertTrue(FileManager.default.fileExists(atPath: invalidFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: inboxURL.appendingPathComponent(".errors/broken.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: validFile.path))
    }

    private func makeService() -> InboxFolderService {
        InboxFolderService(inboxURL: inboxURL, repository: repository)
    }

    private func ageFile(_ url: URL, byAtLeast seconds: TimeInterval) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-seconds)],
            ofItemAtPath: url.path
        )
    }
}

private final class FailingCreateRepository: TaskRepository {
    func create(document: TaskDocument, preferredFilename: String?) throws -> TaskRecord {
        throw TaskError.ioFailure("simulated create failure")
    }

    func update(path: String, mutate: (inout TaskDocument) throws -> Void) throws -> TaskRecord {
        fatalError("unused")
    }

    func delete(path: String) throws {
        fatalError("unused")
    }

    func load(path: String) throws -> TaskRecord {
        fatalError("unused")
    }

    func loadAll() throws -> [TaskRecord] {
        fatalError("unused")
    }

    func complete(path: String, at completionTime: Date, completedBy: String?) throws -> TaskRecord {
        fatalError("unused")
    }

    func completeRepeating(path: String, at completionTime: Date, completedBy: String?) throws -> (completed: TaskRecord, next: TaskRecord) {
        fatalError("unused")
    }
}
