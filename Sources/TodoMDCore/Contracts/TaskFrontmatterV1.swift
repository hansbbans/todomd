import Foundation

public enum TaskLocationReminderTrigger: String, CaseIterable, Equatable, Sendable {
    case onArrival = "arrive"
    case onDeparture = "leave"
}

public struct TaskLocationReminder: Equatable, Sendable {
    public static let defaultRadiusMeters: Double = 200

    public var name: String?
    public var latitude: Double
    public var longitude: Double
    public var radiusMeters: Double
    public var trigger: TaskLocationReminderTrigger

    public init(
        name: String? = nil,
        latitude: Double,
        longitude: Double,
        radiusMeters: Double = TaskLocationReminder.defaultRadiusMeters,
        trigger: TaskLocationReminderTrigger
    ) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.trigger = trigger
    }
}

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
    public var locationReminder: TaskLocationReminder?
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
        locationReminder: TaskLocationReminder? = nil,
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
        self.locationReminder = locationReminder
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
