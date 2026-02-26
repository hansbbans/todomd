import Foundation
#if canImport(SwiftData)
import SwiftData
#endif
#if canImport(UIKit)
import UIKit
#endif

struct ConflictVersionSummary: Identifiable, Equatable {
    let id: String
    let displayName: String
    let savingComputer: String
    let modifiedAt: Date?
    let versionURLPath: String?
    let hasLocalContents: Bool
    let preview: String?
}

struct ConflictSummary: Identifiable, Equatable {
    let path: String
    let filename: String
    let localSource: String
    let localModifiedAt: Date?
    let versions: [ConflictVersionSummary]

    var id: String { path }
}

struct TaskEditState: Equatable {
    var title: String
    var subtitle: String
    var status: TaskStatus
    var flagged: Bool
    var priority: TaskPriority

    var hasDue: Bool
    var dueDate: Date
    var hasDefer: Bool
    var deferDate: Date
    var hasScheduled: Bool
    var scheduledDate: Date

    var hasEstimatedMinutes: Bool
    var estimatedMinutes: Int

    var area: String
    var project: String
    var tagsText: String
    var recurrence: String
    var body: String

    var createdAt: Date
    var modifiedAt: Date?
    var completedAt: Date?
    var source: String
}

struct TodaySection: Identifiable, Equatable {
    let group: TodayGroup
    let records: [TaskRecord]

    var id: String { group.rawValue }
}

@MainActor
final class AppContainer: ObservableObject {
    @Published var selectedView: ViewIdentifier = .builtIn(.inbox) {
        didSet { _ = applyCurrentViewFilter() }
    }
    @Published var records: [TaskRecord] = []
    @Published var diagnostics: [ParseFailureDiagnostic] = []
    @Published var counters: RuntimeCounters = .init()
    @Published var lastSyncSummary: SyncSummary?
    @Published var rateLimitAlertMessage: String?
    @Published var urlRoutingErrorMessage: String?
    @Published var conflicts: [ConflictSummary] = []
    @Published var navigationTaskPath: String?

    private let repository: FileTaskRepository
    private let fileWatcher: FileWatcherService
    private let manualOrderService: ManualOrderService
    private let queryEngine = TaskQueryEngine()
    private let dateParser = NaturalLanguageDateParser()
    private let urlRouter = URLRouter()
    private let logger: RuntimeLogging
    private let rootURL: URL

#if canImport(SwiftData)
    let modelContainer: ModelContainer
    private let modelContext: ModelContext
#endif

#if canImport(UserNotifications)
    private let notificationScheduler = UserNotificationScheduler()
#endif

    private var canonicalByPath: [String: TaskRecord] = [:]
    private var allIndexedRecords: [TaskRecord] = []

    private var metadataQuery: NSMetadataQuery?
    private var metadataObserverTokens: [NSObjectProtocol] = []
    private var lifecycleObserverTokens: [NSObjectProtocol] = []
    private var metadataRefreshWorkItem: DispatchWorkItem?

    private static let settingsNotificationHourKey = "settings_notification_hour"
    private static let settingsNotificationMinuteKey = "settings_notification_minute"

    init(logger: RuntimeLogging = ConsoleRuntimeLogger()) {
        self.logger = logger

        let folderLocator = TaskFolderLocator()
        let resolvedRoot: URL
        do {
            resolvedRoot = try folderLocator.ensureFolderExists()
        } catch {
            let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("todo.md", isDirectory: true)
            try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            resolvedRoot = fallback
        }

        self.rootURL = resolvedRoot

#if canImport(SwiftData)
        if let container = try? ModelContainer(for: TaskIndexRecord.self) {
            self.modelContainer = container
        } else {
            fatalError("Failed to initialize SwiftData container for TaskIndexRecord")
        }
        self.modelContext = ModelContext(modelContainer)
#endif

        let repository = FileTaskRepository(rootURL: rootURL)
        self.repository = repository
        self.fileWatcher = FileWatcherService(rootURL: rootURL, repository: repository)
        self.manualOrderService = ManualOrderService(rootURL: rootURL)

        configureLifecycleObservers()
        startMetadataQuery()
        refresh()
    }

    var rootFolderPath: String {
        rootURL.path
    }

    func refresh() {
        do {
            let sync = try fileWatcher.synchronize()
            let canonicalRecords = try repository.loadAll()
            canonicalByPath = Dictionary(uniqueKeysWithValues: canonicalRecords.map { ($0.identity.path, $0) })

            let indexStart = ContinuousClock.now
#if canImport(SwiftData)
            try syncSwiftDataIndex(from: canonicalRecords)
            allIndexedRecords = try loadAllFromSwiftDataIndex()
#else
            allIndexedRecords = canonicalRecords
#endif
            let indexMilliseconds = elapsedMilliseconds(since: indexStart)

            diagnostics = fileWatcher.parseDiagnostics
            conflicts = buildConflictSummaries(from: sync.events)

            let queryMilliseconds = applyCurrentViewFilter()

            let planner = notificationPlannerForCurrentSettings()
            let enumerateMilliseconds = fileWatcher.lastPerformance?.enumerateMilliseconds ?? 0
            let parseMilliseconds = fileWatcher.lastPerformance?.parseMilliseconds ?? 0
            counters = RuntimeCounters(
                lastSync: sync.summary.timestamp,
                totalFilesIndexed: allIndexedRecords.count,
                parseFailureCount: diagnostics.count,
                pendingNotificationCount: canonicalRecords.flatMap { planner.planNotifications(for: $0) }.count,
                enumerateMilliseconds: enumerateMilliseconds,
                parseMilliseconds: parseMilliseconds,
                indexMilliseconds: indexMilliseconds,
                queryMilliseconds: queryMilliseconds
            )
            lastSyncSummary = sync.summary

            if let rateLimitEvent = sync.events.first(where: {
                if case .rateLimitedBatch = $0 { return true }
                return false
            }), case .rateLimitedBatch(let paths, let source, _) = rateLimitEvent {
                let sourceLabel = source ?? "unknown"
                rateLimitAlertMessage = "\(paths.count) new tasks were detected in a burst from \(sourceLabel)."
            }

            if let pendingNotificationPath = NotificationActionCoordinator.shared.consumePendingNavigationPath() {
                navigationTaskPath = pendingNotificationPath
            }

            logger.info("Sync completed", metadata: [
                "ingested": "\(sync.summary.ingestedCount)",
                "failed": "\(sync.summary.failedCount)",
                "deleted": "\(sync.summary.deletedCount)",
                "conflicts": "\(sync.summary.conflictCount)"
            ])
            logger.info("Sync performance", metadata: [
                "enumerate_ms": String(format: "%.2f", enumerateMilliseconds),
                "parse_ms": String(format: "%.2f", parseMilliseconds),
                "index_ms": String(format: "%.2f", indexMilliseconds),
                "query_ms": String(format: "%.2f", queryMilliseconds)
            ])

#if canImport(UserNotifications)
            Task {
                await notificationScheduler.requestAuthorizationIfNeeded()
                await notificationScheduler.synchronize(records: canonicalRecords, planner: planner)
            }
#endif
        } catch {
            logger.error("Refresh failed", metadata: ["error": error.localizedDescription])
        }
    }

    func filteredRecords() -> [TaskRecord] {
        records
    }

    func todaySections(today: LocalDate = LocalDate.today(in: .current)) -> [TodaySection] {
        let todayRecords = allIndexedRecords.filter {
            queryEngine.matches($0, view: .builtIn(.today), today: today)
        }
        let ordered = manualOrderService.ordered(records: todayRecords, view: .builtIn(.today))
        var grouped: [TodayGroup: [TaskRecord]] = [:]

        for record in ordered {
            guard let group = queryEngine.todayGroup(for: record, today: today) else { continue }
            grouped[group, default: []].append(record)
        }

        let groupOrder: [TodayGroup] = [.overdue, .scheduled, .dueToday, .deferredNowAvailable]
        return groupOrder.compactMap { group in
            guard let records = grouped[group], !records.isEmpty else { return nil }
            return TodaySection(group: group, records: records)
        }
    }

    func clearPendingNavigationPath() {
        navigationTaskPath = nil
    }

    func record(for path: String) -> TaskRecord? {
        if let cached = canonicalByPath[path] {
            if cached.document.body.isEmpty, let loaded = try? repository.load(path: path) {
                canonicalByPath[path] = loaded
                return loaded
            }
            return cached
        }

        do {
            let loaded = try repository.load(path: path)
            canonicalByPath[path] = loaded
            return loaded
        } catch {
            logger.error("Failed to load record for detail", metadata: ["path": path, "error": error.localizedDescription])
            return nil
        }
    }

    func makeEditState(path: String) -> TaskEditState? {
        guard let record = record(for: path) else { return nil }
        let frontmatter = record.document.frontmatter

        return TaskEditState(
            title: frontmatter.title,
            subtitle: frontmatter.description ?? "",
            status: frontmatter.status,
            flagged: frontmatter.flagged,
            priority: frontmatter.priority,
            hasDue: frontmatter.due != nil,
            dueDate: dateFromLocalDate(frontmatter.due) ?? Date(),
            hasDefer: frontmatter.defer != nil,
            deferDate: dateFromLocalDate(frontmatter.defer) ?? Date(),
            hasScheduled: frontmatter.scheduled != nil,
            scheduledDate: dateFromLocalDate(frontmatter.scheduled) ?? Date(),
            hasEstimatedMinutes: frontmatter.estimatedMinutes != nil,
            estimatedMinutes: frontmatter.estimatedMinutes ?? 15,
            area: frontmatter.area ?? "",
            project: frontmatter.project ?? "",
            tagsText: frontmatter.tags.joined(separator: ", "),
            recurrence: frontmatter.recurrence ?? "",
            body: record.document.body,
            createdAt: frontmatter.created,
            modifiedAt: frontmatter.modified,
            completedAt: frontmatter.completed,
            source: frontmatter.source
        )
    }

    @discardableResult
    func updateTask(path: String, editState: TaskEditState) -> Bool {
        do {
            let updated = try repository.update(path: path) { document in
                let trimmedTitle = editState.title.trimmingCharacters(in: .whitespacesAndNewlines)
                document.frontmatter.title = trimmedTitle.isEmpty ? document.frontmatter.title : trimmedTitle
                document.frontmatter.description = editState.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                document.frontmatter.status = editState.status
                document.frontmatter.flagged = editState.flagged
                document.frontmatter.priority = editState.priority

                document.frontmatter.due = editState.hasDue ? localDateFromDate(editState.dueDate) : nil
                document.frontmatter.defer = editState.hasDefer ? localDateFromDate(editState.deferDate) : nil
                document.frontmatter.scheduled = editState.hasScheduled ? localDateFromDate(editState.scheduledDate) : nil

                document.frontmatter.estimatedMinutes = editState.hasEstimatedMinutes ? max(0, editState.estimatedMinutes) : nil

                document.frontmatter.area = editState.area.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                document.frontmatter.project = editState.project.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

                document.frontmatter.tags = editState.tagsText
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                document.frontmatter.recurrence = editState.recurrence.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                document.body = String(editState.body.prefix(TaskValidation.maxBodyLength))
            }

            markSelfWrite(path: updated.identity.path)
            refresh()
            return true
        } catch {
            logger.error("Task update failed", metadata: ["path": path, "error": error.localizedDescription])
            return false
        }
    }

    @discardableResult
    func deleteTask(path: String) -> Bool {
        do {
            try repository.delete(path: path)
            refresh()
            return true
        } catch {
            logger.error("Task delete failed", metadata: ["path": path, "error": error.localizedDescription])
            return false
        }
    }

    @discardableResult
    func deferToTomorrow(path: String) -> Bool {
        do {
            let updated = try repository.update(path: path) { document in
                guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) else { return }
                document.frontmatter.defer = localDateFromDate(tomorrow)
                document.frontmatter.modified = Date()
            }
            markSelfWrite(path: updated.identity.path)
            refresh()
            return true
        } catch {
            logger.error("Defer-to-tomorrow failed", metadata: ["path": path, "error": error.localizedDescription])
            return false
        }
    }

    @discardableResult
    func toggleFlag(path: String) -> Bool {
        do {
            let updated = try repository.update(path: path) { document in
                document.frontmatter.flagged.toggle()
                document.frontmatter.modified = Date()
            }
            markSelfWrite(path: updated.identity.path)
            refresh()
            return true
        } catch {
            logger.error("Toggle-flag failed", metadata: ["path": path, "error": error.localizedDescription])
            return false
        }
    }

    func createTask(title: String, naturalDate: String?) {
        var due: LocalDate?
        if let naturalDate, !naturalDate.isEmpty {
            due = dateParser.parse(naturalDate)
        }

        let now = Date()
        let frontmatter = TaskFrontmatterV1(
            title: title,
            status: .todo,
            due: due,
            created: now,
            modified: now,
            source: "user"
        )

        let document = TaskDocument(frontmatter: frontmatter, body: "")

        do {
            let created = try repository.create(document: document, preferredFilename: nil)
            markSelfWrite(path: created.identity.path)
            refresh()
        } catch {
            logger.error("Task creation failed", metadata: ["error": error.localizedDescription])
        }
    }

    func createTask(request: TaskCreateRequest) {
        let now = Date()
        let frontmatter = TaskFrontmatterV1(
            title: request.title,
            status: .todo,
            due: request.due,
            defer: request.deferDate,
            scheduled: request.scheduled,
            priority: request.priority ?? .none,
            area: request.area,
            project: request.project,
            tags: request.tags,
            created: now,
            modified: now,
            source: request.source
        )

        let document = TaskDocument(frontmatter: frontmatter, body: "")
        do {
            let created = try repository.create(document: document, preferredFilename: nil)
            markSelfWrite(path: created.identity.path)
            refresh()
        } catch {
            logger.error("Task creation from request failed", metadata: ["error": error.localizedDescription])
        }
    }

    func complete(path: String) {
        do {
            let now = Date()
            let current = try repository.load(path: path)
            let recurrence = current.document.frontmatter.recurrence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let shouldRepeat = !recurrence.isEmpty && current.document.frontmatter.status != .done && current.document.frontmatter.status != .cancelled

            if shouldRepeat {
                let result = try repository.completeRepeating(path: path, at: now)
                markSelfWrite(path: result.completed.identity.path)
                markSelfWrite(path: result.next.identity.path)
            } else {
                let completed = try repository.complete(path: path, at: now)
                markSelfWrite(path: completed.identity.path)
            }
            refresh()
        } catch {
            logger.error("Complete failed", metadata: ["error": error.localizedDescription])
        }
    }

    func complete(record: TaskRecord) {
        complete(path: record.identity.path)
    }

    func saveManualOrder(filenames: [String]) {
        do {
            try manualOrderService.saveOrder(view: selectedView, filenames: filenames)
            applyCurrentViewFilter()
        } catch {
            logger.error("Save manual order failed", metadata: ["error": error.localizedDescription])
        }
    }

    func handleIncomingURL(_ url: URL) {
        do {
            let action = try urlRouter.parse(url: url)
            switch action {
            case .addTask(let request):
                createTask(request: request)
            case .showView(let view):
                selectedView = view
            }
        } catch {
            logger.error("URL routing failed", metadata: ["url": url.absoluteString, "error": error.localizedDescription])
            urlRoutingErrorMessage = "Could not open link: \(error.localizedDescription)"
        }
    }

    func deleteUnparseable(path: String) {
        _ = deleteTask(path: path)
    }

    func rebuildIndex() {
#if canImport(SwiftData)
        do {
            let descriptor = FetchDescriptor<TaskIndexRecord>()
            let existing = try modelContext.fetch(descriptor)
            for model in existing {
                modelContext.delete(model)
            }
            try modelContext.save()
        } catch {
            logger.error("Failed to rebuild index", metadata: ["error": error.localizedDescription])
        }
#endif
        refresh()
    }

    func resolveConflictKeepLocal(path: String) {
        let url = URL(fileURLWithPath: path)
        guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !versions.isEmpty else {
            refresh()
            return
        }

        for version in versions {
            version.isResolved = true
            _ = try? version.remove()
        }

        _ = try? NSFileVersion.removeOtherVersionsOfItem(at: url)
        refresh()
    }

    func resolveConflictKeepRemote(path: String) {
        resolveConflictKeepRemote(path: path, preferredVersionID: nil)
    }

    func resolveConflictKeepRemote(path: String, preferredVersionID: String?) {
        let url = URL(fileURLWithPath: path)
        guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !versions.isEmpty else {
            refresh()
            return
        }

        let selected: NSFileVersion?
        if let preferredVersionID {
            selected = versions.first(where: { String(describing: $0.persistentIdentifier) == preferredVersionID })
                ?? versions.max(by: { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) })
        } else {
            selected = versions.max(by: { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) })
        }

        if let selected {
            _ = try? selected.replaceItem(at: url, options: [])
        }

        for version in versions {
            version.isResolved = true
            _ = try? version.remove()
        }

        _ = try? NSFileVersion.removeOtherVersionsOfItem(at: url)
        refresh()
    }

    func localFileContents(path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    func conflictVersionContents(atPath path: String?) -> String {
        guard let path else { return "" }
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    @discardableResult
    private func applyCurrentViewFilter(today: LocalDate = LocalDate.today(in: .current)) -> Double {
        let start = ContinuousClock.now
        let filtered = allIndexedRecords.filter { queryEngine.matches($0, view: selectedView, today: today) }
        records = manualOrderService.ordered(records: filtered, view: selectedView)
        return elapsedMilliseconds(since: start)
    }

    private func notificationPlannerForCurrentSettings() -> NotificationPlanner {
        let defaults = UserDefaults.standard
        let hour = defaults.object(forKey: Self.settingsNotificationHourKey) as? Int ?? 9
        let minute = defaults.object(forKey: Self.settingsNotificationMinuteKey) as? Int ?? 0
        let normalizedHour = min(23, max(0, hour))
        let normalizedMinute = min(59, max(0, minute))
        return NotificationPlanner(calendar: .current, defaultHour: normalizedHour, defaultMinute: normalizedMinute)
    }

    private func configureLifecycleObservers() {
        let center = NotificationCenter.default

        lifecycleObserverTokens.append(center.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.debounceMetadataRefresh()
            }
        })

#if canImport(UIKit)
        lifecycleObserverTokens.append(center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.startMetadataQuery()
                self?.refresh()
            }
        })

        lifecycleObserverTokens.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopMetadataQuery()
            }
        })
#endif
    }

    private func startMetadataQuery() {
        guard metadataQuery == nil else { return }

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K BEGINSWITH %@", NSMetadataItemPathKey, rootURL.path)

        let center = NotificationCenter.default
        metadataObserverTokens.append(center.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            query.disableUpdates()
            self?.debounceMetadataRefresh()
            query.enableUpdates()
        })

        metadataObserverTokens.append(center.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] _ in
            self?.debounceMetadataRefresh()
        })

        _ = query.start()
        metadataQuery = query
    }

    private func stopMetadataQuery() {
        metadataRefreshWorkItem?.cancel()
        metadataRefreshWorkItem = nil

        if let query = metadataQuery {
            query.stop()
        }
        metadataQuery = nil

        for token in metadataObserverTokens {
            NotificationCenter.default.removeObserver(token)
        }
        metadataObserverTokens.removeAll()
    }

    private func debounceMetadataRefresh() {
        metadataRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        metadataRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

#if canImport(SwiftData)
    private func syncSwiftDataIndex(from canonicalRecords: [TaskRecord]) throws {
        let descriptor = FetchDescriptor<TaskIndexRecord>()
        let existing = try modelContext.fetch(descriptor)
        var existingByPath = Dictionary(uniqueKeysWithValues: existing.map { ($0.path, $0) })
        let canonicalPaths = Set(canonicalRecords.map { $0.identity.path })

        for record in canonicalRecords {
            if let model = existingByPath.removeValue(forKey: record.identity.path) {
                apply(record: record, to: model)
            } else {
                modelContext.insert(TaskIndexRecord(
                    path: record.identity.path,
                    filename: record.identity.filename,
                    title: record.document.frontmatter.title,
                    subtitle: record.document.frontmatter.description,
                    status: record.document.frontmatter.status.rawValue,
                    dueISODate: record.document.frontmatter.due?.isoString,
                    deferISODate: record.document.frontmatter.defer?.isoString,
                    scheduledISODate: record.document.frontmatter.scheduled?.isoString,
                    priority: record.document.frontmatter.priority.rawValue,
                    flagged: record.document.frontmatter.flagged,
                    area: record.document.frontmatter.area,
                    project: record.document.frontmatter.project,
                    tags: record.document.frontmatter.tags,
                    recurrence: record.document.frontmatter.recurrence,
                    estimatedMinutes: record.document.frontmatter.estimatedMinutes,
                    source: record.document.frontmatter.source,
                    modifiedAt: record.document.frontmatter.modified,
                    completedAt: record.document.frontmatter.completed,
                    createdAt: record.document.frontmatter.created
                ))
            }
        }

        for stale in existingByPath.values where !canonicalPaths.contains(stale.path) {
            modelContext.delete(stale)
        }

        try modelContext.save()
    }

    private func apply(record: TaskRecord, to model: TaskIndexRecord) {
        model.filename = record.identity.filename
        model.title = record.document.frontmatter.title
        model.subtitle = record.document.frontmatter.description
        model.status = record.document.frontmatter.status.rawValue
        model.dueISODate = record.document.frontmatter.due?.isoString
        model.deferISODate = record.document.frontmatter.defer?.isoString
        model.scheduledISODate = record.document.frontmatter.scheduled?.isoString
        model.priority = record.document.frontmatter.priority.rawValue
        model.flagged = record.document.frontmatter.flagged
        model.area = record.document.frontmatter.area
        model.project = record.document.frontmatter.project
        model.tags = record.document.frontmatter.tags
        model.recurrence = record.document.frontmatter.recurrence
        model.estimatedMinutes = record.document.frontmatter.estimatedMinutes
        model.source = record.document.frontmatter.source
        model.modifiedAt = record.document.frontmatter.modified
        model.completedAt = record.document.frontmatter.completed
        model.createdAt = record.document.frontmatter.created
    }

    private func loadAllFromSwiftDataIndex() throws -> [TaskRecord] {
        let descriptor = FetchDescriptor<TaskIndexRecord>(sortBy: [SortDescriptor(\TaskIndexRecord.createdAt, order: .reverse)])
        let models = try modelContext.fetch(descriptor)
        return models.map(makeTaskRecord(from:))
    }

    private func makeTaskRecord(from model: TaskIndexRecord) -> TaskRecord {
        let status = TaskStatus(rawValue: model.status) ?? .todo
        let priority = TaskPriority(rawValue: model.priority) ?? .none
        let due = model.dueISODate.flatMap { try? LocalDate(isoDate: $0) }
        let deferDate = model.deferISODate.flatMap { try? LocalDate(isoDate: $0) }
        let scheduled = model.scheduledISODate.flatMap { try? LocalDate(isoDate: $0) }

        let frontmatter = TaskFrontmatterV1(
            title: model.title,
            status: status,
            due: due,
            defer: deferDate,
            scheduled: scheduled,
            priority: priority,
            flagged: model.flagged,
            area: model.area,
            project: model.project,
            tags: model.tags,
            recurrence: model.recurrence,
            estimatedMinutes: model.estimatedMinutes,
            description: model.subtitle,
            created: model.createdAt,
            modified: model.modifiedAt,
            completed: model.completedAt,
            source: model.source
        )

        let body = canonicalByPath[model.path]?.document.body ?? ""
        return TaskRecord(identity: TaskFileIdentity(path: model.path), document: TaskDocument(frontmatter: frontmatter, body: body))
    }
#endif

    private func buildConflictSummaries(from events: [FileWatcherEvent]) -> [ConflictSummary] {
        let conflictPaths = Set(events.compactMap { event -> String? in
            guard case .conflict(let path, _) = event else { return nil }
            return path
        })

        return conflictPaths.sorted().map { path in
            let url = URL(fileURLWithPath: path)
            let versions = (NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).map { version in
                let versionPath = version.url.path
                let preview: String?
                if version.hasLocalContents {
                    preview = (try? String(contentsOfFile: versionPath, encoding: .utf8)).map { String($0.prefix(400)) }
                } else {
                    preview = nil
                }

                return ConflictVersionSummary(
                    id: String(describing: version.persistentIdentifier),
                    displayName: version.localizedName ?? "Version",
                    savingComputer: version.localizedNameOfSavingComputer ?? "Unknown device",
                    modifiedAt: version.modificationDate,
                    versionURLPath: versionPath,
                    hasLocalContents: version.hasLocalContents,
                    preview: preview
                )
            }

            let localRecord = canonicalByPath[path]
            return ConflictSummary(
                path: path,
                filename: URL(fileURLWithPath: path).lastPathComponent,
                localSource: localRecord?.document.frontmatter.source ?? "unknown",
                localModifiedAt: localRecord?.document.frontmatter.modified ?? localRecord?.document.frontmatter.created,
                versions: versions
            )
        }
    }

    private func dateFromLocalDate(_ localDate: LocalDate?) -> Date? {
        guard let localDate else { return nil }
        var components = DateComponents()
        components.year = localDate.year
        components.month = localDate.month
        components.day = localDate.day
        components.hour = 12
        components.minute = 0
        components.calendar = .current
        return Calendar.current.date(from: components)
    }

    private func localDateFromDate(_ date: Date) -> LocalDate {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (try? LocalDate(
            year: components.year ?? 1970,
            month: components.month ?? 1,
            day: components.day ?? 1
        )) ?? .epoch
    }

    private func markSelfWrite(path: String) {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
           let modificationDate = attributes[.modificationDate] as? Date {
            fileWatcher.markSelfWrite(path: path, modificationDate: modificationDate)
        } else {
            fileWatcher.markSelfWrite(path: path)
        }
    }

    private func elapsedMilliseconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now)
        let seconds = Double(duration.components.seconds)
        let attoseconds = Double(duration.components.attoseconds)
        return (seconds * 1_000) + (attoseconds / 1_000_000_000_000_000)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
