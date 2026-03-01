import AppIntents
import SwiftUI
import WidgetKit

private let quickAddURL = URL(string: "todomd://quick-add")!
private let todoMDWidgetKind = "TodoMDTasksWidget"

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
        return .result()
    }
}

struct WidgetTaskItem: Identifiable, Hashable {
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

struct TodoMDWidgetEntry: TimelineEntry {
    let date: Date
    let viewTitle: String
    let viewRawValue: String
    let taskLimit: Int
    let tasks: [WidgetTaskItem]
}

private struct WidgetTaskLoader {
    private let locator = TaskFolderLocator()
    private let queryEngine = TaskQueryEngine()
    private let perspectiveQueryEngine = PerspectiveQueryEngine()

    func load(configuration: TodoMDWidgetConfigurationIntent) throws -> TodoMDWidgetEntry {
        let root = try locator.ensureFolderExists()
        let repository = FileTaskRepository(rootURL: root)
        let perspectivesRepository = PerspectivesRepository()
        let manualOrderService = ManualOrderService(rootURL: root)

        let perspectivesDocument = (try? perspectivesRepository.load(rootURL: root)) ?? PerspectivesDocument()
        let perspectivesByID = perspectivesDocument.perspectives
        let selection = resolveSelection(configuration: configuration, perspectivesByID: perspectivesByID)

        let today = LocalDate.today(in: .current)
        var records = try repository.loadAll()

        switch selection {
        case .builtIn(let view):
            let identifier = ViewIdentifier.builtIn(view)
            records = records.filter { queryEngine.matches($0, view: identifier, today: today) }
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
}

struct TodoMDTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> TodoMDWidgetEntry {
        placeholderEntry()
    }

    func snapshot(for configuration: TodoMDWidgetConfigurationIntent, in _: Context) async -> TodoMDWidgetEntry {
        (try? WidgetTaskLoader().load(configuration: configuration)) ?? placeholderEntry()
    }

    func timeline(for configuration: TodoMDWidgetConfigurationIntent, in _: Context) async -> Timeline<TodoMDWidgetEntry> {
        let entry = (try? WidgetTaskLoader().load(configuration: configuration)) ?? placeholderEntry()
        let refreshMinutes = configuration.source == .today ? 5 : 15
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: refreshMinutes, to: Date())
            ?? Date().addingTimeInterval(TimeInterval(refreshMinutes * 60))
        return Timeline(entries: [entry], policy: .after(nextRefresh))
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

struct TodoMDTasksWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    let entry: TodoMDWidgetEntry

    private let tokens = ThemeTokenStore().loadPreset(.classic)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.viewTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(displayedTasks.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(textSecondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(displayedTasks) { task in
                    taskRow(task)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Link(destination: quickAddURL) {
                    Label("Add", systemImage: "plus.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
        }
        .padding(12)
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
        HStack(spacing: 8) {
            if task.status == .done || task.status == .cancelled {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(textSecondary)
            } else {
                Button(intent: CompleteTaskFromWidgetIntent(path: task.path)) {
                    Image(systemName: task.status == .inProgress ? "circle.dashed" : "circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            }

            if let taskURL = taskURL(for: task.path) {
                Link(destination: taskURL) {
                    HStack(spacing: 6) {
                        Text(task.title)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(textPrimary)
                            .lineLimit(1)

                        if let dueISODate = task.dueISODate {
                            Text(dueISODate)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
            } else {
                Text(task.title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(textPrimary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
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

@main
struct TodoMDWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodoMDTasksWidget()
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
