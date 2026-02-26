import Foundation

public enum TodayGroup: String, Sendable {
    case overdue = "Overdue"
    case scheduled = "Scheduled"
    case dueToday = "Due Today"
    case deferredNowAvailable = "Deferred-now-available"
}

public struct TaskQueryEngine {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func matches(_ record: TaskRecord, view: ViewIdentifier, today: LocalDate) -> Bool {
        switch view {
        case .builtIn(let builtIn):
            switch builtIn {
            case .inbox:
                return isInbox(record)
            case .today:
                return isToday(record, today: today)
            case .upcoming:
                return isUpcoming(record, today: today)
            case .anytime:
                return isAnytime(record, today: today)
            case .someday:
                return isSomeday(record)
            case .flagged:
                return isFlagged(record)
            }
        case .area(let name):
            return record.document.frontmatter.area == name
        case .project(let name):
            return record.document.frontmatter.project == name
        case .tag(let tag):
            return record.document.frontmatter.tags.contains(tag)
        case .custom:
            return false
        }
    }

    public func todayGroup(for record: TaskRecord, today: LocalDate) -> TodayGroup? {
        guard isActive(record), isAvailableByDefer(record, today: today) else { return nil }

        let frontmatter = record.document.frontmatter

        if let due = frontmatter.due, due < today {
            return .overdue
        }

        if frontmatter.scheduled == today {
            return .scheduled
        }

        if frontmatter.due == today {
            return .dueToday
        }

        if let deferDate = frontmatter.defer, deferDate <= today {
            return .deferredNowAvailable
        }

        return nil
    }

    public func isInbox(_ record: TaskRecord) -> Bool {
        let frontmatter = record.document.frontmatter
        return isActive(record) && frontmatter.area == nil && frontmatter.project == nil
    }

    public func isToday(_ record: TaskRecord, today: LocalDate) -> Bool {
        todayGroup(for: record, today: today) != nil
    }

    public func isUpcoming(_ record: TaskRecord, today: LocalDate) -> Bool {
        guard isActive(record), isAvailableByDefer(record, today: today) else { return false }
        let frontmatter = record.document.frontmatter

        if let due = frontmatter.due, due > today { return true }
        if let scheduled = frontmatter.scheduled, scheduled > today { return true }
        return false
    }

    public func isAnytime(_ record: TaskRecord, today: LocalDate) -> Bool {
        let status = record.document.frontmatter.status
        guard status == .todo || status == .inProgress else { return false }
        guard isAvailableByDefer(record, today: today) else { return false }
        return status != .someday
    }

    public func isSomeday(_ record: TaskRecord) -> Bool {
        record.document.frontmatter.status == .someday
    }

    public func isFlagged(_ record: TaskRecord) -> Bool {
        let frontmatter = record.document.frontmatter
        return frontmatter.flagged && frontmatter.status != .done && frontmatter.status != .cancelled
    }

    private func isActive(_ record: TaskRecord) -> Bool {
        let status = record.document.frontmatter.status
        return status == .todo || status == .inProgress
    }

    private func isAvailableByDefer(_ record: TaskRecord, today: LocalDate) -> Bool {
        guard let deferDate = record.document.frontmatter.defer else { return true }
        return deferDate <= today
    }
}
