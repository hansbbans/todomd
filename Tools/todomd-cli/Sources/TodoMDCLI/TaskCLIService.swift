import ArgumentParser
import Foundation
import TodoMDCore

enum TaskCLIServiceError: LocalizedError {
    case missingFolder(String)

    var errorDescription: String? {
        switch self {
        case .missingFolder(let path):
            return "Folder does not exist: \(path)"
        }
    }
}

struct TaskCLIEnvironment {
    var fileManager: FileManager
    var calendar: Calendar
    var now: () -> Date
    var resolveDefaultFolder: () throws -> URL

    init(
        fileManager: FileManager = .default,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        resolveDefaultFolder: @escaping () throws -> URL = {
            try TaskFolderLocator().ensureFolderExists()
        }
    ) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.now = now
        self.resolveDefaultFolder = resolveDefaultFolder
    }

    func resolveRootURL(folder: String?, createIfMissing: Bool) throws -> URL {
        if let folder, !folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let normalized = URL(fileURLWithPath: folder, isDirectory: true)
                .standardizedFileURL
                .resolvingSymlinksInPath()

            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: normalized.path, isDirectory: &isDirectory)
            if exists {
                guard isDirectory.boolValue else {
                    throw TaskCLIServiceError.missingFolder(normalized.path)
                }
                return normalized
            }

            guard createIfMissing else {
                throw TaskCLIServiceError.missingFolder(normalized.path)
            }

            try fileManager.createDirectory(at: normalized, withIntermediateDirectories: true)
            return normalized
        }

        let normalized = try resolveDefaultFolder().standardizedFileURL.resolvingSymlinksInPath()
        try fileManager.createDirectory(at: normalized, withIntermediateDirectories: true)
        return normalized
    }
}

struct TaskSummary: Sendable, Equatable {
    let ref: String
    let title: String
    let path: String
}

struct AddTaskInput: Sendable {
    var title: String
    var due: String?
    var project: String?
    var priority: String?
    var source: String?
    var folder: String?

    init(
        title: String,
        due: String? = nil,
        project: String? = nil,
        priority: String? = nil,
        source: String? = nil,
        folder: String? = nil
    ) {
        self.title = title
        self.due = due
        self.project = project
        self.priority = priority
        self.source = source
        self.folder = folder
    }
}

enum TaskListView: String, Sendable, Equatable {
    case today
    case inbox
    case upcoming
    case all
}

struct ListTasksInput: Sendable {
    var view: String?
    var folder: String?

    init(view: String? = nil, folder: String? = nil) {
        self.view = view
        self.folder = folder
    }
}

struct ListTasksResult: Sendable, Equatable {
    let view: TaskListView
    let tasks: [TaskSummary]
}

struct DoneTaskInput: Sendable {
    var ref: String
    var folder: String?

    init(ref: String, folder: String? = nil) {
        self.ref = ref
        self.folder = folder
    }
}

struct DoneTaskResult: Sendable, Equatable {
    let completed: TaskSummary
    let next: TaskSummary?
}

struct InboxCommandInput: Sendable {
    var folder: String?

    init(folder: String? = nil) {
        self.folder = folder
    }
}

struct InboxCommandResult: Sendable, Equatable {
    let ingestedCount: Int
}

struct AddOutputFormatter {
    static func makeLine(for result: TaskSummary) -> String {
        "Created \(result.ref) \(result.title)"
    }
}

struct TaskListOutputFormatter {
    static func makeLines(for result: ListTasksResult) -> [String] {
        guard !result.tasks.isEmpty else {
            return ["No tasks in \(result.view.rawValue)"]
        }

        return result.tasks.map { "\($0.ref)  \($0.title)" }
    }
}

struct DoneOutputFormatter {
    static func makeLine(for result: DoneTaskResult) -> String {
        if let next = result.next {
            return "Completed \(result.completed.ref) \(result.completed.title) (next \(next.ref))"
        }
        return "Completed \(result.completed.ref) \(result.completed.title)"
    }
}

struct InboxOutputFormatter {
    static func makeLine(for result: InboxCommandResult) -> String {
        "Ingested \(result.ingestedCount) files"
    }
}

struct TaskCLIService {
    var environment: TaskCLIEnvironment

    init(environment: TaskCLIEnvironment = TaskCLIEnvironment()) {
        self.environment = environment
    }

    func add(_ input: AddTaskInput) throws -> TaskSummary {
        let rootURL = try environment.resolveRootURL(folder: input.folder, createIfMissing: true)
        let repository = FileTaskRepository(rootURL: rootURL)
        let now = environment.now()

        let document = TaskDocument(
            frontmatter: TaskFrontmatterV1(
                title: normalizedTitle(input.title),
                status: .todo,
                due: try parseDue(input.due),
                priority: try parsePriority(input.priority),
                project: normalizedOptional(input.project),
                created: now,
                modified: now,
                source: normalizedSource(input.source)
            ),
            body: ""
        )

        let created = try repository.create(document: document, preferredFilename: nil)
        return summary(for: created)
    }

    func list(_ input: ListTasksInput) throws -> ListTasksResult {
        let rootURL = try environment.resolveRootURL(folder: input.folder, createIfMissing: false)
        let repository = FileTaskRepository(rootURL: rootURL)
        let records = try loadRecords(repository: repository, rootURL: rootURL)
        let view = try parseView(input.view)

        let tasks: [TaskSummary]
        switch view {
        case .all:
            tasks = records
                .sorted(by: recordSortComparator)
                .map(summary(for:))
        case .today, .inbox, .upcoming:
            let engine = TaskQueryEngine(calendar: environment.calendar)
            let today = try localToday()
            let eveningStart = try LocalTime(isoTime: "18:00")
            let viewIdentifier: ViewIdentifier = switch view {
            case .today: .builtIn(.today)
            case .inbox: .builtIn(.inbox)
            case .upcoming: .builtIn(.upcoming)
            case .all: .builtIn(.today)
            }

            tasks = records
                .filter { engine.matches($0, view: viewIdentifier, today: today, eveningStart: eveningStart) }
                .sorted(by: recordSortComparator)
                .map(summary(for:))
        }

        return ListTasksResult(view: view, tasks: tasks)
    }

    func done(_ input: DoneTaskInput) throws -> DoneTaskResult {
        let rootURL = try environment.resolveRootURL(folder: input.folder, createIfMissing: false)
        let repository = FileTaskRepository(rootURL: rootURL)
        let records = try loadRecords(repository: repository, rootURL: rootURL)
        let resolver = TaskRefResolver(records: records)

        guard let match = resolver.resolve(ref: input.ref) else {
            throw ValidationError("No task found for ref '\(input.ref)'.")
        }

        let now = environment.now()
        let recurrence = match.document.frontmatter.recurrence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isRepeating = !recurrence.isEmpty
            && match.document.frontmatter.status != .done
            && match.document.frontmatter.status != .cancelled

        if isRepeating {
            let result = try repository.completeRepeating(
                path: match.identity.path,
                at: now,
                completedBy: "todomd-cli"
            )
            return DoneTaskResult(
                completed: summary(for: result.completed),
                next: summary(for: result.next)
            )
        }

        let completed = try repository.complete(
            path: match.identity.path,
            at: now,
            completedBy: "todomd-cli"
        )
        return DoneTaskResult(completed: summary(for: completed), next: nil)
    }

    func inbox(_ input: InboxCommandInput) throws -> InboxCommandResult {
        let rootURL = try environment.resolveRootURL(folder: input.folder, createIfMissing: true)
        let repository = FileTaskRepository(rootURL: rootURL)
        let inboxURL = rootURL.appendingPathComponent(".inbox", isDirectory: true)
        let results = try InboxFolderService(
            inboxURL: inboxURL,
            repository: repository,
            minimumFileAge: 0
        ).processInbox(now: environment.now())

        return InboxCommandResult(ingestedCount: results.count)
    }

    private func summary(for record: TaskRecord) -> TaskSummary {
        TaskSummary(
            ref: normalizedRef(for: record),
            title: record.document.frontmatter.title,
            path: record.identity.path
        )
    }

    private func normalizedRef(for record: TaskRecord) -> String {
        let trimmed = record.document.frontmatter.ref?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "no-ref" : trimmed
    }

    private func normalizedTitle(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedOptional(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedSource(_ raw: String?) -> String {
        normalizedOptional(raw) ?? "cli"
    }

    private func parsePriority(_ raw: String?) throws -> TaskPriority {
        guard let trimmed = normalizedOptional(raw) else { return .none }
        guard let priority = TaskPriority(rawValue: trimmed.lowercased()) else {
            throw ValidationError("Invalid priority '\(trimmed)'. Use none, low, medium, or high.")
        }
        return priority
    }

    private func parseDue(_ raw: String?) throws -> LocalDate? {
        guard let trimmed = normalizedOptional(raw) else { return nil }
        if let isoDate = try? LocalDate(isoDate: trimmed) {
            return isoDate
        }

        if let parsed = NaturalLanguageDateParser(calendar: environment.calendar).parse(trimmed, relativeTo: environment.now()) {
            return parsed
        }

        throw ValidationError("Could not parse due date '\(trimmed)'. Use YYYY-MM-DD or a phrase like 'today' or 'tomorrow'.")
    }

    private func parseView(_ raw: String?) throws -> TaskListView {
        let trimmed = normalizedOptional(raw)?.lowercased() ?? TaskListView.today.rawValue
        guard let view = TaskListView(rawValue: trimmed) else {
            throw ValidationError("Invalid view '\(trimmed)'. Use today, inbox, upcoming, or all.")
        }
        return view
    }

    private func localToday() throws -> LocalDate {
        let components = environment.calendar.dateComponents([.year, .month, .day], from: environment.now())
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            throw ValidationError("Could not determine today's date for task filtering.")
        }
        return try LocalDate(year: year, month: month, day: day)
    }

    private func loadRecords(repository: FileTaskRepository, rootURL: URL) throws -> [TaskRecord] {
        do {
            return try repository.loadAll()
        } catch {
            throw ValidationError(
                "Failed to load tasks from \(rootURL.path): \(error). Hint: run `todomd validate \(rootURL.path)` to find malformed task files."
            )
        }
    }

    private var recordSortComparator: (TaskRecord, TaskRecord) -> Bool {
        { lhs, rhs in
            let lhsTitle = lhs.document.frontmatter.title.localizedCaseInsensitiveCompare(rhs.document.frontmatter.title)
            if lhsTitle != .orderedSame {
                return lhsTitle == .orderedAscending
            }
            return lhs.identity.path < rhs.identity.path
        }
    }
}
