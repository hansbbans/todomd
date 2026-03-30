import AppIntents
import SwiftUI
import WidgetKit

private let quickAddURL = URL(string: "todomd://quick-add")!
private let voiceRambleURL = URL(string: "todomd://voice-ramble")!
private let todoMDWidgetKind = "TodoMDTasksWidget"
private let todoMDTodayTomorrowWidgetKind = "TodoMDTodayTomorrowWidget"
private let todoMDQuickAddAccessoryWidgetKind = "TodoMDQuickAddAccessoryWidget"
private let todoMDVoiceRambleAccessoryWidgetKind = "TodoMDVoiceRambleAccessoryWidget"

enum WidgetTaskSourceOption: String, AppEnum {
    case today
    case inbox
    case perspective

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Task Source")
    static let caseDisplayRepresentations: [WidgetTaskSourceOption: DisplayRepresentation] = [
        .today: DisplayRepresentation(title: "Today"),
        .inbox: DisplayRepresentation(title: "Inbox"),
        .perspective: DisplayRepresentation(title: "Perspective")
    ]
}

struct WidgetPerspectiveEntity: AppEntity, Hashable {
    typealias ID = String

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Perspective")
    static let defaultQuery = WidgetPerspectiveEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct WidgetPerspectiveEntityQuery: EntityQuery {
    func entities(for identifiers: [WidgetPerspectiveEntity.ID]) async throws -> [WidgetPerspectiveEntity] {
        let available = try loadPerspectives()
        let idSet = Set(identifiers)
        return available.filter { idSet.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetPerspectiveEntity] {
        try loadPerspectives()
    }

    private func loadPerspectives() throws -> [WidgetPerspectiveEntity] {
        let root = try TaskFolderLocator().ensureFolderExists()
        let repository = PerspectivesRepository()
        let document = (try? repository.load(rootURL: root)) ?? PerspectivesDocument()
        let orderedIDs = orderedPerspectiveIDs(document: document)

        return orderedIDs.compactMap { id in
            guard let perspective = document.perspectives[id] else { return nil }
            return WidgetPerspectiveEntity(id: perspective.id, name: perspective.name)
        }
    }

    private func orderedPerspectiveIDs(document: PerspectivesDocument) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []

        for id in document.order where document.perspectives[id] != nil {
            if seen.insert(id).inserted {
                ordered.append(id)
            }
        }

        let extras = document.perspectives.values
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map(\.id)
        for id in extras where seen.insert(id).inserted {
            ordered.append(id)
        }

        return ordered
    }
}

struct TodoMDWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "todo.md Tasks"
    static let description = IntentDescription("Show tasks from Today, Inbox, or a perspective with optional filters.")

    @Parameter(title: "Source", default: .today) var source: WidgetTaskSourceOption
    @Parameter(title: "Perspective") var perspective: WidgetPerspectiveEntity?
    @Parameter(title: "Task Limit", default: 5) var taskLimit: Int
    @Parameter(title: "Area", default: "") var area: String
    @Parameter(title: "Project", default: "") var project: String
    @Parameter(title: "Tag", default: "") var tag: String
}

struct CompleteTaskFromWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Task"
    static let openAppWhenRun = false

    @Parameter(title: "Task Path") var path: String

    init() {}

    init(path: String) {
        self.path = path
    }

    func perform() async throws -> some IntentResult {
        let root = try TaskFolderLocator().ensureFolderExists()
        let repository = FileTaskRepository(rootURL: root)
        let current = try repository.load(path: path)

        let status = current.document.frontmatter.status
        guard status != .done, status != .cancelled else {
            return .result()
        }

        let recurrence = current.document.frontmatter.recurrence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let shouldRepeat = !recurrence.isEmpty

        if shouldRepeat {
            _ = try repository.completeRepeating(path: path, at: Date())
        } else {
            _ = try repository.complete(path: path, at: Date())
        }

        WidgetCenter.shared.reloadTimelines(ofKind: todoMDWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: todoMDTodayTomorrowWidgetKind)
        return .result()
    }
}

struct WidgetTaskItem: Identifiable, Hashable, Codable {
    let id: String
    let path: String
    let title: String
    let status: TaskStatus
    let dueISODate: String?
}

private enum WidgetSelection {
    case builtIn(BuiltInView)
    case perspective(PerspectiveDefinition)

    var viewRawValue: String {
        switch self {
        case .builtIn(let view):
            return view.rawValue
        case .perspective(let perspective):
            return "perspective:\(perspective.id)"
        }
    }

    var title: String {
        switch self {
        case .builtIn(.today):
            return "Today"
        case .builtIn(.inbox):
            return "Inbox"
        case .builtIn(let view):
            return view.rawValue.capitalized
        case .perspective(let perspective):
            return perspective.name
        }
    }
}

struct TodoMDWidgetEntry: TimelineEntry, Codable {
    let date: Date
    let viewTitle: String
    let viewRawValue: String
    let taskLimit: Int
    let tasks: [WidgetTaskItem]
}

struct TodoMDTodayTomorrowWidgetEntry: TimelineEntry, Codable {
    let date: Date
    let todayCount: Int
    let tomorrowCount: Int
    let todayEventCount: Int
    let tomorrowEventCount: Int
    let todayTasks: [WidgetTaskItem]
    let tomorrowTasks: [WidgetTaskItem]
    let todayEvents: [WidgetCalendarEventSnapshot]
    let tomorrowEvents: [WidgetCalendarEventSnapshot]
}

struct TodoMDQuickAddAccessoryEntry: TimelineEntry {
    let date: Date
}

struct TodoMDVoiceRambleAccessoryEntry: TimelineEntry {
    let date: Date
}

private struct WidgetEntryCache {
    private let defaults = TaskFolderPreferences.shared
    private let keyPrefix = "widget_entry_cache_v1"

    func load(for configuration: TodoMDWidgetConfigurationIntent) -> TodoMDWidgetEntry? {
        guard let data = defaults.data(forKey: cacheKey(for: configuration)) else {
            return nil
        }
        return try? JSONDecoder().decode(TodoMDWidgetEntry.self, from: data)
    }

    func save(_ entry: TodoMDWidgetEntry, for configuration: TodoMDWidgetConfigurationIntent) {
        guard let data = try? JSONEncoder().encode(entry) else {
            return
        }
        defaults.set(data, forKey: cacheKey(for: configuration))
    }

    private func cacheKey(for configuration: TodoMDWidgetConfigurationIntent) -> String {
        let perspectiveID = configuration.perspective?.id ?? ""
        let area = configuration.area.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = configuration.project.trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = configuration.tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskLimit = max(1, min(50, configuration.taskLimit))
        return [
            keyPrefix,
            configuration.source.rawValue,
            perspectiveID,
            String(taskLimit),
            area,
            project,
            tag
        ].joined(separator: "|")
    }
}

private struct TodayTomorrowWidgetEntryCache {
    private let defaults = TaskFolderPreferences.shared
    private let key = "widget_entry_cache_today_tomorrow_v2"

    func load() -> TodoMDTodayTomorrowWidgetEntry? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(TodoMDTodayTomorrowWidgetEntry.self, from: data)
    }

    func save(_ entry: TodoMDTodayTomorrowWidgetEntry) {
        guard let data = try? JSONEncoder().encode(entry) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}

private struct WidgetTaskLoader {
    private let locator = TaskFolderLocator()
    private let queryEngine = TaskQueryEngine()
    private let perspectiveQueryEngine = PerspectiveQueryEngine()
    private let snapshotStore = TaskRecordSnapshotStore()

    func load(configuration: TodoMDWidgetConfigurationIntent) throws -> TodoMDWidgetEntry {
        let root = try locator.ensureFolderExists()
        let repository = FileTaskRepository(rootURL: root)
        let perspectivesRepository = PerspectivesRepository()
        let manualOrderService = ManualOrderService(rootURL: root)

        let perspectivesDocument = (try? perspectivesRepository.load(rootURL: root)) ?? PerspectivesDocument()
        let perspectivesByID = perspectivesDocument.perspectives
        let selection = resolveSelection(configuration: configuration, perspectivesByID: perspectivesByID)

        let today = LocalDate.today(in: .current)
        var records = try snapshotStore.hydrate(rootURL: root, repository: repository, mode: .optimistic).records

        switch selection {
        case .builtIn(let view):
            let identifier = ViewIdentifier.builtIn(view)
            records = records.filter { queryEngine.matches($0, view: identifier, today: today, eveningStart: (try? LocalTime(isoTime: "18:00")) ?? .midnight) }
            records = manualOrderService.ordered(records: records, view: identifier)
        case .perspective(let perspective):
            records = records.filter { perspectiveQueryEngine.matches($0, perspective: perspective, today: today) }
            records = sorted(records: records, perspective: perspective)
        }

        let areaFilter = configuration.area.trimmingCharacters(in: .whitespacesAndNewlines)
        if !areaFilter.isEmpty {
            records = records.filter { $0.document.frontmatter.area == areaFilter }
        }

        let projectFilter = configuration.project.trimmingCharacters(in: .whitespacesAndNewlines)
        if !projectFilter.isEmpty {
            records = records.filter { $0.document.frontmatter.project == projectFilter }
        }

        let tagFilter = configuration.tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tagFilter.isEmpty {
            records = records.filter { $0.document.frontmatter.tags.contains(tagFilter) }
        }

        let sanitizedLimit = max(1, min(50, configuration.taskLimit))
        let mapped = records.prefix(sanitizedLimit).map { record in
            WidgetTaskItem(
                id: record.identity.path,
                path: record.identity.path,
                title: record.document.frontmatter.title,
                status: record.document.frontmatter.status,
                dueISODate: record.document.frontmatter.due?.isoString
            )
        }

        return TodoMDWidgetEntry(
            date: Date(),
            viewTitle: selection.title,
            viewRawValue: selection.viewRawValue,
            taskLimit: sanitizedLimit,
            tasks: Array(mapped)
        )
    }

    func loadTodayTomorrow(maxTasksPerColumn: Int) throws -> TodoMDTodayTomorrowWidgetEntry {
        let root = try locator.ensureFolderExists()
        let repository = FileTaskRepository(rootURL: root)
        let manualOrderService = ManualOrderService(rootURL: root)

        let today = LocalDate.today(in: .current)
        let tomorrow = offset(today, byDays: 1)
        let records = try snapshotStore.hydrate(rootURL: root, repository: repository, mode: .optimistic).records
        let calendarSnapshot = WidgetCalendarSnapshotStore.load()

        let todayIdentifier = ViewIdentifier.builtIn(.today)
        let orderedToday = manualOrderService.ordered(
            records: records.filter { queryEngine.matches($0, view: todayIdentifier, today: today, eveningStart: (try? LocalTime(isoTime: "18:00")) ?? .midnight) },
            view: todayIdentifier
        )
        let orderedTomorrow = records
            .filter { matchesTomorrow($0, tomorrow: tomorrow) }
            .sorted { compareTomorrowRecords($0, $1, tomorrow: tomorrow) }

        let sanitizedLimit = max(1, min(8, maxTasksPerColumn))
        let todayEvents = calendarSnapshot?.events(for: today) ?? []
        let tomorrowEvents = calendarSnapshot?.events(for: tomorrow) ?? []
        return TodoMDTodayTomorrowWidgetEntry(
            date: Date(),
            todayCount: orderedToday.count,
            tomorrowCount: orderedTomorrow.count,
            todayEventCount: todayEvents.count,
            tomorrowEventCount: tomorrowEvents.count,
            todayTasks: map(records: orderedToday, limit: sanitizedLimit),
            tomorrowTasks: map(records: orderedTomorrow, limit: sanitizedLimit),
            todayEvents: Array(todayEvents.prefix(sanitizedLimit)),
            tomorrowEvents: Array(tomorrowEvents.prefix(sanitizedLimit))
        )
    }

    private func resolveSelection(
        configuration: TodoMDWidgetConfigurationIntent,
        perspectivesByID: [String: PerspectiveDefinition]
    ) -> WidgetSelection {
        switch configuration.source {
        case .today:
            return .builtIn(.today)
        case .inbox:
            return .builtIn(.inbox)
        case .perspective:
            if let perspectiveID = configuration.perspective?.id,
               let perspective = perspectivesByID[perspectiveID] {
                return .perspective(perspective)
            }
            return .builtIn(.today)
        }
    }

    private func sorted(records: [TaskRecord], perspective: PerspectiveDefinition) -> [TaskRecord] {
        let ascending: [TaskRecord]
        switch perspective.sort.field {
        case .manual:
            ascending = orderedByManualList(records: records, filenames: perspective.manualOrder)
        case .due:
            ascending = records.sorted { compareOptionalDate($0.document.frontmatter.due, $1.document.frontmatter.due, fallback: ($0, $1)) }
        case .scheduled:
            ascending = records.sorted { compareOptionalDate($0.document.frontmatter.scheduled, $1.document.frontmatter.scheduled, fallback: ($0, $1)) }
        case .defer:
            ascending = records.sorted { compareOptionalDate($0.document.frontmatter.defer, $1.document.frontmatter.defer, fallback: ($0, $1)) }
        case .priority:
            ascending = records.sorted { lhs, rhs in
                let left = priorityRank(lhs.document.frontmatter.priority)
                let right = priorityRank(rhs.document.frontmatter.priority)
                if left != right {
                    return left > right
                }
                return compareOptionalDate(lhs.document.frontmatter.due, rhs.document.frontmatter.due, fallback: (lhs, rhs))
            }
        case .estimatedMinutes:
            ascending = records.sorted { lhs, rhs in
                switch (lhs.document.frontmatter.estimatedMinutes, rhs.document.frontmatter.estimatedMinutes) {
                case let (left?, right?):
                    if left != right {
                        return left < right
                    }
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    break
                }

                return compareOptionalDate(lhs.document.frontmatter.due, rhs.document.frontmatter.due, fallback: (lhs, rhs))
            }
        case .title:
            ascending = records.sorted {
                $0.document.frontmatter.title.localizedCaseInsensitiveCompare($1.document.frontmatter.title) == .orderedAscending
            }
        case .created:
            ascending = records.sorted { $0.document.frontmatter.created > $1.document.frontmatter.created }
        case .modified:
            ascending = records.sorted { lhs, rhs in
                let left = lhs.document.frontmatter.modified ?? lhs.document.frontmatter.created
                let right = rhs.document.frontmatter.modified ?? rhs.document.frontmatter.created
                if left != right {
                    return left > right
                }
                return lhs.document.frontmatter.title.localizedCaseInsensitiveCompare(rhs.document.frontmatter.title) == .orderedAscending
            }
        case .completed:
            ascending = records.sorted { lhs, rhs in
                let left = lhs.document.frontmatter.completed ?? Date.distantPast
                let right = rhs.document.frontmatter.completed ?? Date.distantPast
                if left != right {
                    return left > right
                }
                return lhs.document.frontmatter.title.localizedCaseInsensitiveCompare(rhs.document.frontmatter.title) == .orderedAscending
            }
        case .flagged:
            ascending = records.sorted { lhs, rhs in
                if lhs.document.frontmatter.flagged != rhs.document.frontmatter.flagged {
                    return lhs.document.frontmatter.flagged && !rhs.document.frontmatter.flagged
                }
                return compareOptionalDate(lhs.document.frontmatter.due, rhs.document.frontmatter.due, fallback: (lhs, rhs))
            }
        case .unknown:
            ascending = records
        }

        if perspective.sort.direction == .desc {
            return Array(ascending.reversed())
        }

        return ascending
    }

    private func map(records: [TaskRecord], limit: Int) -> [WidgetTaskItem] {
        records.prefix(limit).map { record in
            WidgetTaskItem(
                id: record.identity.path,
                path: record.identity.path,
                title: record.document.frontmatter.title,
                status: record.document.frontmatter.status,
                dueISODate: record.document.frontmatter.due?.isoString
            )
        }
    }

    private func orderedByManualList(records: [TaskRecord], filenames: [String]?) -> [TaskRecord] {
        guard let filenames, !filenames.isEmpty else {
            return records.sorted { $0.document.frontmatter.created < $1.document.frontmatter.created }
        }

        let byFilename = Dictionary(uniqueKeysWithValues: records.map { ($0.identity.filename, $0) })
        var ordered: [TaskRecord] = []
        var seen = Set<String>()

        for filename in filenames {
            guard let record = byFilename[filename] else { continue }
            ordered.append(record)
            seen.insert(record.identity.path)
        }

        let remaining = records.filter { !seen.contains($0.identity.path) }
            .sorted { $0.document.frontmatter.created < $1.document.frontmatter.created }

        return ordered + remaining
    }

    private func compareOptionalDate(_ lhs: LocalDate?, _ rhs: LocalDate?, fallback: (TaskRecord, TaskRecord)) -> Bool {
        switch (lhs, rhs) {
        case let (left?, right?):
            if left != right {
                return left < right
            }
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            break
        }

        return fallback.0.document.frontmatter.title.localizedCaseInsensitiveCompare(fallback.1.document.frontmatter.title) == .orderedAscending
    }

    private func priorityRank(_ priority: TaskPriority) -> Int {
        switch priority {
        case .high:
            return 4
        case .medium:
            return 3
        case .low:
            return 2
        case .none:
            return 1
        }
    }

    private func matchesTomorrow(_ record: TaskRecord, tomorrow: LocalDate) -> Bool {
        guard queryEngine.isAnytime(record, today: tomorrow) else { return false }
        let frontmatter = record.document.frontmatter
        return frontmatter.due == tomorrow
            || frontmatter.scheduled == tomorrow
            || frontmatter.defer == tomorrow
    }

    private func compareTomorrowRecords(_ lhs: TaskRecord, _ rhs: TaskRecord, tomorrow: LocalDate) -> Bool {
        let leftRank = tomorrowMatchRank(for: lhs, tomorrow: tomorrow)
        let rightRank = tomorrowMatchRank(for: rhs, tomorrow: tomorrow)
        if leftRank != rightRank {
            return leftRank < rightRank
        }

        let leftPriority = priorityRank(lhs.document.frontmatter.priority)
        let rightPriority = priorityRank(rhs.document.frontmatter.priority)
        if leftPriority != rightPriority {
            return leftPriority > rightPriority
        }

        return lhs.document.frontmatter.title.localizedCaseInsensitiveCompare(rhs.document.frontmatter.title) == .orderedAscending
    }

    private func tomorrowMatchRank(for record: TaskRecord, tomorrow: LocalDate) -> Int {
        let frontmatter = record.document.frontmatter
        if frontmatter.due == tomorrow {
            return 0
        }
        if frontmatter.scheduled == tomorrow {
            return 1
        }
        if frontmatter.defer == tomorrow {
            return 2
        }
        return 3
    }

    private func offset(_ date: LocalDate, byDays days: Int) -> LocalDate {
        var components = DateComponents()
        components.year = date.year
        components.month = date.month
        components.day = date.day

        let calendar = queryEngine.calendar
        let baseDate = calendar.date(from: components) ?? Date()
        let shifted = calendar.date(byAdding: .day, value: days, to: baseDate) ?? baseDate
        let shiftedComponents = calendar.dateComponents([.year, .month, .day], from: shifted)

        return (try? LocalDate(
            year: shiftedComponents.year ?? date.year,
            month: shiftedComponents.month ?? date.month,
            day: shiftedComponents.day ?? date.day
        )) ?? date
    }

}

struct TodoMDTimelineProvider: AppIntentTimelineProvider {
    private let entryCache = WidgetEntryCache()

    func placeholder(in _: Context) -> TodoMDWidgetEntry {
        placeholderEntry()
    }

    func snapshot(for configuration: TodoMDWidgetConfigurationIntent, in context: Context) async -> TodoMDWidgetEntry {
        resolveEntry(configuration: configuration, allowsPlaceholder: context.isPreview)
    }

    func timeline(for configuration: TodoMDWidgetConfigurationIntent, in _: Context) async -> Timeline<TodoMDWidgetEntry> {
        let entry = resolveEntry(configuration: configuration, allowsPlaceholder: false)
        let refreshMinutes = configuration.source == .today ? 5 : 15
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: refreshMinutes, to: Date())
            ?? Date().addingTimeInterval(TimeInterval(refreshMinutes * 60))
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    private func resolveEntry(configuration: TodoMDWidgetConfigurationIntent, allowsPlaceholder: Bool) -> TodoMDWidgetEntry {
        do {
            let loaded = try WidgetTaskLoader().load(configuration: configuration)
            entryCache.save(loaded, for: configuration)
            TaskFolderPreferences.clearLastWidgetLoadError()
            return loaded
        } catch {
            TaskFolderPreferences.saveLastWidgetLoadError(
                error.localizedDescription,
                context: widgetLoadContext(for: configuration)
            )
        }

        if let cached = entryCache.load(for: configuration) {
            return cached
        }

        if allowsPlaceholder {
            return placeholderEntry()
        }

        return emptyEntry(configuration: configuration)
    }

    private func emptyEntry(configuration: TodoMDWidgetConfigurationIntent) -> TodoMDWidgetEntry {
        TodoMDWidgetEntry(
            date: Date(),
            viewTitle: runtimeViewTitle(for: configuration),
            viewRawValue: runtimeViewRawValue(for: configuration),
            taskLimit: max(1, min(50, configuration.taskLimit)),
            tasks: []
        )
    }

    private func runtimeViewTitle(for configuration: TodoMDWidgetConfigurationIntent) -> String {
        switch configuration.source {
        case .today:
            return "Today"
        case .inbox:
            return "Inbox"
        case .perspective:
            let trimmed = configuration.perspective?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "Today" : trimmed
        }
    }

    private func runtimeViewRawValue(for configuration: TodoMDWidgetConfigurationIntent) -> String {
        switch configuration.source {
        case .today:
            return BuiltInView.today.rawValue
        case .inbox:
            return BuiltInView.inbox.rawValue
        case .perspective:
            if let perspectiveID = configuration.perspective?.id, !perspectiveID.isEmpty {
                return "perspective:\(perspectiveID)"
            }
            return BuiltInView.today.rawValue
        }
    }

    private func widgetLoadContext(for configuration: TodoMDWidgetConfigurationIntent) -> String {
        let selectedFolder = TaskFolderPreferences.selectedFolderURL()?.path ?? "<auto>"
        let perspectiveID = configuration.perspective?.id ?? ""
        return [
            "source=\(configuration.source.rawValue)",
            "perspective=\(perspectiveID)",
            "limit=\(max(1, min(50, configuration.taskLimit)))",
            "folder=\(selectedFolder)"
        ].joined(separator: " ")
    }

    private func placeholderEntry() -> TodoMDWidgetEntry {
        TodoMDWidgetEntry(
            date: Date(),
            viewTitle: "Today",
            viewRawValue: BuiltInView.today.rawValue,
            taskLimit: 3,
            tasks: [
                WidgetTaskItem(id: "example-1", path: "/tmp/example-1.md", title: "Plan sprint goals", status: .todo, dueISODate: nil),
                WidgetTaskItem(id: "example-2", path: "/tmp/example-2.md", title: "Review pull requests", status: .inProgress, dueISODate: "2026-02-27")
            ]
        )
    }
}

struct TodayTomorrowTimelineProvider: TimelineProvider {
    private let entryCache = TodayTomorrowWidgetEntryCache()

    func placeholder(in _: Context) -> TodoMDTodayTomorrowWidgetEntry {
        placeholderEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping (TodoMDTodayTomorrowWidgetEntry) -> Void) {
        completion(resolveEntry(allowsPlaceholder: context.isPreview))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<TodoMDTodayTomorrowWidgetEntry>) -> Void) {
        let entry = resolveEntry(allowsPlaceholder: false)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date())
            ?? Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func resolveEntry(allowsPlaceholder: Bool) -> TodoMDTodayTomorrowWidgetEntry {
        do {
            let loaded = try WidgetTaskLoader().loadTodayTomorrow(maxTasksPerColumn: 8)
            entryCache.save(loaded)
            TaskFolderPreferences.clearLastWidgetLoadError()
            return loaded
        } catch {
            TaskFolderPreferences.saveLastWidgetLoadError(
                error.localizedDescription,
                context: widgetLoadContext()
            )
        }

        if let cached = entryCache.load() {
            return cached
        }

        if allowsPlaceholder {
            return placeholderEntry()
        }

        return TodoMDTodayTomorrowWidgetEntry(
            date: Date(),
            todayCount: 0,
            tomorrowCount: 0,
            todayEventCount: 0,
            tomorrowEventCount: 0,
            todayTasks: [],
            tomorrowTasks: [],
            todayEvents: [],
            tomorrowEvents: []
        )
    }

    private func widgetLoadContext() -> String {
        let selectedFolder = TaskFolderPreferences.selectedFolderURL()?.path ?? "<auto>"
        return "source=today-tomorrow folder=\(selectedFolder)"
    }

    private func placeholderEntry() -> TodoMDTodayTomorrowWidgetEntry {
        TodoMDTodayTomorrowWidgetEntry(
            date: Date(),
            todayCount: 2,
            tomorrowCount: 2,
            todayEventCount: 1,
            tomorrowEventCount: 1,
            todayTasks: [
                WidgetTaskItem(id: "today-1", path: "/tmp/today-1.md", title: "Ship widget polish", status: .todo, dueISODate: nil),
                WidgetTaskItem(id: "today-2", path: "/tmp/today-2.md", title: "Review trip budget", status: .inProgress, dueISODate: nil)
            ],
            tomorrowTasks: [
                WidgetTaskItem(id: "tomorrow-1", path: "/tmp/tomorrow-1.md", title: "Draft itinerary", status: .todo, dueISODate: "2026-03-17"),
                WidgetTaskItem(id: "tomorrow-2", path: "/tmp/tomorrow-2.md", title: "Confirm hotel check-in", status: .todo, dueISODate: "2026-03-17")
            ],
            todayEvents: [
                WidgetCalendarEventSnapshot(
                    id: "event-today-1",
                    calendarID: "calendar",
                    calendarName: "Work",
                    calendarColorHex: "#FF6B6B",
                    title: "Design review",
                    startDate: Date().addingTimeInterval(60 * 60),
                    endDate: Date().addingTimeInterval(2 * 60 * 60),
                    isAllDay: false
                )
            ],
            tomorrowEvents: [
                WidgetCalendarEventSnapshot(
                    id: "event-tomorrow-1",
                    calendarID: "calendar",
                    calendarName: "Personal",
                    calendarColorHex: "#4D96FF",
                    title: "Dentist appointment",
                    startDate: Date().addingTimeInterval(25 * 60 * 60),
                    endDate: Date().addingTimeInterval(26 * 60 * 60),
                    isAllDay: false
                )
            ]
        )
    }
}

struct TodoMDQuickAddAccessoryTimelineProvider: TimelineProvider {
    func placeholder(in _: Context) -> TodoMDQuickAddAccessoryEntry {
        TodoMDQuickAddAccessoryEntry(date: Date())
    }

    func getSnapshot(in _: Context, completion: @escaping (TodoMDQuickAddAccessoryEntry) -> Void) {
        completion(TodoMDQuickAddAccessoryEntry(date: Date()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<TodoMDQuickAddAccessoryEntry>) -> Void) {
        let entry = TodoMDQuickAddAccessoryEntry(date: Date())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct TodoMDVoiceRambleAccessoryTimelineProvider: TimelineProvider {
    func placeholder(in _: Context) -> TodoMDVoiceRambleAccessoryEntry {
        TodoMDVoiceRambleAccessoryEntry(date: Date())
    }

    func getSnapshot(in _: Context, completion: @escaping (TodoMDVoiceRambleAccessoryEntry) -> Void) {
        completion(TodoMDVoiceRambleAccessoryEntry(date: Date()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<TodoMDVoiceRambleAccessoryEntry>) -> Void) {
        let entry = TodoMDVoiceRambleAccessoryEntry(date: Date())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct TodoMDTasksWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    let entry: TodoMDWidgetEntry

    private let tokens = ThemeTokenStore().loadPreset(.classic)

    private struct WidgetMetrics {
        let headerFontSize: CGFloat
        let countFontSize: CGFloat
        let taskFontSize: CGFloat
        let glyphFontSize: CGFloat
        let quickAddDiameter: CGFloat
        let quickAddGlyphSize: CGFloat
        let contentSpacing: CGFloat
        let rowSpacing: CGFloat
        let padding: CGFloat
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.contentSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.viewTitle)
                    .font(widgetTitleFont)
                    .foregroundStyle(textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(displayedTasks.count)")
                    .font(widgetCountFont)
                    .foregroundStyle(textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                ForEach(displayedTasks) { task in
                    taskRow(task)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                quickAddButton
            }
        }
        .padding(metrics.padding)
        .containerBackground(for: .widget) {
            background
        }
        .widgetURL(showViewURL(rawValue: entry.viewRawValue))
    }

    private var displayedTasks: [WidgetTaskItem] {
        let familyLimit: Int
        switch family {
        case .systemSmall:
            familyLimit = 3
        case .systemMedium:
            familyLimit = 6
        case .systemLarge:
            familyLimit = 12
        default:
            familyLimit = 6
        }

        return Array(entry.tasks.prefix(min(entry.taskLimit, familyLimit)))
    }

    private func taskRow(_ task: WidgetTaskItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if task.status == .done || task.status == .cancelled {
                Image(systemName: "checkmark.circle.fill")
                    .font(widgetTaskGlyphFont)
                    .foregroundStyle(textSecondary)
            } else {
                Button(intent: CompleteTaskFromWidgetIntent(path: task.path)) {
                    Image(systemName: task.status == .inProgress ? "circle.dashed" : "circle")
                        .font(widgetTaskGlyphFont)
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            }

            if let taskURL = taskURL(for: task.path) {
                Link(destination: taskURL) {
                    Text(task.title)
                        .font(widgetTaskTitleFont)
                        .foregroundStyle(textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(task.title)
                    .font(widgetTaskTitleFont)
                    .foregroundStyle(textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
    }

    private var quickAddButton: some View {
        Link(destination: quickAddURL) {
            ZStack {
                Circle()
                    .fill(accent)
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                    }

                Image(systemName: "plus")
                    .font(widgetQuickAddGlyphFont)
                    .foregroundStyle(quickAddGlyphColor)
            }
            .frame(width: metrics.quickAddDiameter, height: metrics.quickAddDiameter)
            .shadow(color: accent.opacity(0.22), radius: 10, x: 0, y: 5)
            .shadow(color: .black.opacity(0.14), radius: 6, x: 0, y: 3)
        }
        .accessibilityLabel("Add Task")
    }

    private var metrics: WidgetMetrics {
        switch family {
        case .systemSmall:
            return WidgetMetrics(
                headerFontSize: 14,
                countFontSize: 14,
                taskFontSize: 13,
                glyphFontSize: 13,
                quickAddDiameter: 34,
                quickAddGlyphSize: 18,
                contentSpacing: 7,
                rowSpacing: 5,
                padding: 12
            )
        case .systemLarge:
            return WidgetMetrics(
                headerFontSize: 17,
                countFontSize: 17,
                taskFontSize: 15,
                glyphFontSize: 15,
                quickAddDiameter: 40,
                quickAddGlyphSize: 22,
                contentSpacing: 9,
                rowSpacing: 7,
                padding: 14
            )
        case .systemMedium:
            return WidgetMetrics(
                headerFontSize: 16,
                countFontSize: 16,
                taskFontSize: 14,
                glyphFontSize: 14,
                quickAddDiameter: 36,
                quickAddGlyphSize: 20,
                contentSpacing: 8,
                rowSpacing: 6,
                padding: 12
            )
        default:
            return WidgetMetrics(
                headerFontSize: 16,
                countFontSize: 16,
                taskFontSize: 14,
                glyphFontSize: 14,
                quickAddDiameter: 36,
                quickAddGlyphSize: 20,
                contentSpacing: 8,
                rowSpacing: 6,
                padding: 12
            )
        }
    }

    private var widgetTitleFont: Font {
        .system(size: metrics.headerFontSize, weight: .semibold)
    }

    private var widgetCountFont: Font {
        .system(size: metrics.countFontSize, weight: .medium)
    }

    private var widgetTaskTitleFont: Font {
        .system(size: metrics.taskFontSize, weight: .regular)
    }

    private var widgetTaskGlyphFont: Font {
        .system(size: metrics.glyphFontSize, weight: .regular)
    }

    private var widgetQuickAddGlyphFont: Font {
        .system(size: metrics.quickAddGlyphSize, weight: .light)
    }

    private var quickAddGlyphColor: Color {
        colorScheme == .dark ? .black.opacity(0.78) : .black.opacity(0.72)
    }

    private var background: Color {
        colorScheme == .dark ? Color(hex: tokens.colors.backgroundPrimaryDark) : Color(hex: tokens.colors.backgroundPrimaryLight)
    }

    private var textPrimary: Color {
        colorScheme == .dark ? Color(hex: tokens.colors.textPrimaryDark) : Color(hex: tokens.colors.textPrimaryLight)
    }

    private var textSecondary: Color {
        Color(hex: tokens.colors.textSecondary)
    }

    private var accent: Color {
        colorScheme == .dark ? Color(hex: tokens.colors.accentDark) : Color(hex: tokens.colors.accentLight)
    }

    private func showViewURL(rawValue: String) -> URL? {
        URL(string: "todomd://show/\(rawValue)")
    }

    private func taskURL(for path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "todomd"
        components.host = "task"
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        return components.url
    }
}

struct TodoMDTodayTomorrowWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    let entry: TodoMDTodayTomorrowWidgetEntry

    private let tokens = ThemeTokenStore().loadPreset(.classic)

    private struct Metrics {
        let headerFontSize: CGFloat
        let countFontSize: CGFloat
        let taskFontSize: CGFloat
        let eventFontSize: CGFloat
        let eventTimeFontSize: CGFloat
        let glyphFontSize: CGFloat
        let quickAddDiameter: CGFloat
        let quickAddGlyphSize: CGFloat
        let columnSpacing: CGFloat
        let sectionSpacing: CGFloat
        let rowSpacing: CGFloat
        let padding: CGFloat
        let dividerOpacity: CGFloat
        let emptyFontSize: CGFloat
        let rowsPerColumn: Int
        let preferredEventSlots: Int
        let eventMarkerSize: CGFloat
    }

    private enum ColumnRow: Identifiable {
        case task(WidgetTaskItem)
        case event(WidgetCalendarEventSnapshot)

        var id: String {
            switch self {
            case .task(let task):
                return "task-\(task.id)"
            case .event(let event):
                return "event-\(event.id)"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            HStack(alignment: .top, spacing: metrics.columnSpacing) {
                taskColumn(
                    title: "Today",
                    countText: countText(taskCount: entry.todayCount, eventCount: entry.todayEventCount),
                    rows: displayedTodayRows
                )

                Rectangle()
                    .fill(textSecondary.opacity(metrics.dividerOpacity))
                    .frame(width: 1)

                taskColumn(
                    title: "Tomorrow",
                    countText: countText(taskCount: entry.tomorrowCount, eventCount: entry.tomorrowEventCount),
                    rows: displayedTomorrowRows
                )
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                quickAddButton
            }
        }
        .padding(metrics.padding)
        .containerBackground(for: .widget) {
            background
        }
        .widgetURL(showViewURL(rawValue: BuiltInView.today.rawValue))
    }

    private var displayedTodayRows: [ColumnRow] {
        columnRows(tasks: entry.todayTasks, events: entry.todayEvents)
    }

    private var displayedTomorrowRows: [ColumnRow] {
        columnRows(tasks: entry.tomorrowTasks, events: entry.tomorrowEvents)
    }

    @ViewBuilder
    private func taskColumn(title: String, countText: String, rows: [ColumnRow]) -> some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(titleFont)
                    .foregroundStyle(textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(countText)
                    .font(countFont)
                    .foregroundStyle(textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            if rows.isEmpty {
                Text("No items")
                    .font(emptyStateFont)
                    .foregroundStyle(textSecondary)
                    .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                    ForEach(rows) { row in
                        switch row {
                        case .task(let task):
                            taskRow(task)
                        case .event(let event):
                            eventRow(event)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func taskRow(_ task: WidgetTaskItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if task.status == .done || task.status == .cancelled {
                Image(systemName: "checkmark.circle.fill")
                    .font(taskGlyphFont)
                    .foregroundStyle(textSecondary)
            } else {
                Button(intent: CompleteTaskFromWidgetIntent(path: task.path)) {
                    Image(systemName: task.status == .inProgress ? "circle.dashed" : "circle")
                        .font(taskGlyphFont)
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            }

            if let taskURL = taskURL(for: task.path) {
                Link(destination: taskURL) {
                    Text(task.title)
                        .font(taskTitleFont)
                        .foregroundStyle(textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(task.title)
                    .font(taskTitleFont)
                    .foregroundStyle(textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
    }

    private func eventRow(_ event: WidgetCalendarEventSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle()
                .fill(Color(hex: event.calendarColorHex))
                .frame(width: metrics.eventMarkerSize, height: metrics.eventMarkerSize)

            Text(eventTimeText(for: event))
                .font(eventTimeFont)
                .foregroundStyle(textSecondary)
                .lineLimit(1)
                .monospacedDigit()

            Text(event.title)
                .font(eventTitleFont)
                .foregroundStyle(textPrimary.opacity(0.92))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    private var quickAddButton: some View {
        Link(destination: quickAddURL) {
            ZStack {
                Circle()
                    .fill(accent)
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                    }

                Image(systemName: "plus")
                    .font(quickAddGlyphFont)
                    .foregroundStyle(quickAddGlyphColor)
            }
            .frame(width: metrics.quickAddDiameter, height: metrics.quickAddDiameter)
            .shadow(color: accent.opacity(0.22), radius: 10, x: 0, y: 5)
            .shadow(color: .black.opacity(0.14), radius: 6, x: 0, y: 3)
        }
        .accessibilityLabel("Add Task")
    }

    private var metrics: Metrics {
        switch family {
        case .systemLarge:
            return Metrics(
                headerFontSize: 17,
                countFontSize: 17,
                taskFontSize: 15,
                eventFontSize: 15,
                eventTimeFontSize: 12,
                glyphFontSize: 15,
                quickAddDiameter: 40,
                quickAddGlyphSize: 22,
                columnSpacing: 12,
                sectionSpacing: 9,
                rowSpacing: 7,
                padding: 14,
                dividerOpacity: 0.18,
                emptyFontSize: 14,
                rowsPerColumn: 6,
                preferredEventSlots: 2,
                eventMarkerSize: 7
            )
        default:
            return Metrics(
                headerFontSize: 16,
                countFontSize: 16,
                taskFontSize: 14,
                eventFontSize: 13,
                eventTimeFontSize: 11,
                glyphFontSize: 14,
                quickAddDiameter: 36,
                quickAddGlyphSize: 20,
                columnSpacing: 10,
                sectionSpacing: 8,
                rowSpacing: 6,
                padding: 12,
                dividerOpacity: 0.14,
                emptyFontSize: 13,
                rowsPerColumn: 3,
                preferredEventSlots: 1,
                eventMarkerSize: 6
            )
        }
    }

    private var titleFont: Font {
        .system(size: metrics.headerFontSize, weight: .semibold)
    }

    private var countFont: Font {
        .system(size: metrics.countFontSize, weight: .medium)
    }

    private var taskTitleFont: Font {
        .system(size: metrics.taskFontSize, weight: .regular)
    }

    private var taskGlyphFont: Font {
        .system(size: metrics.glyphFontSize, weight: .regular)
    }

    private var eventTitleFont: Font {
        .system(size: metrics.eventFontSize, weight: .regular)
    }

    private var eventTimeFont: Font {
        .system(size: metrics.eventTimeFontSize, weight: .medium)
    }

    private var emptyStateFont: Font {
        .system(size: metrics.emptyFontSize, weight: .regular)
    }

    private var quickAddGlyphFont: Font {
        .system(size: metrics.quickAddGlyphSize, weight: .light)
    }

    private var quickAddGlyphColor: Color {
        colorScheme == .dark ? .black.opacity(0.78) : .black.opacity(0.72)
    }

    private var background: Color {
        colorScheme == .dark ? Color(hex: tokens.colors.backgroundPrimaryDark) : Color(hex: tokens.colors.backgroundPrimaryLight)
    }

    private var textPrimary: Color {
        colorScheme == .dark ? Color(hex: tokens.colors.textPrimaryDark) : Color(hex: tokens.colors.textPrimaryLight)
    }

    private var textSecondary: Color {
        Color(hex: tokens.colors.textSecondary)
    }

    private var accent: Color {
        colorScheme == .dark ? Color(hex: tokens.colors.accentDark) : Color(hex: tokens.colors.accentLight)
    }

    private func showViewURL(rawValue: String) -> URL? {
        URL(string: "todomd://show/\(rawValue)")
    }

    private func taskURL(for path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "todomd"
        components.host = "task"
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        return components.url
    }

    private func countText(taskCount: Int, eventCount: Int) -> String {
        switch (taskCount, eventCount) {
        case (0, 0):
            return "0"
        case let (tasks, 0):
            return "\(tasks)"
        case let (0, events):
            return "\(events)E"
        case let (tasks, events):
            return "\(tasks)T \(events)E"
        }
    }

    private func columnRows(
        tasks: [WidgetTaskItem],
        events: [WidgetCalendarEventSnapshot]
    ) -> [ColumnRow] {
        let maxRows = metrics.rowsPerColumn
        let reservedEventSlots = tasks.isEmpty ? maxRows : min(events.count, metrics.preferredEventSlots)
        let taskCount = min(tasks.count, maxRows - reservedEventSlots)
        let eventCount = min(events.count, maxRows - taskCount)

        let taskRows = tasks.prefix(taskCount).map { ColumnRow.task($0) }
        let eventRows = events.prefix(eventCount).map { ColumnRow.event($0) }
        return taskRows + eventRows
    }

    private func eventTimeText(for event: WidgetCalendarEventSnapshot) -> String {
        if event.isAllDay {
            return "All day"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm"
        return formatter.string(from: event.startDate)
    }
}

struct TodoMDQuickAddAccessoryWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: TodoMDQuickAddAccessoryEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circularContent
            case .accessoryRectangular:
                rectangularContent
            case .accessoryInline:
                inlineContent
            default:
                inlineContent
            }
        }
        .widgetURL(quickAddURL)
    }

    private var circularContent: some View {
        ZStack {
            Circle()
                .fill(.clear)

            Image(systemName: "plus")
                .font(.system(size: 19, weight: .semibold))
                .widgetAccentable()
        }
        .accessibilityLabel("Add Task")
    }

    private var rectangularContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Add Task")
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .lineLimit(1)

            Text("Open quick entry")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityLabel("Add Task")
    }

    private var inlineContent: some View {
        Label("Add Task", systemImage: "plus")
            .accessibilityLabel("Add Task")
    }
}

struct TodoMDVoiceRambleAccessoryWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: TodoMDVoiceRambleAccessoryEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circularContent
            case .accessoryRectangular:
                rectangularContent
            case .accessoryInline:
                inlineContent
            default:
                inlineContent
            }
        }
        .widgetURL(voiceRambleURL)
    }

    private var circularContent: some View {
        ZStack {
            Circle()
                .fill(.clear)

            Image(systemName: "waveform")
                .font(.system(size: 17, weight: .semibold))
                .widgetAccentable()
        }
        .accessibilityLabel("Voice Ramble")
    }

    private var rectangularContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Voice Ramble")
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .lineLimit(1)

            Text("Open voice capture")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityLabel("Voice Ramble")
    }

    private var inlineContent: some View {
        Label("Ramble", systemImage: "waveform")
            .accessibilityLabel("Voice Ramble")
    }
}

struct TodoMDTasksWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: todoMDWidgetKind,
            intent: TodoMDWidgetConfigurationIntent.self,
            provider: TodoMDTimelineProvider()
        ) { entry in
            TodoMDTasksWidgetView(entry: entry)
        }
        .configurationDisplayName("todo.md Tasks")
        .description("View and complete tasks from Today, Inbox, or a perspective.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TodoMDTodayTomorrowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: todoMDTodayTomorrowWidgetKind,
            provider: TodayTomorrowTimelineProvider()
        ) { entry in
            TodoMDTodayTomorrowWidgetView(entry: entry)
        }
        .configurationDisplayName("Today / Tomorrow")
        .description("See the tasks that matter today next to what is coming tomorrow.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TodoMDQuickAddAccessoryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: todoMDQuickAddAccessoryWidgetKind,
            provider: TodoMDQuickAddAccessoryTimelineProvider()
        ) { entry in
            TodoMDQuickAddAccessoryWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Add")
        .description("Open todo.md and add a task from the Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct TodoMDVoiceRambleAccessoryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: todoMDVoiceRambleAccessoryWidgetKind,
            provider: TodoMDVoiceRambleAccessoryTimelineProvider()
        ) { entry in
            TodoMDVoiceRambleAccessoryWidgetView(entry: entry)
        }
        .configurationDisplayName("Voice Ramble")
        .description("Open todo.md and capture tasks with voice from the Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct TodoMDWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodoMDTasksWidget()
        TodoMDTodayTomorrowWidget()
        TodoMDQuickAddAccessoryWidget()
        TodoMDVoiceRambleAccessoryWidget()
    }
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            self = .accentColor
            return
        }

        let red = Double((value & 0xFF0000) >> 16) / 255.0
        let green = Double((value & 0x00FF00) >> 8) / 255.0
        let blue = Double(value & 0x0000FF) / 255.0

        self = Color(.sRGB, red: red, green: green, blue: blue, opacity: 1.0)
    }
}
