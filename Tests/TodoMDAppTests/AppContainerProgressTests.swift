import Foundation
import Testing
@testable import TodoMDApp

@Suite(.serialized)
@MainActor
struct AppContainerProgressTests {
    private func makeContainer(root: URL, tasks: [(title: String, project: String?, status: TaskStatus)]) throws -> AppContainer {
        let repository = FileTaskRepository(rootURL: root)
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        for task in tasks {
            _ = try repository.create(
                document: .init(
                    frontmatter: TaskFrontmatterV1(
                        title: task.title,
                        status: task.status,
                        priority: .none,
                        flagged: false,
                        project: task.project,
                        tags: [],
                        created: referenceDate,
                        modified: referenceDate,
                        source: "user"
                    ),
                    body: ""
                ),
                preferredFilename: "\(task.title.replacingOccurrences(of: " ", with: "-")).md"
            )
        }
        let container = AppContainer()
        container.refresh(forceFullScan: true)
        return container
    }

    @Test("Returns 0/0 for project with no tasks")
    func emptyProject() throws {
        let root = try makeTempDirectory()
        let originalOverride = ProcessInfo.processInfo.environment["TODOMD_STORAGE_OVERRIDE_PATH"]
        setenv("TODOMD_STORAGE_OVERRIDE_PATH", root.path, 1)
        defer {
            if let originalOverride {
                setenv("TODOMD_STORAGE_OVERRIDE_PATH", originalOverride, 1)
            } else {
                unsetenv("TODOMD_STORAGE_OVERRIDE_PATH")
            }
            try? FileManager.default.removeItem(at: root)
        }
        let container = try makeContainer(root: root, tasks: [])
        let result = container.projectProgress(for: "NonExistent")
        #expect(result.completed == 0)
        #expect(result.total == 0)
    }

    @Test("Counts only non-cancelled tasks as total")
    func totalExcludesCancelled() throws {
        let root = try makeTempDirectory()
        let originalOverride = ProcessInfo.processInfo.environment["TODOMD_STORAGE_OVERRIDE_PATH"]
        setenv("TODOMD_STORAGE_OVERRIDE_PATH", root.path, 1)
        defer {
            if let originalOverride {
                setenv("TODOMD_STORAGE_OVERRIDE_PATH", originalOverride, 1)
            } else {
                unsetenv("TODOMD_STORAGE_OVERRIDE_PATH")
            }
            try? FileManager.default.removeItem(at: root)
        }
        let container = try makeContainer(root: root, tasks: [
            (title: "A", project: "P", status: .todo),
            (title: "B", project: "P", status: .done),
            (title: "C", project: "P", status: .cancelled),
        ])
        let result = container.projectProgress(for: "P")
        #expect(result.total == 2)   // todo + done, not cancelled
        #expect(result.completed == 1)
    }

    @Test("Counts only done tasks as completed")
    func completedCountsOnlyDone() throws {
        let root = try makeTempDirectory()
        let originalOverride = ProcessInfo.processInfo.environment["TODOMD_STORAGE_OVERRIDE_PATH"]
        setenv("TODOMD_STORAGE_OVERRIDE_PATH", root.path, 1)
        defer {
            if let originalOverride {
                setenv("TODOMD_STORAGE_OVERRIDE_PATH", originalOverride, 1)
            } else {
                unsetenv("TODOMD_STORAGE_OVERRIDE_PATH")
            }
            try? FileManager.default.removeItem(at: root)
        }
        let container = try makeContainer(root: root, tasks: [
            (title: "A", project: "P", status: .todo),
            (title: "B", project: "P", status: .done),
            (title: "C", project: "P", status: .inProgress),
            (title: "D", project: "P", status: .someday),
        ])
        let result = container.projectProgress(for: "P")
        #expect(result.total == 4)
        #expect(result.completed == 1)
    }

    @Test("Ignores tasks from other projects")
    func ignoresOtherProjects() throws {
        let root = try makeTempDirectory()
        let originalOverride = ProcessInfo.processInfo.environment["TODOMD_STORAGE_OVERRIDE_PATH"]
        setenv("TODOMD_STORAGE_OVERRIDE_PATH", root.path, 1)
        defer {
            if let originalOverride {
                setenv("TODOMD_STORAGE_OVERRIDE_PATH", originalOverride, 1)
            } else {
                unsetenv("TODOMD_STORAGE_OVERRIDE_PATH")
            }
            try? FileManager.default.removeItem(at: root)
        }
        let container = try makeContainer(root: root, tasks: [
            (title: "A", project: "P1", status: .done),
            (title: "B", project: "P2", status: .todo),
        ])
        let result = container.projectProgress(for: "P1")
        #expect(result.total == 1)
        #expect(result.completed == 1)
    }

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppContainerProgressTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
