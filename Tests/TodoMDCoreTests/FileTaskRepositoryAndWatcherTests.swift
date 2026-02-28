import XCTest
@testable import TodoMDCore

final class FileTaskRepositoryAndWatcherTests: XCTestCase {
    func testRepositoryCreateLoadUpdateDelete() throws {
        let root = try TestSupport.tempDirectory(prefix: "Repository")
        let repository = FileTaskRepository(rootURL: root)

        let frontmatter = TestSupport.sampleFrontmatter(title: "Task A")
        let document = TaskDocument(frontmatter: frontmatter, body: "Body A")
        let created = try repository.create(document: document, preferredFilename: nil)
        XCTAssertTrue(created.identity.filename.hasSuffix(".md"))

        let loaded = try repository.load(path: created.identity.path)
        XCTAssertEqual(loaded.document.frontmatter.title, "Task A")
        XCTAssertNotNil(loaded.document.frontmatter.ref)

        let updated = try repository.update(path: created.identity.path) { doc in
            doc.frontmatter.title = "Task B"
        }
        XCTAssertEqual(updated.document.frontmatter.title, "Task B")

        try repository.delete(path: created.identity.path)
        XCTAssertThrowsError(try repository.load(path: created.identity.path))
    }

    func testCompleteRepeatingSpawnsNextTask() throws {
        let root = try TestSupport.tempDirectory(prefix: "Repeating")
        let repository = FileTaskRepository(rootURL: root)
        var frontmatter = TestSupport.sampleFrontmatter(title: "Repeat", due: try LocalDate(isoDate: "2025-03-01"))
        frontmatter.recurrence = "FREQ=DAILY"

        let created = try repository.create(document: .init(frontmatter: frontmatter, body: ""), preferredFilename: nil)
        let result = try repository.completeRepeating(path: created.identity.path, at: Date(timeIntervalSince1970: 1_700_000_100), completedBy: "codex")

        XCTAssertEqual(result.completed.document.frontmatter.status, .done)
        XCTAssertEqual(result.completed.document.frontmatter.completedBy, "codex")
        XCTAssertNil(result.completed.document.frontmatter.recurrence)
        XCTAssertEqual(result.next.document.frontmatter.status, .todo)
        XCTAssertNil(result.next.document.frontmatter.completedBy)
        XCTAssertEqual(result.next.document.frontmatter.due?.isoString, "2025-03-02")
    }

    func testFileWatcherDetectsCreateModifyDeleteAndRateLimit() throws {
        let root = try TestSupport.tempDirectory(prefix: "Watcher")
        let repository = FileTaskRepository(rootURL: root)
        let watcher = FileWatcherService(rootURL: root, repository: repository, rateLimitPolicy: .init(threshold: 2, windowSeconds: 60))

        let first = TestSupport.sampleFrontmatter(title: "One", source: "agent")
        let second = TestSupport.sampleFrontmatter(title: "Two", source: "agent")
        let third = TestSupport.sampleFrontmatter(title: "Three", source: "agent")

        _ = try repository.create(document: .init(frontmatter: first, body: ""), preferredFilename: "a.md")
        _ = try repository.create(document: .init(frontmatter: second, body: ""), preferredFilename: "b.md")
        _ = try repository.create(document: .init(frontmatter: third, body: ""), preferredFilename: "c.md")

        let sync1 = try watcher.synchronize(now: Date())
        XCTAssertEqual(sync1.summary.ingestedCount, 3)
        XCTAssertNotNil(watcher.lastPerformance)
        XCTAssertGreaterThanOrEqual(watcher.lastPerformance?.enumerateMilliseconds ?? -1, 0)
        XCTAssertGreaterThanOrEqual(watcher.lastPerformance?.parseMilliseconds ?? -1, 0)
        XCTAssertTrue(sync1.events.contains { event in
            if case .rateLimitedBatch = event { return true }
            return false
        })

        let aPath = root.appendingPathComponent("a.md").path
        _ = try repository.update(path: aPath) { document in
            document.frontmatter.title = "One Updated"
        }

        let sync2 = try watcher.synchronize(now: Date().addingTimeInterval(1))
        XCTAssertTrue(sync2.events.contains { event in
            if case .modified(let path, _, _) = event { return path == aPath }
            return false
        })

        try repository.delete(path: aPath)
        let sync3 = try watcher.synchronize(now: Date().addingTimeInterval(2))
        XCTAssertTrue(sync3.events.contains { event in
            if case .deleted(let path, _) = event { return path == aPath }
            return false
        })
    }

    func testFileWatcherSuppressesSelfWriteEchoForRecentModification() throws {
        let root = try TestSupport.tempDirectory(prefix: "WatcherSelfWrite")
        let repository = FileTaskRepository(rootURL: root)
        let watcher = FileWatcherService(rootURL: root, repository: repository)
        let fileIO = TaskFileIO()

        let frontmatter = TestSupport.sampleFrontmatter(title: "Task")
        _ = try repository.create(document: .init(frontmatter: frontmatter, body: ""), preferredFilename: "self.md")
        _ = try watcher.synchronize(now: Date())

        let path = root.appendingPathComponent("self.md").path
        _ = try repository.update(path: path) { doc in
            doc.frontmatter.title = "Task Updated"
        }

        let fingerprint = try fileIO.fingerprint(for: path)
        watcher.markSelfWrite(path: path, modificationDate: fingerprint.modificationDate)

        let sync = try watcher.synchronize(now: Date())
        XCTAssertFalse(sync.events.contains { event in
            if case .modified(let modifiedPath, _, _) = event { return modifiedPath == path }
            return false
        })
    }

    func testFileWatcherAppliesRollingWindowBurstThreshold() throws {
        let root = try TestSupport.tempDirectory(prefix: "WatcherRollingWindow")
        let repository = FileTaskRepository(rootURL: root)
        let watcher = FileWatcherService(
            rootURL: root,
            repository: repository,
            rateLimitPolicy: .init(threshold: 2, windowSeconds: 60)
        )

        _ = try repository.create(document: .init(frontmatter: TestSupport.sampleFrontmatter(title: "A", source: "agent"), body: ""), preferredFilename: "a.md")
        _ = try repository.create(document: .init(frontmatter: TestSupport.sampleFrontmatter(title: "B", source: "agent"), body: ""), preferredFilename: "b.md")

        let firstSync = try watcher.synchronize(now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertFalse(firstSync.events.contains { event in
            if case .rateLimitedBatch = event { return true }
            return false
        })

        _ = try repository.create(document: .init(frontmatter: TestSupport.sampleFrontmatter(title: "C", source: "agent"), body: ""), preferredFilename: "c.md")
        let secondSync = try watcher.synchronize(now: Date(timeIntervalSince1970: 1_700_000_030))
        XCTAssertTrue(secondSync.events.contains { event in
            if case .rateLimitedBatch = event { return true }
            return false
        })

        _ = try repository.create(document: .init(frontmatter: TestSupport.sampleFrontmatter(title: "D", source: "agent"), body: ""), preferredFilename: "d.md")
        let thirdSync = try watcher.synchronize(now: Date(timeIntervalSince1970: 1_700_000_090))
        XCTAssertFalse(thirdSync.events.contains { event in
            if case .rateLimitedBatch = event { return true }
            return false
        })
    }
}
