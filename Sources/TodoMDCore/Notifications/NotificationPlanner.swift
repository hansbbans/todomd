import Foundation

public enum PlannedNotificationKind: String, Equatable, Sendable {
    case due
    case deferAvailable
}

public struct PlannedNotification: Equatable, Sendable {
    public var identifier: String
    public var taskPath: String
    public var kind: PlannedNotificationKind
    public var fireDate: Date
    public var title: String
    public var body: String

    public init(
        identifier: String,
        taskPath: String,
        kind: PlannedNotificationKind,
        fireDate: Date,
        title: String,
        body: String
    ) {
        self.identifier = identifier
        self.taskPath = taskPath
        self.kind = kind
        self.fireDate = fireDate
        self.title = title
        self.body = body
    }
}

public struct NotificationPlanner {
    public var calendar: Calendar
    public var defaultHour: Int
    public var defaultMinute: Int

    public init(calendar: Calendar = .current, defaultHour: Int = 9, defaultMinute: Int = 0) {
        self.calendar = calendar
        self.defaultHour = defaultHour
        self.defaultMinute = defaultMinute
    }

    public func planNotifications(for record: TaskRecord) -> [PlannedNotification] {
        let filename = record.identity.filename
        let frontmatter = record.document.frontmatter
        var planned: [PlannedNotification] = []

        if let dueDate = frontmatter.due, let fireDate = composeFireDate(from: dueDate) {
            planned.append(
                PlannedNotification(
                    identifier: notificationIdentifier(filename: filename, kind: .due),
                    taskPath: record.identity.path,
                    kind: .due,
                    fireDate: fireDate,
                    title: frontmatter.title,
                    body: "Due today"
                )
            )
        }

        if let deferDate = frontmatter.defer, let fireDate = composeFireDate(from: deferDate) {
            planned.append(
                PlannedNotification(
                    identifier: notificationIdentifier(filename: filename, kind: .deferAvailable),
                    taskPath: record.identity.path,
                    kind: .deferAvailable,
                    fireDate: fireDate,
                    title: frontmatter.title,
                    body: "Task is now available"
                )
            )
        }

        return planned
    }

    public func notificationIdentifier(filename: String, kind: PlannedNotificationKind) -> String {
        switch kind {
        case .due:
            return "\(filename)#due"
        case .deferAvailable:
            return "\(filename)#defer"
        }
    }

    private func composeFireDate(from localDate: LocalDate) -> Date? {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = localDate.year
        components.month = localDate.month
        components.day = localDate.day
        components.hour = defaultHour
        components.minute = defaultMinute
        return calendar.date(from: components)
    }
}
