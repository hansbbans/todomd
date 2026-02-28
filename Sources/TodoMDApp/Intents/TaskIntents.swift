#if canImport(AppIntents)
import AppIntents
import Foundation

struct TaskIntentEntity: AppEntity, Hashable {
    typealias ID = String

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "todo.md Task")
    static let defaultQuery = TaskIntentEntityQuery()

    let id: String
    let title: String
    let path: String
    let status: String
    let source: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(id)"
        )
    }
}

struct TaskIntentEntityQuery: EntityQuery {
    func entities(for identifiers: [TaskIntentEntity.ID]) async throws -> [TaskIntentEntity] {
        let services = IntentServices()
        let repository = try services.makeRepository()
        let records = try repository.loadAll()
        let idSet = Set(identifiers)

        return records
            .filter { idSet.contains($0.identity.filename) }
            .map(services.makeIntentEntity(from:))
    }

    func suggestedEntities() async throws -> [TaskIntentEntity] {
        let services = IntentServices()
        let repository = try services.makeRepository()
        return try repository.loadAll().map(services.makeIntentEntity(from:))
    }
}

private struct IntentServices {
    let locator = TaskFolderLocator()
    let query = TaskQueryEngine()

    func makeRepository() throws -> FileTaskRepository {
        let root = try locator.ensureFolderExists()
        return FileTaskRepository(rootURL: root)
    }

    func resolveView(_ raw: String) -> ViewIdentifier {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? .builtIn(.today) : ViewIdentifier(rawValue: normalized)
    }

    func makeIntentEntity(from record: TaskRecord) -> TaskIntentEntity {
        TaskIntentEntity(
            id: record.identity.filename,
            title: record.document.frontmatter.title,
            path: record.identity.path,
            status: record.document.frontmatter.status.rawValue,
            source: record.document.frontmatter.source
        )
    }

    func findRecord(identifier: String, in records: [TaskRecord]) -> TaskRecord? {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        if let filenameMatch = records.first(where: { $0.identity.filename.lowercased() == normalized }) {
            return filenameMatch
        }

        if let exactTitleMatch = records.first(where: { $0.document.frontmatter.title.lowercased() == normalized }) {
            return exactTitleMatch
        }

        return records.first(where: { $0.document.frontmatter.title.lowercased().contains(normalized) })
    }

    func complete(path: String, repository: FileTaskRepository, now: Date) throws -> TaskRecord {
        let current = try repository.load(path: path)
        let recurrence = current.document.frontmatter.recurrence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let shouldRepeat = !recurrence.isEmpty && current.document.frontmatter.status != .done && current.document.frontmatter.status != .cancelled

        if shouldRepeat {
            return try repository.completeRepeating(path: path, at: now, completedBy: "user").completed
        }
        return try repository.complete(path: path, at: now, completedBy: "user")
    }
}

struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Task"

    @Parameter(title: "Title") var title: String
    @Parameter(title: "Due Date", default: "") var dueDate: String
    @Parameter(title: "Due Time (HH:mm)", default: "") var dueTime: String
    @Parameter(title: "Defer Date", default: "") var deferDate: String
    @Parameter(title: "Priority", default: "") var priority: String
    @Parameter(title: "Area", default: "") var area: String
    @Parameter(title: "Project", default: "") var project: String
    @Parameter(title: "Tags", default: "") var tags: String

    func perform() async throws -> some IntentResult & ReturnsValue<TaskIntentEntity> {
        let services = IntentServices()
        let repository = try services.makeRepository()

        let due = dueDate.isEmpty ? nil : try? LocalDate(isoDate: dueDate)
        let dueTimeValue = (due != nil && !dueTime.isEmpty) ? (try? LocalTime(isoTime: dueTime)) : nil
        let deferred = deferDate.isEmpty ? nil : try? LocalDate(isoDate: deferDate)
        let parsedPriority = TaskPriority(rawValue: priority.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .none
        let trimmedArea = area.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : area.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedProject = project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : project.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedTags = tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let now = Date()

        let frontmatter = TaskFrontmatterV1(
            title: title,
            status: .todo,
            due: due,
            dueTime: dueTimeValue,
            defer: deferred,
            priority: parsedPriority,
            area: trimmedArea,
            project: trimmedProject,
            tags: parsedTags,
            created: now,
            modified: now,
            source: "shortcut"
        )

        let document = TaskDocument(frontmatter: frontmatter, body: "")
        let record = try repository.create(document: document, preferredFilename: nil)
        return .result(value: services.makeIntentEntity(from: record))
    }
}

struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Task"

    @Parameter(title: "Task Title or Filename") var identifier: String

    func perform() async throws -> some IntentResult & ReturnsValue<TaskIntentEntity> {
        let services = IntentServices()
        let repository = try services.makeRepository()
        let records = try repository.loadAll()

        guard let match = services.findRecord(identifier: identifier, in: records) else {
            throw TaskError.invalidURLParameters("No task matched '\(identifier)'")
        }

        let completed = try services.complete(path: match.identity.path, repository: repository, now: Date())
        return .result(value: services.makeIntentEntity(from: completed))
    }
}

struct GetTasksIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Tasks"

    @Parameter(title: "View", default: "today") var view: String
    @Parameter(title: "Area", default: "") var area: String
    @Parameter(title: "Project", default: "") var project: String
    @Parameter(title: "Tag", default: "") var tag: String

    func perform() async throws -> some IntentResult & ReturnsValue<[TaskIntentEntity]> {
        let services = IntentServices()
        let repository = try services.makeRepository()

        let viewIdentifier = services.resolveView(view)
        let today = LocalDate.today(in: .current)

        let tasks = try repository.loadAll()
            .filter { services.query.matches($0, view: viewIdentifier, today: today) }
            .filter { record in
                let trimmed = area.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { return true }
                return record.document.frontmatter.area == trimmed
            }
            .filter { record in
                let trimmed = project.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { return true }
                return record.document.frontmatter.project == trimmed
            }
            .filter { record in
                let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { return true }
                return record.document.frontmatter.tags.contains(trimmed)
            }
            .map(services.makeIntentEntity(from:))

        return .result(value: tasks)
    }
}

struct GetOverdueTasksIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Overdue Tasks"

    func perform() async throws -> some IntentResult & ReturnsValue<[TaskIntentEntity]> {
        let services = IntentServices()
        let repository = try services.makeRepository()
        let today = LocalDate.today(in: .current)

        let overdue = try repository.loadAll()
            .filter { services.query.todayGroup(for: $0, today: today) == .overdue }
            .map(services.makeIntentEntity(from:))

        return .result(value: overdue)
    }
}

struct TodoMDShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add a task in \(.applicationName)",
                "Create task in \(.applicationName)"
            ],
            shortTitle: "Add Task",
            systemImageName: "plus"
        )

        AppShortcut(
            intent: CompleteTaskIntent(),
            phrases: ["Complete task in \(.applicationName)"],
            shortTitle: "Complete Task",
            systemImageName: "checkmark.circle"
        )

        AppShortcut(
            intent: GetTasksIntent(),
            phrases: ["Get tasks in \(.applicationName)"],
            shortTitle: "Get Tasks",
            systemImageName: "list.bullet"
        )

        AppShortcut(
            intent: GetOverdueTasksIntent(),
            phrases: ["Get overdue tasks in \(.applicationName)"],
            shortTitle: "Get Overdue",
            systemImageName: "exclamationmark.triangle"
        )
    }
}
#endif
