import Foundation

public struct TaskFrontmatterV1: Equatable, Sendable {
    public var title: String
    public var status: TaskStatus
    public var due: LocalDate?
    public var dueTime: LocalTime?
    public var `defer`: LocalDate?
    public var scheduled: LocalDate?
    public var priority: TaskPriority
    public var flagged: Bool
    public var area: String?
    public var project: String?
    public var tags: [String]
    public var recurrence: String?
    public var estimatedMinutes: Int?
    public var description: String?
    public var created: Date
    public var modified: Date?
    public var completed: Date?
    public var source: String

    public init(
        title: String,
        status: TaskStatus,
        due: LocalDate? = nil,
        dueTime: LocalTime? = nil,
        defer: LocalDate? = nil,
        scheduled: LocalDate? = nil,
        priority: TaskPriority = .none,
        flagged: Bool = false,
        area: String? = nil,
        project: String? = nil,
        tags: [String] = [],
        recurrence: String? = nil,
        estimatedMinutes: Int? = nil,
        description: String? = nil,
        created: Date,
        modified: Date? = nil,
        completed: Date? = nil,
        source: String
    ) {
        self.title = title
        self.status = status
        self.due = due
        self.dueTime = dueTime
        self.defer = `defer`
        self.scheduled = scheduled
        self.priority = priority
        self.flagged = flagged
        self.area = area
        self.project = project
        self.tags = tags
        self.recurrence = recurrence
        self.estimatedMinutes = estimatedMinutes
        self.description = description
        self.created = created
        self.modified = modified
        self.completed = completed
        self.source = source
    }
}

public struct TaskDocument: Equatable, Sendable {
    public var frontmatter: TaskFrontmatterV1
    public var body: String
    public var unknownFrontmatter: [String: YAMLValue]

    public init(frontmatter: TaskFrontmatterV1, body: String, unknownFrontmatter: [String: YAMLValue] = [:]) {
        self.frontmatter = frontmatter
        self.body = body
        self.unknownFrontmatter = unknownFrontmatter
    }
}
