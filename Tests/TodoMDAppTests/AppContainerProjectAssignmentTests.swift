import Foundation
import Testing
@testable import TodoMDApp

@Suite(.serialized)
@MainActor
struct AppContainerProjectAssignmentTests {
    @Test("Assigning a due date refreshes in-memory state and persists to disk")
    func setDueAndRecurrenceRefreshesInMemoryState() throws {
        let root = try makeTempDirectory()
        let repository = FileTaskRepository(rootURL: root)
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let inboxTask = try repository.create(
            document: .init(
                frontmatter: TaskFrontmatterV1(
                    title: "Inbox task",
                    status: .todo,
                    priority: .none,
                    flagged: false,
                    tags: [],
                    created: referenceDate,
                    modified: referenceDate,
                    source: "user"
                ),
                body: "body"
            ),
            preferredFilename: "inbox-task.md"
        )

        let originalOverride = ProcessInfo.processInfo.environment["TODOMD_STORAGE_OVERRIDE_PATH"]
        setenv("TODOMD_STORAGE_OVERRIDE_PATH", root.path, 1)
        defer {
            if let originalOverride {
                setenv("TODOMD_STORAGE_OVERRIDE_PATH", originalOverride, 1)
            } else {
                unsetenv("TODOMD_STORAGE_OVERRIDE_PATH")
            }
        }

        let container = AppContainer()
        container.selectedView = .builtIn(.inbox)
        container.refresh(forceFullScan: true)

        let dueDate = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 20)))

        #expect(container.setDueAndRecurrence(path: inboxTask.identity.path, date: dueDate, recurrence: "FREQ=WEEKLY"))
        #expect(container.record(for: inboxTask.identity.path)?.document.frontmatter.due?.isoString == "2026-03-20")
        #expect(container.record(for: inboxTask.identity.path)?.document.frontmatter.recurrence == "FREQ=WEEKLY")

        let persisted = try repository.load(path: inboxTask.identity.path)
        #expect(persisted.document.frontmatter.due?.isoString == "2026-03-20")
        #expect(persisted.document.frontmatter.recurrence == "FREQ=WEEKLY")
    }

    @Test("Assigning tags refreshes in-memory state and persists to disk")
    func setTagsRefreshesInMemoryState() throws {
        let root = try makeTempDirectory()
        let repository = FileTaskRepository(rootURL: root)
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let inboxTask = try repository.create(
            document: .init(
                frontmatter: TaskFrontmatterV1(
                    title: "Inbox task",
                    status: .todo,
                    priority: .none,
                    flagged: false,
                    tags: [],
                    created: referenceDate,
                    modified: referenceDate,
                    source: "user"
                ),
                body: "body"
            ),
            preferredFilename: "inbox-task.md"
        )

        let originalOverride = ProcessInfo.processInfo.environment["TODOMD_STORAGE_OVERRIDE_PATH"]
        setenv("TODOMD_STORAGE_OVERRIDE_PATH", root.path, 1)
        defer {
            if let originalOverride {
                setenv("TODOMD_STORAGE_OVERRIDE_PATH", originalOverride, 1)
            } else {
                unsetenv("TODOMD_STORAGE_OVERRIDE_PATH")
            }
        }

        let container = AppContainer()
        container.selectedView = .builtIn(.inbox)
        container.refresh(forceFullScan: true)

        #expect(container.setTags(path: inboxTask.identity.path, tags: ["work", "docs"]))
        #expect(container.record(for: inboxTask.identity.path)?.document.frontmatter.tags == ["work", "docs"])

        let persisted = try repository.load(path: inboxTask.identity.path)
        #expect(persisted.document.frontmatter.tags == ["work", "docs"])
    }

    @Test("Assigning a project updates inbox filtering immediately")
    func addToProjectRefreshesInMemoryState() throws {
        let root = try makeTempDirectory()
        let repository = FileTaskRepository(rootURL: root)
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let existingProject = try repository.create(
            document: .init(
                frontmatter: TaskFrontmatterV1(
                    title: "Seed project",
                    status: .todo,
                    priority: .none,
                    flagged: false,
                    area: "Work",
                    project: "Launch",
                    tags: [],
                    created: referenceDate,
                    modified: referenceDate,
                    source: "user"
                ),
                body: "seed"
            ),
            preferredFilename: "seed-project.md"
        )
        let inboxTask = try repository.create(
            document: .init(
                frontmatter: TaskFrontmatterV1(
                    title: "Inbox task",
                    status: .todo,
                    priority: .none,
                    flagged: false,
                    tags: [],
                    created: referenceDate,
                    modified: referenceDate,
                    source: "user"
                ),
                body: "body"
            ),
            preferredFilename: "inbox-task.md"
        )

        let originalOverride = ProcessInfo.processInfo.environment["TODOMD_STORAGE_OVERRIDE_PATH"]
        setenv("TODOMD_STORAGE_OVERRIDE_PATH", root.path, 1)
        defer {
            if let originalOverride {
                setenv("TODOMD_STORAGE_OVERRIDE_PATH", originalOverride, 1)
            } else {
                unsetenv("TODOMD_STORAGE_OVERRIDE_PATH")
            }
        }

        let container = AppContainer()
        container.selectedView = .builtIn(.inbox)
        container.refresh(forceFullScan: true)

        #expect(container.filteredRecords().contains { $0.identity.path == inboxTask.identity.path })
        #expect(container.addToProject(path: inboxTask.identity.path, project: existingProject.document.frontmatter.project ?? "Launch"))

        #expect(container.filteredRecords().contains { $0.identity.path == inboxTask.identity.path } == false)
        #expect(container.record(for: inboxTask.identity.path)?.document.frontmatter.project == "Launch")
        #expect(container.record(for: inboxTask.identity.path)?.document.frontmatter.area == "Work")

        let persisted = try repository.load(path: inboxTask.identity.path)
        #expect(persisted.document.frontmatter.project == "Launch")
        #expect(persisted.document.frontmatter.area == "Work")
    }

    @Test("Quick entry strips natural-language dates from the saved title while persisting the due date")
    func quickEntryStripsNaturalLanguageDateFromSavedTitle() async throws {
        let root = try makeTempDirectory()
        let repository = FileTaskRepository(rootURL: root)

        let originalOverride = ProcessInfo.processInfo.environment["TODOMD_STORAGE_OVERRIDE_PATH"]
        setenv("TODOMD_STORAGE_OVERRIDE_PATH", root.path, 1)
        defer {
            if let originalOverride {
                setenv("TODOMD_STORAGE_OVERRIDE_PATH", originalOverride, 1)
            } else {
                unsetenv("TODOMD_STORAGE_OVERRIDE_PATH")
            }
        }

        let container = AppContainer()

        let title = "Buy gum due on march 20 2026"
        #expect(container.createTask(fromQuickEntryText: title))

        let persisted = try await waitForSingleRecord(in: repository)
        #expect(persisted.document.frontmatter.title == "Buy gum")
        #expect(persisted.document.frontmatter.due?.isoString == "2026-03-20")
    }

    @Test("Editing a title with a natural-language date keeps the title and updates the due date")
    func updateTaskPreservesNaturalLanguageTitleWhileApplyingDue() throws {
        let root = try makeTempDirectory()
        let repository = FileTaskRepository(rootURL: root)
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let inboxTask = try repository.create(
            document: .init(
                frontmatter: TaskFrontmatterV1(
                    title: "Buy gum",
                    status: .todo,
                    priority: .none,
                    flagged: false,
                    tags: [],
                    created: referenceDate,
                    modified: referenceDate,
                    source: "user"
                ),
                body: ""
            ),
            preferredFilename: "buy-gum.md"
        )

        let originalOverride = ProcessInfo.processInfo.environment["TODOMD_STORAGE_OVERRIDE_PATH"]
        setenv("TODOMD_STORAGE_OVERRIDE_PATH", root.path, 1)
        defer {
            if let originalOverride {
                setenv("TODOMD_STORAGE_OVERRIDE_PATH", originalOverride, 1)
            } else {
                unsetenv("TODOMD_STORAGE_OVERRIDE_PATH")
            }
        }

        let container = AppContainer()
        container.selectedView = .builtIn(.inbox)
        container.refresh(forceFullScan: true)

        var editState = try #require(container.makeEditState(path: inboxTask.identity.path))
        editState.title = "Buy gum due on march 20 2026"

        #expect(container.updateTask(path: inboxTask.identity.path, editState: editState))
        #expect(container.record(for: inboxTask.identity.path)?.document.frontmatter.title == "Buy gum due on march 20 2026")
        #expect(container.record(for: inboxTask.identity.path)?.document.frontmatter.due?.isoString == "2026-03-20")

        let persisted = try repository.load(path: inboxTask.identity.path)
        #expect(persisted.document.frontmatter.title == "Buy gum due on march 20 2026")
        #expect(persisted.document.frontmatter.due?.isoString == "2026-03-20")
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoMDAppTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func waitForSingleRecord(
        in repository: FileTaskRepository,
        timeoutNanoseconds: UInt64 = 2_000_000_000
    ) async throws -> TaskRecord {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            let records = try repository.loadAll()
            if let record = records.first, records.count == 1 {
                return record
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        throw TimeoutError()
    }
}

private struct TimeoutError: Error {}
