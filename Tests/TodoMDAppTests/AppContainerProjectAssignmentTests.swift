import Foundation
import Testing
@testable import TodoMDApp

@MainActor
struct AppContainerProjectAssignmentTests {
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

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoMDAppTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
