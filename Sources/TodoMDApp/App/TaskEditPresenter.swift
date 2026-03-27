import Foundation

struct TaskEditState: Equatable {
    var ref: String
    var title: String
    var subtitle: String
    var status: TaskStatus
    var flagged: Bool
    var priority: TaskPriority
    var assignee: String
    var blockedByManual: Bool
    var blockedByRefsText: String
    var completedBy: String

    var hasDue: Bool
    var dueDate: Date
    var hasDueTime: Bool
    var dueTime: Date
    var persistentReminderEnabled: Bool
    var hasDefer: Bool
    var deferDate: Date
    var hasScheduled: Bool
    var scheduledDate: Date
    var hasScheduledTime: Bool
    var scheduledTime: Date

    var hasEstimatedMinutes: Bool
    var estimatedMinutes: Int

    var area: String
    var project: String
    var tagsText: String
    var recurrence: String
    var body: String
    var hasLocationReminder: Bool
    var locationName: String
    var locationLatitude: String
    var locationLongitude: String
    var locationRadiusMeters: Int
    var locationTrigger: TaskLocationReminderTrigger

    var createdAt: Date
    var modifiedAt: Date?
    var completedAt: Date?
    var source: String
}

struct TaskEditPresenter {
    var persistentReminderDefault: Bool
    var quickEntryParser: NaturalLanguageTaskParser
    var calendar: Calendar
    var now: () -> Date

    init(
        persistentReminderDefault: Bool,
        quickEntryParser: NaturalLanguageTaskParser,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.persistentReminderDefault = persistentReminderDefault
        self.quickEntryParser = quickEntryParser
        self.calendar = calendar
        self.now = now
    }

    func makeEditState(record: TaskRecord) -> TaskEditState {
        let frontmatter = record.document.frontmatter
        let locationReminder = frontmatter.locationReminder
        let blockedByRefsText = frontmatter.blockedByRefs.joined(separator: ", ")

        return TaskEditState(
            ref: frontmatter.ref ?? "",
            title: frontmatter.title,
            subtitle: frontmatter.description ?? "",
            status: frontmatter.status,
            flagged: frontmatter.flagged,
            priority: frontmatter.priority,
            assignee: frontmatter.assignee ?? "",
            blockedByManual: frontmatter.blockedBy == .manual,
            blockedByRefsText: blockedByRefsText,
            completedBy: frontmatter.completedBy ?? "",
            hasDue: frontmatter.due != nil,
            dueDate: dateFromLocalDate(frontmatter.due) ?? now(),
            hasDueTime: frontmatter.dueTime != nil,
            dueTime: dateFromLocalTime(frontmatter.dueTime) ?? now(),
            persistentReminderEnabled: frontmatter.persistentReminder ?? persistentReminderDefault,
            hasDefer: frontmatter.defer != nil,
            deferDate: dateFromLocalDate(frontmatter.defer) ?? now(),
            hasScheduled: frontmatter.scheduled != nil,
            scheduledDate: dateFromLocalDate(frontmatter.scheduled) ?? now(),
            hasScheduledTime: frontmatter.scheduledTime != nil,
            scheduledTime: dateFromLocalTime(frontmatter.scheduledTime) ?? now(),
            hasEstimatedMinutes: frontmatter.estimatedMinutes != nil,
            estimatedMinutes: frontmatter.estimatedMinutes ?? 15,
            area: frontmatter.area ?? "",
            project: frontmatter.project ?? "",
            tagsText: frontmatter.tags.joined(separator: ", "),
            recurrence: frontmatter.recurrence ?? "",
            body: record.document.body,
            hasLocationReminder: locationReminder != nil,
            locationName: locationReminder?.name ?? "",
            locationLatitude: locationReminder.map { String(format: "%.6f", $0.latitude) } ?? "",
            locationLongitude: locationReminder.map { String(format: "%.6f", $0.longitude) } ?? "",
            locationRadiusMeters: Int((locationReminder?.radiusMeters ?? TaskLocationReminder.defaultRadiusMeters).rounded()),
            locationTrigger: locationReminder?.trigger ?? .onArrival,
            createdAt: frontmatter.created,
            modifiedAt: frontmatter.modified,
            completedAt: frontmatter.completed,
            source: frontmatter.source
        )
    }

    func apply(editState: TaskEditState, to document: inout TaskDocument) {
        let previousStatus = document.frontmatter.status
        let trimmedTitle = editState.title.trimmingCharacters(in: .whitespacesAndNewlines)
        document.frontmatter.title = trimmedTitle.isEmpty ? document.frontmatter.title : trimmedTitle
        document.frontmatter.ref = editState.ref.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        document.frontmatter.description = editState.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        document.frontmatter.status = editState.status
        document.frontmatter.flagged = editState.flagged
        document.frontmatter.priority = editState.priority
        document.frontmatter.assignee = editState.assignee.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        let blockedRefs = editState.blockedByRefsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if editState.blockedByManual {
            document.frontmatter.blockedBy = .manual
        } else if blockedRefs.isEmpty {
            document.frontmatter.blockedBy = nil
        } else {
            document.frontmatter.blockedBy = .refs(blockedRefs)
        }

        document.frontmatter.due = editState.hasDue ? localDateFromDate(editState.dueDate) : nil
        document.frontmatter.dueTime = (editState.hasDue && editState.hasDueTime) ? localTimeFromDate(editState.dueTime) : nil
        document.frontmatter.persistentReminder = editState.persistentReminderEnabled && editState.hasDue && editState.hasDueTime
        document.frontmatter.defer = editState.hasDefer ? localDateFromDate(editState.deferDate) : nil
        document.frontmatter.scheduled = editState.hasScheduled ? localDateFromDate(editState.scheduledDate) : nil
        document.frontmatter.scheduledTime = (editState.hasScheduled && editState.hasScheduledTime)
            ? localTimeFromDate(editState.scheduledTime)
            : nil

        document.frontmatter.estimatedMinutes = editState.hasEstimatedMinutes ? max(0, editState.estimatedMinutes) : nil

        document.frontmatter.area = editState.area.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        document.frontmatter.project = editState.project.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        document.frontmatter.tags = editState.tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        document.frontmatter.recurrence = editState.recurrence.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        document.frontmatter.locationReminder = locationReminder(from: editState)
        document.body = String(editState.body.prefix(TaskValidation.maxBodyLength))

        let isNowCompleted = editState.status == .done || editState.status == .cancelled
        let wasCompleted = previousStatus == .done || previousStatus == .cancelled
        if isNowCompleted && !wasCompleted {
            document.frontmatter.completed = now()
            document.frontmatter.completedBy = "user"
        } else if !isNowCompleted && wasCompleted {
            document.frontmatter.completed = nil
            document.frontmatter.completedBy = nil
        }
    }

    func resolvedEditState(_ editState: TaskEditState, for currentRecord: TaskRecord?) -> TaskEditState {
        var resolved = editState
        let trimmedTitle = editState.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return resolved }

        let existingTitle = currentRecord?.document.frontmatter.title
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmedTitle != existingTitle,
              let parsed = quickEntryParser.parse(trimmedTitle),
              let due = parsed.due,
              let dueDate = dateFromLocalDate(due) else {
            return resolved
        }

        resolved.hasDue = true
        resolved.dueDate = dueDate

        if let dueTime = parsed.dueTime,
           let dueTimeDate = dateFromLocalTime(dueTime) {
            resolved.hasDueTime = true
            resolved.dueTime = dueTimeDate
        }

        return resolved
    }

    func duplicatedTaskDocument(from source: TaskDocument, now: Date) -> TaskDocument {
        var duplicate = source
        duplicate.frontmatter.ref = nil
        duplicate.frontmatter.status = .todo
        duplicate.frontmatter.due = nil
        duplicate.frontmatter.dueTime = nil
        duplicate.frontmatter.persistentReminder = nil
        duplicate.frontmatter.defer = nil
        duplicate.frontmatter.scheduled = nil
        duplicate.frontmatter.scheduledTime = nil
        duplicate.frontmatter.recurrence = nil
        duplicate.frontmatter.created = now
        duplicate.frontmatter.modified = now
        duplicate.frontmatter.completed = nil
        duplicate.frontmatter.completedBy = nil
        return duplicate
    }

    private func locationReminder(from editState: TaskEditState) -> TaskLocationReminder? {
        guard editState.hasLocationReminder else { return nil }

        let latitudeText = editState.locationLatitude.trimmingCharacters(in: .whitespacesAndNewlines)
        let longitudeText = editState.locationLongitude.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let latitude = Double(latitudeText), let longitude = Double(longitudeText) else {
            return nil
        }

        return TaskLocationReminder(
            name: editState.locationName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            latitude: latitude,
            longitude: longitude,
            radiusMeters: Double(max(50, min(1_000, editState.locationRadiusMeters))),
            trigger: editState.locationTrigger
        )
    }

    private func dateFromLocalDate(_ localDate: LocalDate?) -> Date? {
        guard let localDate else { return nil }
        var components = DateComponents()
        components.year = localDate.year
        components.month = localDate.month
        components.day = localDate.day
        components.hour = 12
        components.minute = 0
        components.calendar = calendar
        return calendar.date(from: components)
    }

    private func localDateFromDate(_ date: Date) -> LocalDate {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return (try? LocalDate(
            year: components.year ?? 1970,
            month: components.month ?? 1,
            day: components.day ?? 1
        )) ?? .epoch
    }

    private func dateFromLocalTime(_ localTime: LocalTime?) -> Date? {
        guard let localTime else { return nil }
        var components = DateComponents()
        components.hour = localTime.hour
        components.minute = localTime.minute
        components.second = 0
        components.calendar = calendar
        return calendar.date(from: components)
    }

    private func localTimeFromDate(_ date: Date) -> LocalTime {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (try? LocalTime(
            hour: components.hour ?? 0,
            minute: components.minute ?? 0
        )) ?? .midnight
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
