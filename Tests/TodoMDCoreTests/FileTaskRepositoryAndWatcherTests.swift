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

    func testRepositoryCreateAssignsStableTaskURL() throws {
        let root = try TestSupport.tempDirectory(prefix: "RepositoryURL")
        let repository = FileTaskRepository(rootURL: root)

        let created = try repository.create(
            document: .init(frontmatter: TestSupport.sampleFrontmatter(title: "Task A"), body: "Body A"),
            preferredFilename: "task-a.md"
        )

        let ref = try XCTUnwrap(created.document.frontmatter.ref)
        XCTAssertEqual(created.document.frontmatter.url, "todomd://task/\(ref)")

        let loaded = try repository.load(path: created.identity.path)
        XCTAssertEqual(loaded.document.frontmatter.url, "todomd://task/\(ref)")
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

#if os(macOS)
    func testFileWatcherIngestsExternallyCreatedTaskDuringIncrementalScan() async throws {
        let root = try TestSupport.tempDirectory(prefix: "WatcherIncrementalCreate")
        let repository = FileTaskRepository(rootURL: root)
        let watcher = FileWatcherService(rootURL: root, repository: repository)

        for index in 0..<129 {
            _ = try repository.create(
                document: .init(
                    frontmatter: TestSupport.sampleFrontmatter(title: "Seed \(index)", source: "seed"),
                    body: ""
                ),
                preferredFilename: String(format: "seed-%03d.md", index)
            )
        }

        _ = try watcher.synchronize(now: Date())

        let createdURL = root.appendingPathComponent("external-agent-task.md")
        try """
        ---
        title: External Agent Task
        status: todo
        priority: none
        flagged: false
        created: "2026-03-20T12:00:00.000Z"
        source: codex-agent
        ---
        """.write(to: createdURL, atomically: true, encoding: .utf8)

        var ingestedPaths: Set<String> = []
        var ingestedRecords: [TaskRecord] = []

        for attempt in 0..<20 {
            if attempt > 0 {
                try await Task.sleep(nanoseconds: 50_000_000)
            }

            let sync = try watcher.synchronize(now: Date().addingTimeInterval(Double(attempt + 1)))
            ingestedRecords = sync.records
            ingestedPaths = Set(sync.records.map(\.identity.path))

            if ingestedPaths.contains(createdURL.path) {
                break
            }
        }

        XCTAssertTrue(ingestedPaths.contains(createdURL.path))
        XCTAssertEqual(
            ingestedRecords.first(where: { $0.identity.path == createdURL.path })?.document.frontmatter.title,
            "External Agent Task"
        )
    }
#endif

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

    func testFileWatcherSuppressesNewSelfWrittenFilesUntilCallerUpsertsThem() throws {
        let root = try TestSupport.tempDirectory(prefix: "WatcherSelfWriteCreate")
        let repository = FileTaskRepository(rootURL: root)
        let watcher = FileWatcherService(rootURL: root, repository: repository)
        let fileIO = TaskFileIO()

        let created = try repository.create(
            document: .init(frontmatter: TestSupport.sampleFrontmatter(title: "Imported"), body: ""),
            preferredFilename: "imported.md"
        )

        let fingerprint = try fileIO.fingerprint(for: created.identity.path)
        watcher.markSelfWrite(path: created.identity.path, modificationDate: fingerprint.modificationDate)

        let sync = try watcher.synchronize(now: Date())

        XCTAssertEqual(sync.summary.ingestedCount, 0)
        XCTAssertTrue(sync.records.isEmpty)
        XCTAssertFalse(sync.events.contains { event in
            if case .created(let path, _, _) = event { return path == created.identity.path }
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

    func testFileWatcherIgnoresAgentsMarkdownFile() throws {
        let root = try TestSupport.tempDirectory(prefix: "WatcherIgnoresAgents")
        let repository = FileTaskRepository(rootURL: root)
        let watcher = FileWatcherService(rootURL: root, repository: repository)

        let agentsURL = root.appendingPathComponent("AGENTS.md")
        try """
        # Workspace instructions

        This is not a task file.
        """.write(to: agentsURL, atomically: true, encoding: .utf8)

        let sync = try watcher.synchronize(now: Date())

        XCTAssertEqual(sync.summary.failedCount, 0)
        XCTAssertTrue(sync.events.isEmpty)
        XCTAssertTrue(watcher.parseDiagnostics.isEmpty)
    }

    func testFileWatcherProcessesInboxFolderAutomatically() throws {
        let root = try TestSupport.tempDirectory(prefix: "WatcherInbox")
        let repository = FileTaskRepository(rootURL: root)
        let watcher = FileWatcherService(rootURL: root, repository: repository)
        let inboxURL = root.appendingPathComponent(".inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)

        let droppedFile = inboxURL.appendingPathComponent("buy-milk.md", isDirectory: false)
        try "Buy milk and eggs".write(to: droppedFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-3)],
            ofItemAtPath: droppedFile.path
        )

        let sync = try watcher.synchronize(now: Date())

        XCTAssertEqual(sync.summary.ingestedCount, 1)
        XCTAssertEqual(sync.records.count, 1)
        XCTAssertEqual(sync.records[0].document.frontmatter.source, "inbox-drop")
        XCTAssertEqual(sync.records[0].document.frontmatter.title, "buy-milk")
        XCTAssertFalse(FileManager.default.fileExists(atPath: droppedFile.path))
    }

    func testFileWatcherContinuesRefreshWhenInboxQuarantineFails() throws {
        let root = try TestSupport.tempDirectory(prefix: "WatcherInboxQuarantineFailure")
        let repository = FileTaskRepository(rootURL: root)
        let watcher = FileWatcherService(rootURL: root, repository: repository)
        let inboxURL = root.appendingPathComponent(".inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)

        let errorsURL = inboxURL.appendingPathComponent(".errors", isDirectory: false)
        try "not a directory".write(to: errorsURL, atomically: true, encoding: .utf8)

        let invalidFile = inboxURL.appendingPathComponent("broken.md", isDirectory: false)
        try """
        ---
        title: Broken
        flagged: maybe
        ---
        """.write(to: invalidFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-3)],
            ofItemAtPath: invalidFile.path
        )

        _ = try repository.create(
            document: .init(frontmatter: TestSupport.sampleFrontmatter(title: "Normal"), body: ""),
            preferredFilename: "normal.md"
        )

        let sync = try watcher.synchronize(now: Date())

        XCTAssertEqual(sync.summary.ingestedCount, 1)
        XCTAssertEqual(sync.records.count, 1)
        XCTAssertEqual(sync.records[0].document.frontmatter.title, "Normal")
        XCTAssertTrue(FileManager.default.fileExists(atPath: invalidFile.path))
    }

    func testFileWatcherReportsParseFailureReason() throws {
        let root = try TestSupport.tempDirectory(prefix: "WatcherParseFailureReason")
        let repository = FileTaskRepository(rootURL: root)
        let watcher = FileWatcherService(rootURL: root, repository: repository)

        let invalidURL = root.appendingPathComponent("invalid.md")
        try """
        ---
        title: Invalid
        flagged: maybe
        created: 2026-03-08T10:00:00Z
        source: codex-agent
        ---
        """.write(to: invalidURL, atomically: true, encoding: .utf8)

        let sync = try watcher.synchronize(now: Date())

        XCTAssertEqual(sync.summary.failedCount, 1)
        XCTAssertEqual(watcher.parseDiagnostics.count, 1)
        XCTAssertEqual(watcher.parseDiagnostics.first?.reason, "Field flagged must be a boolean")

        guard let event = sync.events.first else {
            return XCTFail("Expected an unparseable event")
        }

        switch event {
        case .unparseable(let path, let reason, _):
            XCTAssertEqual(path, invalidURL.path)
            XCTAssertEqual(reason, "Field flagged must be a boolean")
        default:
            XCTFail("Expected an unparseable event")
        }
    }

    func testSnapshotHydrationPrimesWatcherWithoutColdReparse() throws {
        let root = try TestSupport.tempDirectory(prefix: "SnapshotPrime")
        let repository = FileTaskRepository(rootURL: root)
        let snapshotStore = try makeSnapshotStore()

        _ = try repository.create(
            document: .init(frontmatter: TestSupport.sampleFrontmatter(title: "One"), body: "body-1"),
            preferredFilename: "one.md"
        )
        _ = try repository.create(
            document: .init(frontmatter: TestSupport.sampleFrontmatter(title: "Two"), body: "body-2"),
            preferredFilename: "two.md"
        )

        let hydration = try snapshotStore.hydrate(rootURL: root, repository: repository)
        let watcher = FileWatcherService(rootURL: root, repository: repository)
        watcher.prime(fingerprints: hydration.fingerprints)

        let sync = try watcher.synchronize(now: Date())
        XCTAssertEqual(hydration.records.count, 2)
        XCTAssertEqual(sync.summary.ingestedCount, 0)
    }

    func testSnapshotHydrationReloadsChangedFiles() throws {
        let root = try TestSupport.tempDirectory(prefix: "SnapshotRefresh")
        let repository = FileTaskRepository(rootURL: root)
        let snapshotStore = try makeSnapshotStore()

        let created = try repository.create(
            document: .init(frontmatter: TestSupport.sampleFrontmatter(title: "Before"), body: "body"),
            preferredFilename: "task.md"
        )

        _ = try snapshotStore.hydrate(rootURL: root, repository: repository)

        _ = try repository.update(path: created.identity.path) { document in
            document.frontmatter.title = "After"
        }

        let refreshed = try snapshotStore.hydrate(rootURL: root, repository: repository)
        XCTAssertEqual(refreshed.records.first?.document.frontmatter.title, "After")
    }

    func testSnapshotDeltaPersistenceUpdatesAndDeletesWithoutFullRewrite() throws {
        let root = try TestSupport.tempDirectory(prefix: "SnapshotDelta")
        let repository = FileTaskRepository(rootURL: root)
        let snapshotStore = try makeSnapshotStore()
        let fileIO = TaskFileIO()

        let first = try repository.create(
            document: .init(frontmatter: TestSupport.sampleFrontmatter(title: "First"), body: "body-1"),
            preferredFilename: "first.md"
        )
        let second = try repository.create(
            document: .init(frontmatter: TestSupport.sampleFrontmatter(title: "Second"), body: "body-2"),
            preferredFilename: "second.md"
        )

        _ = try snapshotStore.hydrate(rootURL: root, repository: repository)

        let updated = try repository.update(path: first.identity.path) { document in
            document.frontmatter.title = "First Updated"
        }
        try repository.delete(path: second.identity.path)

        try snapshotStore.applyDelta(
            upsertedRecords: [updated],
            deletedPaths: Set([second.identity.path]),
            fingerprints: try fileIO.enumerateMarkdownFingerprints(rootURL: root),
            rootURL: root
        )

        let refreshed = try snapshotStore.hydrate(rootURL: root, repository: repository)
        XCTAssertEqual(refreshed.records.map(\.document.frontmatter.title), ["First Updated"])
    }

    func testOptimisticSnapshotHydrationRestoresPersistedMetadata() throws {
        let root = try TestSupport.tempDirectory(prefix: "SnapshotOptimistic")
        let repository = FileTaskRepository(rootURL: root)
        let snapshotStore = try makeSnapshotStore()

        _ = try repository.create(
            document: .init(frontmatter: TestSupport.sampleFrontmatter(title: "One", source: "agent"), body: "body-1"),
            preferredFilename: "one.md"
        )
        _ = try repository.create(
            document: .init(frontmatter: TestSupport.sampleFrontmatter(title: "Two", source: "agent"), body: "body-2"),
            preferredFilename: "two.md"
        )

        _ = try snapshotStore.hydrate(rootURL: root, repository: repository, mode: .validated)
        let optimistic = try snapshotStore.hydrate(rootURL: root, repository: repository, mode: .optimistic)

        XCTAssertEqual(optimistic.records.count, 2)
        XCTAssertEqual(Set(optimistic.metadataEntries.map(\.title)), Set(["One", "Two"]))
        XCTAssertEqual(optimistic.fingerprints.count, 2)
    }

    func testRepeatedHydrationPreservesTaskURL() throws {
        let root = try TestSupport.tempDirectory(prefix: "SnapshotOptimisticURL")
        let repository = FileTaskRepository(rootURL: root)
        let snapshotStore = try makeSnapshotStore()

        let created = try repository.create(
            document: .init(frontmatter: TestSupport.sampleFrontmatter(title: "Linked", source: "agent"), body: "body"),
            preferredFilename: "linked.md"
        )

        let expectedURL = try XCTUnwrap(created.document.frontmatter.url)

        _ = try snapshotStore.hydrate(rootURL: root, repository: repository, mode: .validated)
        let optimistic = try snapshotStore.hydrate(rootURL: root, repository: repository, mode: .optimistic)

        XCTAssertEqual(optimistic.records.count, 1)
        XCTAssertEqual(optimistic.records.first?.document.frontmatter.url, expectedURL)
    }

    func testSnapshotCacheFilesPersistTaskURL() throws {
        let root = try TestSupport.tempDirectory(prefix: "SnapshotCacheURL")
        let cacheBaseURL = try TestSupport.tempDirectory(prefix: "SnapshotCacheBase")
        let repository = FileTaskRepository(rootURL: root)
        let snapshotStore = TaskRecordSnapshotStore(cacheBaseURL: cacheBaseURL)

        let created = try repository.create(
            document: .init(frontmatter: TestSupport.sampleFrontmatter(title: "Linked", source: "agent"), body: "body"),
            preferredFilename: "linked.md"
        )

        let expectedURL = try XCTUnwrap(created.document.frontmatter.url)

        _ = try snapshotStore.hydrate(rootURL: root, repository: repository, mode: .validated)

        let cacheDirectory = snapshotDirectory(rootURL: root, cacheBaseURL: cacheBaseURL)
        let launchStateURL = cacheDirectory.appendingPathComponent("launch-state.json", isDirectory: false)
        let launchStateData = try Data(contentsOf: launchStateURL)
        let launchStateObject = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: launchStateData, options: [], format: nil) as? [String: Any]
        )
        let launchRecords = try XCTUnwrap(launchStateObject["records"] as? [[String: Any]])
        let launchFrontmatter = try XCTUnwrap(launchRecords.first)
        XCTAssertEqual(launchFrontmatter["url"] as? String, expectedURL)

        let entryURL = cacheDirectory
            .appendingPathComponent("entries", isDirectory: true)
            .appendingPathComponent("\(snapshotCacheKey(for: created.identity.path)).json", isDirectory: false)
        let entryData = try Data(contentsOf: entryURL)
        let entryObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: entryData) as? [String: Any])
        XCTAssertEqual(entryObject["url"] as? String, expectedURL)
    }

    func testOptimisticSnapshotHydrationFallsBackWhenDirectoryFingerprintChanges() throws {
        let root = try TestSupport.tempDirectory(prefix: "SnapshotOptimisticDirty")
        let repository = FileTaskRepository(rootURL: root)
        let snapshotStore = try makeSnapshotStore()

        _ = try repository.create(
            document: .init(frontmatter: TestSupport.sampleFrontmatter(title: "One", source: "agent"), body: "body-1"),
            preferredFilename: "bucket-000/one.md"
        )

        _ = try snapshotStore.hydrate(rootURL: root, repository: repository, mode: .validated)

        _ = try repository.create(
            document: .init(frontmatter: TestSupport.sampleFrontmatter(title: "Two", source: "agent"), body: "body-2"),
            preferredFilename: "bucket-000/two.md"
        )

        let refreshed = try snapshotStore.hydrate(rootURL: root, repository: repository, mode: .optimistic)

        XCTAssertEqual(Set(refreshed.records.map(\.document.frontmatter.title)), Set(["One", "Two"]))
        XCTAssertFalse(refreshed.requiresValidation)
    }

    private func makeSnapshotStore() throws -> TaskRecordSnapshotStore {
        TaskRecordSnapshotStore(cacheBaseURL: try TestSupport.tempDirectory(prefix: "SnapshotCache"))
    }

    private func snapshotDirectory(rootURL: URL, cacheBaseURL: URL) -> URL {
        cacheBaseURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .appendingPathComponent("TodoMD", isDirectory: true)
            .appendingPathComponent("task-record-snapshot-v3", isDirectory: true)
            .appendingPathComponent(snapshotCacheKey(for: rootURL.standardizedFileURL.resolvingSymlinksInPath().path), isDirectory: true)
    }

    private func snapshotCacheKey(for path: String) -> String {
        let prime: UInt64 = 1_099_511_628_211
        var hash: UInt64 = 14_695_981_039_346_656_037

        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash &*= prime
        }

        return String(format: "%016llx", hash)
    }
}
