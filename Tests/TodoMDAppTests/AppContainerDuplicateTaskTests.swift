import Foundation
import Testing
@testable import TodoMDApp

@Suite(.serialized)
@MainActor
struct AppContainerDuplicateTaskTests {
    @Test("Duplicating a completed task resets status and date fields but keeps other content")
    func duplicateCompletedTaskResetsDateAndCompletionFields() throws {
        let root = try makeTempDirectory()
        let repository = FileTaskRepository(rootURL: root)
        let originalCreated = Date(timeIntervalSince1970: 1_700_000_000)
        let originalModified = Date(timeIntervalSince1970: 1_700_100_000)
        let originalCompleted = Date(timeIntervalSince1970: 1_700_200_000)
        let originalDue = try LocalDate(isoDate: "2026-03-20")
        let originalDueTime = try LocalTime(isoTime: "08:30")
        let originalDefer = try LocalDate(isoDate: "2026-03-21")
        let originalScheduled = try LocalDate(isoDate: "2026-03-22")
        let originalScheduledTime = try LocalTime(isoTime: "19:15")

        let sourceRecord = try repository.create(
            document: .init(
                frontmatter: TaskFrontmatterV1(
                    ref: "t-abcd",
                    title: "Renew passport",
                    status: .done,
                    due: originalDue,
                    dueTime: originalDueTime,
                    persistentReminder: true,
                    defer: originalDefer,
                    scheduled: originalScheduled,
                    scheduledTime: originalScheduledTime,
                    priority: .high,
                    flagged: true,
                    area: "Travel",
                    project: "Vacation",
                    tags: ["docs", "urgent"],
                    recurrence: "FREQ=WEEKLY",
                    estimatedMinutes: 45,
                    description: "Bring printed forms",
                    locationReminder: .init(
                        name: "Home",
                        latitude: 40.0,
                        longitude: -73.0,
                        radiusMeters: 150,
                        trigger: .onArrival
                    ),
                    created: originalCreated,
                    modified: originalModified,
                    completed: originalCompleted,
                    assignee: "Hans",
                    completedBy: "user",
                    blockedBy: .refs(["t-dead"]),
                    source: "user"
                ),
                body: "Checklist body",
                unknownFrontmatter: ["custom_field": .string("keep-me")]
            ),
            preferredFilename: "renew-passport.md"
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

        let duplicationStart = Date()
        let duplicate = try #require(container.duplicateTask(path: sourceRecord.identity.path))
        let persistedDuplicate = try repository.load(path: duplicate.identity.path)
        let duplicateFrontmatter = persistedDuplicate.document.frontmatter

        #expect(duplicate.identity.path != sourceRecord.identity.path)
        #expect(duplicateFrontmatter.ref != sourceRecord.document.frontmatter.ref)
        #expect(TaskRefGenerator.isValid(ref: try #require(duplicateFrontmatter.ref)))
        #expect(duplicateFrontmatter.title == "Renew passport")
        #expect(duplicateFrontmatter.status == .todo)
        #expect(duplicateFrontmatter.due == nil)
        #expect(duplicateFrontmatter.dueTime == nil)
        #expect(duplicateFrontmatter.persistentReminder == nil)
        #expect(duplicateFrontmatter.defer == nil)
        #expect(duplicateFrontmatter.scheduled == nil)
        #expect(duplicateFrontmatter.scheduledTime == nil)
        #expect(duplicateFrontmatter.recurrence == nil)
        #expect(duplicateFrontmatter.completed == nil)
        #expect(duplicateFrontmatter.completedBy == nil)
        #expect(duplicateFrontmatter.priority == .high)
        #expect(duplicateFrontmatter.flagged == true)
        #expect(duplicateFrontmatter.area == "Travel")
        #expect(duplicateFrontmatter.project == "Vacation")
        #expect(duplicateFrontmatter.tags == ["docs", "urgent"])
        #expect(duplicateFrontmatter.estimatedMinutes == 45)
        #expect(duplicateFrontmatter.description == "Bring printed forms")
        #expect(duplicateFrontmatter.assignee == "Hans")
        #expect(duplicateFrontmatter.blockedBy == .refs(["t-dead"]))
        #expect(duplicateFrontmatter.locationReminder == sourceRecord.document.frontmatter.locationReminder)
        #expect(duplicateFrontmatter.source == "user")
        #expect(persistedDuplicate.document.body == "Checklist body\n")
        #expect(persistedDuplicate.document.unknownFrontmatter["custom_field"] == .string("keep-me"))
        #expect(duplicateFrontmatter.created >= duplicationStart)
        #expect(duplicateFrontmatter.modified == duplicateFrontmatter.created)
    }

    @Test("Duplicating an in-progress task still creates a todo copy with the same title")
    func duplicateInProgressTaskAlwaysCreatesTodoCopy() throws {
        let root = try makeTempDirectory()
        let repository = FileTaskRepository(rootURL: root)
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let sourceRecord = try repository.create(
            document: .init(
                frontmatter: TaskFrontmatterV1(
                    title: "File taxes",
                    status: .inProgress,
                    priority: .medium,
                    flagged: false,
                    tags: ["finance"],
                    created: referenceDate,
                    modified: referenceDate,
                    source: "user"
                ),
                body: "Body"
            ),
            preferredFilename: "file-taxes.md"
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

        let duplicate = try #require(container.duplicateTask(path: sourceRecord.identity.path))
        let persistedDuplicate = try repository.load(path: duplicate.identity.path)

        #expect(persistedDuplicate.document.frontmatter.title == "File taxes")
        #expect(persistedDuplicate.document.frontmatter.status == .todo)
        #expect(persistedDuplicate.document.frontmatter.priority == .medium)
        #expect(persistedDuplicate.document.frontmatter.tags == ["finance"])
        #expect(persistedDuplicate.document.body == "Body\n")
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoMDAppDuplicateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
