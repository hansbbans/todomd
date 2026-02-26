import Foundation
@testable import TodoMDCore

enum TestSupport {
    static func tempDirectory(prefix: String = "TodoMDTests") throws -> URL {
        let base = FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func sampleFrontmatter(
        title: String = "Buy groceries",
        status: TaskStatus = .todo,
        due: LocalDate? = nil,
        deferDate: LocalDate? = nil,
        scheduled: LocalDate? = nil,
        source: String = "user"
    ) -> TaskFrontmatterV1 {
        TaskFrontmatterV1(
            title: title,
            status: status,
            due: due,
            defer: deferDate,
            scheduled: scheduled,
            priority: .none,
            flagged: false,
            area: nil,
            project: nil,
            tags: [],
            recurrence: nil,
            estimatedMinutes: nil,
            description: nil,
            created: Date(timeIntervalSince1970: 1_700_000_000),
            modified: Date(timeIntervalSince1970: 1_700_000_000),
            completed: nil,
            source: source
        )
    }
}
