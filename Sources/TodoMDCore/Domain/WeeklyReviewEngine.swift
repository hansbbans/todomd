import Foundation

public enum WeeklyReviewSectionKind: String, CaseIterable, Sendable {
    case overdue
    case stale
    case someday
    case projectsWithoutNextAction

    public var title: String {
        switch self {
        case .overdue:
            return "Overdue"
        case .stale:
            return "Stale Tasks"
        case .someday:
            return "Someday"
        case .projectsWithoutNextAction:
            return "Projects With No Next Action"
        }
    }
}

public struct WeeklyReviewProjectSummary: Equatable, Identifiable, Sendable {
    public let project: String
    public let taskCount: Int
    public let blockedCount: Int
    public let delegatedCount: Int
    public let deferredCount: Int
    public let somedayCount: Int

    public init(
        project: String,
        taskCount: Int,
        blockedCount: Int,
        delegatedCount: Int,
        deferredCount: Int,
        somedayCount: Int
    ) {
        self.project = project
        self.taskCount = taskCount
        self.blockedCount = blockedCount
        self.delegatedCount = delegatedCount
        self.deferredCount = deferredCount
        self.somedayCount = somedayCount
    }

    public var id: String { project }
}

public struct WeeklyReviewSection: Equatable, Identifiable, Sendable {
    public let kind: WeeklyReviewSectionKind
    public let records: [TaskRecord]
    public let projects: [WeeklyReviewProjectSummary]

    public init(
        kind: WeeklyReviewSectionKind,
        records: [TaskRecord] = [],
        projects: [WeeklyReviewProjectSummary] = []
    ) {
        self.kind = kind
        self.records = records
        self.projects = projects
    }

    public var id: String { kind.rawValue }

    public var count: Int {
        switch kind {
        case .projectsWithoutNextAction:
            return projects.count
        case .overdue, .stale, .someday:
            return records.count
        }
    }
}

public struct WeeklyReviewEngine {
    public var calendar: Calendar
    public var staleAfterDays: Int

    public init(calendar: Calendar = .current, staleAfterDays: Int = 14) {
        self.calendar = calendar
        self.staleAfterDays = max(1, staleAfterDays)
    }

    public func sections(
        for records: [TaskRecord],
        today: LocalDate = LocalDate.today(in: .current),
        now: Date = Date()
    ) -> [WeeklyReviewSection] {
        let overdue = records
            .filter { isOverdue($0, today: today) }
            .sorted(by: compareOverdueRecords)

        let overduePaths = Set(overdue.map(\.identity.path))

        let stale = records
            .filter {
                !overduePaths.contains($0.identity.path)
                    && isStale($0, today: today, now: now)
            }
            .sorted(by: compareStaleRecords)

        let stalePaths = Set(stale.map(\.identity.path))

        let someday = records
            .filter {
                !overduePaths.contains($0.identity.path)
                    && !stalePaths.contains($0.identity.path)
                    && isSomeday($0)
            }
            .sorted(by: compareSomedayRecords)

        let projectsWithoutNextAction = projectSummariesWithoutNextAction(records: records, today: today)

        return [
            WeeklyReviewSection(kind: .overdue, records: overdue),
            WeeklyReviewSection(kind: .stale, records: stale),
            WeeklyReviewSection(kind: .someday, records: someday),
            WeeklyReviewSection(kind: .projectsWithoutNextAction, projects: projectsWithoutNextAction)
        ].filter { $0.count > 0 }
    }

    public func isOverdue(_ record: TaskRecord, today: LocalDate) -> Bool {
        let frontmatter = record.document.frontmatter
        guard isOpen(frontmatter.status), let due = frontmatter.due else { return false }
        return due < today
    }

    public func isStale(_ record: TaskRecord, today: LocalDate, now: Date = Date()) -> Bool {
        let frontmatter = record.document.frontmatter
        guard isOpen(frontmatter.status), frontmatter.status != .someday else { return false }
        guard !isOverdue(record, today: today) else { return false }
        let lastTouched = frontmatter.modified ?? frontmatter.created
        let startOfToday = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -staleAfterDays, to: startOfToday) else {
            return false
        }
        return lastTouched < cutoff
    }

    public func isSomeday(_ record: TaskRecord) -> Bool {
        record.document.frontmatter.status == .someday
    }

    public func hasCurrentNextAction(_ record: TaskRecord, today: LocalDate) -> Bool {
        let frontmatter = record.document.frontmatter
        guard isOpen(frontmatter.status), frontmatter.status != .someday else { return false }
        guard isAssignedToUser(frontmatter.assignee) else { return false }
        guard !frontmatter.isBlocked else { return false }
        guard isAvailableByDefer(frontmatter.defer, today: today) else { return false }
        return true
    }

    public func projectSummariesWithoutNextAction(
        records: [TaskRecord],
        today: LocalDate
    ) -> [WeeklyReviewProjectSummary] {
        var grouped: [String: [TaskRecord]] = [:]

        for record in records {
            let frontmatter = record.document.frontmatter
            guard isOpen(frontmatter.status) || frontmatter.status == .someday else { continue }
            guard let rawProject = frontmatter.project?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawProject.isEmpty else { continue }
            grouped[rawProject, default: []].append(record)
        }

        return grouped.compactMap { project, records in
            guard !records.contains(where: { hasCurrentNextAction($0, today: today) }) else {
                return nil
            }

            return WeeklyReviewProjectSummary(
                project: project,
                taskCount: records.count,
                blockedCount: records.filter { $0.document.frontmatter.isBlocked }.count,
                delegatedCount: records.filter { isDelegated($0.document.frontmatter.assignee) }.count,
                deferredCount: records.filter { !isAvailableByDefer($0.document.frontmatter.defer, today: today) }.count,
                somedayCount: records.filter { $0.document.frontmatter.status == .someday }.count
            )
        }
        .sorted {
            $0.project.localizedCaseInsensitiveCompare($1.project) == .orderedAscending
        }
    }

    private func isOpen(_ status: TaskStatus) -> Bool {
        status == .todo || status == .inProgress
    }

    private func isAssignedToUser(_ assignee: String?) -> Bool {
        let normalized = assignee?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized == nil || normalized == "" || normalized == "user"
    }

    private func isDelegated(_ assignee: String?) -> Bool {
        let normalized = assignee?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let normalized, !normalized.isEmpty else { return false }
        return normalized != "user"
    }

    private func isAvailableByDefer(_ deferDate: LocalDate?, today: LocalDate) -> Bool {
        guard let deferDate else { return true }
        return deferDate <= today
    }

    private func compareOverdueRecords(_ lhs: TaskRecord, _ rhs: TaskRecord) -> Bool {
        let leftDue = lhs.document.frontmatter.due
        let rightDue = rhs.document.frontmatter.due
        switch (leftDue, rightDue) {
        case let (l?, r?) where l != r:
            return l < r
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return compareTitles(lhs, rhs)
        }
    }

    private func compareStaleRecords(_ lhs: TaskRecord, _ rhs: TaskRecord) -> Bool {
        let leftTouched = lhs.document.frontmatter.modified ?? lhs.document.frontmatter.created
        let rightTouched = rhs.document.frontmatter.modified ?? rhs.document.frontmatter.created
        if leftTouched != rightTouched {
            return leftTouched < rightTouched
        }
        return compareTitles(lhs, rhs)
    }

    private func compareSomedayRecords(_ lhs: TaskRecord, _ rhs: TaskRecord) -> Bool {
        compareStaleRecords(lhs, rhs)
    }

    private func compareTitles(_ lhs: TaskRecord, _ rhs: TaskRecord) -> Bool {
        lhs.document.frontmatter.title.localizedCaseInsensitiveCompare(rhs.document.frontmatter.title) == .orderedAscending
    }
}
