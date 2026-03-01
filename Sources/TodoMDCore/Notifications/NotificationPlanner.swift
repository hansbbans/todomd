import Foundation

public enum PlannedNotificationKind: String, Equatable, Sendable {
    case due
    case deferAvailable
    case persistentNag
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
    public var persistentRemindersEnabled: Bool
    public var persistentReminderIntervalMinutes: Int
    public var maxPersistentNagsPerTask: Int

    public init(
        calendar: Calendar = .current,
        defaultHour: Int = 9,
        defaultMinute: Int = 0,
        persistentRemindersEnabled: Bool = false,
        persistentReminderIntervalMinutes: Int = 1,
        maxPersistentNagsPerTask: Int = 64
    ) {
        self.calendar = calendar
        self.defaultHour = defaultHour
        self.defaultMinute = defaultMinute
        self.persistentRemindersEnabled = persistentRemindersEnabled
        self.persistentReminderIntervalMinutes = max(1, persistentReminderIntervalMinutes)
        self.maxPersistentNagsPerTask = max(1, maxPersistentNagsPerTask)
    }

    public func planNotifications(for record: TaskRecord, referenceDate: Date = Date()) -> [PlannedNotification] {
        let filename = record.identity.filename
        let frontmatter = record.document.frontmatter
        let status = frontmatter.status
        let taskPersistentRemindersEnabled = frontmatter.persistentReminder ?? persistentRemindersEnabled
        guard status == .todo || status == .inProgress else { return [] }

        var planned: [PlannedNotification] = []

        if let dueDate = frontmatter.due, let fireDate = composeDueFireDate(from: dueDate, dueTime: frontmatter.dueTime) {
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

            if taskPersistentRemindersEnabled {
                let nags = persistentNagNotifications(
                    filename: filename,
                    path: record.identity.path,
                    title: frontmatter.title,
                    dueFireDate: fireDate,
                    referenceDate: referenceDate
                )
                planned.append(contentsOf: nags)
            }
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
        notificationIdentifier(filename: filename, kind: kind, sequence: nil)
    }

    public func notificationIdentifier(filename: String, kind: PlannedNotificationKind, sequence: Int?) -> String {
        switch kind {
        case .due:
            return "\(filename)#due"
        case .deferAvailable:
            return "\(filename)#defer"
        case .persistentNag:
            let ordinal = max(1, sequence ?? 1)
            return "\(filename)#nag-\(ordinal)"
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

    private func composeDueFireDate(from localDate: LocalDate, dueTime: LocalTime?) -> Date? {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = localDate.year
        components.month = localDate.month
        components.day = localDate.day
        components.hour = dueTime?.hour ?? defaultHour
        components.minute = dueTime?.minute ?? defaultMinute
        components.second = 0
        return calendar.date(from: components)
    }

    private func persistentNagNotifications(
        filename: String,
        path: String,
        title: String,
        dueFireDate: Date,
        referenceDate: Date
    ) -> [PlannedNotification] {
        let intervalSeconds = TimeInterval(persistentReminderIntervalMinutes * 60)
        let baseDate = max(dueFireDate, referenceDate)
        var plans: [PlannedNotification] = []
        plans.reserveCapacity(maxPersistentNagsPerTask)

        for sequence in 1...maxPersistentNagsPerTask {
            let fireDate = baseDate.addingTimeInterval(intervalSeconds * Double(sequence))
            plans.append(
                PlannedNotification(
                    identifier: notificationIdentifier(filename: filename, kind: .persistentNag, sequence: sequence),
                    taskPath: path,
                    kind: .persistentNag,
                    fireDate: fireDate,
                    title: title,
                    body: "Still due"
                )
            )
        }

        return plans
    }
}
