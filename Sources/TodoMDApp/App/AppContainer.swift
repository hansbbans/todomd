@preconcurrency import Foundation
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

struct TodaySection: Identifiable, Equatable {
    let group: TodayGroup
    let records: [TaskRecord]

    var id: String { group.rawValue }
}

struct UpcomingSection: Identifiable, Equatable {
    let date: LocalDate
    let records: [TaskRecord]

    var id: String { date.isoString }
}

struct LocationFavorite: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var latitude: Double
    var longitude: Double
    var radiusMeters: Int

    init(
        id: String = UUID().uuidString,
        name: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Int = Int(TaskLocationReminder.defaultRadiusMeters.rounded())
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
    }
}

private struct ReminderImportCandidate: Sendable {
    let reminderID: String
    let document: TaskDocument
}

private struct ReminderImportCreateResult: Sendable {
    struct CreatedRecord: Sendable {
        let path: String
        let reminderID: String
    }

    let created: [CreatedRecord]
    let failedCount: Int
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
    @Published var shouldPresentQuickEntry = false
    @Published var conflicts: [ConflictSummary] = []
    @Published var navigationTaskPath: String?
    @Published var perspectives: [PerspectiveDefinition] = []
    @Published var perspectivesWarningMessage: String?
    @Published var isCalendarConnected = false
    @Published var isCalendarSyncing = false
    @Published var calendarStatusMessage: String?
    @Published private(set) var calendarSources: [CalendarSource] = []
    @Published private(set) var selectedCalendarSourceIDs: Set<String> = []
    @Published var calendarTodayEvents: [CalendarEventItem] = []
    @Published var calendarUpcomingSections: [CalendarDaySection] = []
    @Published private(set) var reminderLists: [ReminderList] = []
    @Published private(set) var selectedReminderListID: String?
    @Published var remindersImportStatusMessage: String?
    @Published var isRemindersImporting = false
    @Published private(set) var locationFavorites: [LocationFavorite] = []

    private var repository: FileTaskRepository
    private var fileWatcher: FileWatcherService
    private var manualOrderService: ManualOrderService
    private var perspectivesRepository: PerspectivesRepository
    private let queryEngine = TaskQueryEngine()
    private let perspectiveQueryEngine = PerspectiveQueryEngine()
    private let dateParser = NaturalLanguageDateParser()
    private let quickEntryParser = NaturalLanguageTaskParser()
    private let urlRouter = URLRouter()
    private let googleCalendarService = GoogleCalendarService()
    private let remindersImportService = RemindersImportService()
    private let logger: RuntimeLogging
    private(set) var rootURL: URL

#if canImport(SwiftData)
    let modelContainer: ModelContainer
    private let modelContext: ModelContext
#endif

#if canImport(UserNotifications)
    private let notificationScheduler = UserNotificationScheduler()
#endif

    private var canonicalByPath: [String: TaskRecord] = [:]
    private var allIndexedRecords: [TaskRecord] = []
    private var cachedPerspectivesDocument = PerspectivesDocument()

    private var metadataQuery: NSMetadataQuery?
    private var metadataObserverTokens: [NSObjectProtocol] = []
    private var lifecycleObserverTokens: [NSObjectProtocol] = []
    private var metadataRefreshWorkItem: DispatchWorkItem?
    private var suppressMetadataRefreshUntil: Date?
    private var calendarRefreshTask: Task<Void, Never>?
    private var lastCalendarSyncAt: Date?

    private static let settingsNotificationHourKey = "settings_notification_hour"
    private static let settingsNotificationMinuteKey = "settings_notification_minute"
    private static let settingsNotifyAutoUnblockedKey = "settings_notify_auto_unblocked"
    private static let settingsPersistentRemindersEnabledKey = "settings_persistent_reminders_enabled"
    private static let settingsPersistentReminderIntervalMinutesKey = "settings_persistent_reminder_interval_minutes"
    private static let settingsArchiveCompletedKey = "settings_archive_completed"
    private static let settingsCompletedRetentionKey = "settings_completed_retention"
    private static let settingsDefaultPriorityKey = "settings_default_priority"
    private static let settingsQuickEntryDefaultViewKey = "settings_quick_entry_default_view"
    private static let settingsPerspectivesKey = "settings_saved_perspectives_v1"
    private static let settingsGoogleCalendarEnabledKey = "settings_google_calendar_enabled"
    private static let settingsGoogleCalendarSelectedIDsKey = "settings_google_calendar_selected_ids"
    private static let settingsRemindersImportListIDKey = "settings_reminders_import_list_id"
    private static let settingsLocationFavoritesKey = "settings_location_favorites_v1"
    private static let infoGoogleCalendarClientIDKey = "GOOGLE_OAUTH_CLIENT_ID"
    private static let infoGoogleCalendarRedirectURIKey = "GOOGLE_OAUTH_REDIRECT_URI"
    private static let defaultGoogleCalendarRedirectURI = "todomd://oauth"
    private static let hashtagRegex = try? NSRegularExpression(pattern: "#([A-Za-z0-9_-]+)")

    init(logger: RuntimeLogging = ConsoleRuntimeLogger()) {
        self.logger = logger

        let resolvedRoot = Self.resolveRootURL()
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
        self.perspectivesRepository = PerspectivesRepository()

        loadCalendarSourceSelection()
        loadReminderListSelection()
        loadLocationFavorites()
        loadPerspectivesFromDisk()
        migrateLegacyPerspectivesFromSettingsIfNeeded()
        isCalendarConnected = googleCalendarService.isConnected
        configureLifecycleObservers()
        startMetadataQuery()
        refresh()
    }

    deinit {
        metadataRefreshWorkItem?.cancel()

        let center = NotificationCenter.default
        for token in metadataObserverTokens {
            center.removeObserver(token)
        }
        for token in lifecycleObserverTokens {
            center.removeObserver(token)
        }
    }

    var rootFolderPath: String {
        rootURL.path
    }

    func reloadStorageLocation() {
        _ = reconfigureStorageIfNeeded(force: true)
        refresh()
    }

    func refresh() {
        do {
            loadPerspectivesFromDisk()
            let sync = try fileWatcher.synchronize()
            let canonicalLoad = try loadCanonicalRecordsBestEffort(timestamp: sync.summary.timestamp)
            var canonicalRecords = canonicalLoad.records

            let backfilledRefCount = try backfillMissingRefs(in: canonicalRecords)
            if backfilledRefCount > 0 {
                canonicalRecords = try repository.loadAll()
            }

            let autoUnblockedPaths = try autoResolveBlockedDependencies(in: canonicalRecords)
            if !autoUnblockedPaths.isEmpty {
                canonicalRecords = try repository.loadAll()
                notifyAutoUnblockedTasksIfEnabled(paths: autoUnblockedPaths, records: canonicalRecords)
            }

            let completionMetadataUpdates = try inferCompletionMetadata(in: canonicalRecords)
            if completionMetadataUpdates > 0 {
                canonicalRecords = try repository.loadAll()
            }

            canonicalByPath = Dictionary(uniqueKeysWithValues: canonicalRecords.map { ($0.identity.path, $0) })

            let indexStart = ContinuousClock.now
#if canImport(SwiftData)
            do {
                try syncSwiftDataIndex(from: canonicalRecords)
                allIndexedRecords = try loadAllFromSwiftDataIndex()
            } catch {
                logger.error("Index sync failed; using canonical records", metadata: ["error": error.localizedDescription])
                allIndexedRecords = canonicalRecords
            }
#else
            allIndexedRecords = canonicalRecords
#endif
            let indexMilliseconds = elapsedMilliseconds(since: indexStart)

            diagnostics = mergedParseDiagnostics(
                watcherDiagnostics: fileWatcher.parseDiagnostics,
                fullScanDiagnostics: canonicalLoad.failures
            )
            conflicts = buildConflictSummaries(from: sync.events)

            let queryMilliseconds = applyCurrentViewFilter()

            let planner = notificationPlannerForCurrentSettings()
            let enumerateMilliseconds = fileWatcher.lastPerformance?.enumerateMilliseconds ?? 0
            let parseMilliseconds = fileWatcher.lastPerformance?.parseMilliseconds ?? 0
            counters = RuntimeCounters(
                lastSync: sync.summary.timestamp,
                totalFilesIndexed: allIndexedRecords.count,
                parseFailureCount: diagnostics.count,
                pendingNotificationCount: canonicalRecords.flatMap { planner.planNotifications(for: $0) }.count
                    + canonicalRecords.filter { record in
                        let status = record.document.frontmatter.status
                        return (status == .todo || status == .inProgress) && record.document.frontmatter.locationReminder != nil
                    }.count,
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
            let hasLocationReminders = canonicalRecords.contains { $0.document.frontmatter.locationReminder != nil }
            Task {
                await notificationScheduler.requestAuthorizationIfNeeded(requestLocation: hasLocationReminders)
                await notificationScheduler.synchronize(records: canonicalRecords, planner: planner)
            }
#endif

            scheduleCalendarRefresh()
        } catch {
            logger.error("Refresh failed", metadata: ["error": error.localizedDescription])
        }
    }

    private func loadCanonicalRecordsBestEffort(timestamp: Date) throws -> (records: [TaskRecord], failures: [ParseFailureDiagnostic]) {
        let urls = try TaskFileIO().enumerateMarkdownFiles(rootURL: rootURL)
        var records: [TaskRecord] = []
        var failures: [ParseFailureDiagnostic] = []
        records.reserveCapacity(urls.count)

        for url in urls {
            do {
                records.append(try repository.load(path: url.path))
            } catch {
                failures.append(ParseFailureDiagnostic(path: url.path, reason: error.localizedDescription, timestamp: timestamp))
            }
        }

        return (records, failures)
    }

    private func mergedParseDiagnostics(
        watcherDiagnostics: [ParseFailureDiagnostic],
        fullScanDiagnostics: [ParseFailureDiagnostic]
    ) -> [ParseFailureDiagnostic] {
        var byKey: [String: ParseFailureDiagnostic] = [:]
        for diagnostic in watcherDiagnostics + fullScanDiagnostics {
            let key = "\(diagnostic.path)|\(diagnostic.reason)"
            if let existing = byKey[key], existing.timestamp >= diagnostic.timestamp {
                continue
            }
            byKey[key] = diagnostic
        }

        return byKey.values.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp > rhs.timestamp
            }
            return lhs.path < rhs.path
        }
    }

    private func backfillMissingRefs(in records: [TaskRecord]) throws -> Int {
        let generator = TaskRefGenerator()
        var existingRefs: Set<String> = Set(records.compactMap { record in
            guard let ref = record.document.frontmatter.ref?.trimmingCharacters(in: .whitespacesAndNewlines),
                  TaskRefGenerator.isValid(ref: ref) else {
                return nil
            }
            return ref
        })

        var backfilledCount = 0
        for record in records.sorted(by: { $0.identity.path < $1.identity.path }) {
            let existing = record.document.frontmatter.ref?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if TaskRefGenerator.isValid(ref: existing) {
                existingRefs.insert(existing)
                continue
            }

            let generated = generator.generate(existingRefs: existingRefs)
            existingRefs.insert(generated)
            do {
                let updated = try repository.update(path: record.identity.path) { document in
                    document.frontmatter.ref = generated
                }
                markSelfWrite(path: updated.identity.path)
                backfilledCount += 1
            } catch {
                logger.error("Ref backfill failed", metadata: [
                    "path": record.identity.path,
                    "error": error.localizedDescription
                ])
            }
        }

        return backfilledCount
    }

    private func autoResolveBlockedDependencies(in records: [TaskRecord]) throws -> [String] {
        let recordsByRef = Dictionary(uniqueKeysWithValues: records.compactMap { record -> (String, TaskRecord)? in
            guard let ref = record.document.frontmatter.ref?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !ref.isEmpty else {
                return nil
            }
            return (ref, record)
        })

        var fullyUnblockedPaths: [String] = []

        for record in records {
            guard case .refs(let refs) = record.document.frontmatter.blockedBy else { continue }
            guard !refs.isEmpty else { continue }

            let unresolvedRefs = refs.filter { ref in
                guard let blocker = recordsByRef[ref] else {
                    return false
                }
                let status = blocker.document.frontmatter.status
                return status != .done && status != .cancelled
            }

            if unresolvedRefs == refs {
                continue
            }

            do {
                let updated = try repository.update(path: record.identity.path) { document in
                    if unresolvedRefs.isEmpty {
                        document.frontmatter.blockedBy = nil
                    } else {
                        document.frontmatter.blockedBy = .refs(unresolvedRefs)
                    }
                }
                markSelfWrite(path: updated.identity.path)
                if unresolvedRefs.isEmpty {
                    fullyUnblockedPaths.append(updated.identity.path)
                }
            } catch {
                logger.error("Auto-unblock update failed", metadata: [
                    "path": record.identity.path,
                    "error": error.localizedDescription
                ])
            }
        }

        return fullyUnblockedPaths
    }

    private func inferCompletionMetadata(in records: [TaskRecord]) throws -> Int {
        var updatedCount = 0

        for record in records {
            let frontmatter = record.document.frontmatter
            let isCompleted = frontmatter.status == .done || frontmatter.status == .cancelled

            if isCompleted {
                let needsCompletedAt = frontmatter.completed == nil
                let completedByText = frontmatter.completedBy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let needsCompletedBy = completedByText.isEmpty
                guard needsCompletedAt || needsCompletedBy else { continue }

                let inferredCompletedBy: String = {
                    let assignee = frontmatter.assignee?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !assignee.isEmpty { return assignee }
                    let source = frontmatter.source.trimmingCharacters(in: .whitespacesAndNewlines)
                    return source.isEmpty ? "unknown" : source
                }()

                do {
                    let updated = try repository.update(path: record.identity.path) { document in
                        if document.frontmatter.completed == nil {
                            document.frontmatter.completed = document.frontmatter.modified ?? Date()
                        }
                        let completedBy = document.frontmatter.completedBy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if completedBy.isEmpty {
                            document.frontmatter.completedBy = inferredCompletedBy
                        }
                    }
                    markSelfWrite(path: updated.identity.path)
                    updatedCount += 1
                } catch {
                    logger.error("Completion metadata inference failed", metadata: [
                        "path": record.identity.path,
                        "error": error.localizedDescription
                    ])
                }
                continue
            }

            if frontmatter.completed == nil && frontmatter.completedBy == nil {
                continue
            }

            do {
                let updated = try repository.update(path: record.identity.path) { document in
                    document.frontmatter.completed = nil
                    document.frontmatter.completedBy = nil
                }
                markSelfWrite(path: updated.identity.path)
                updatedCount += 1
            } catch {
                logger.error("Completion metadata clear failed", metadata: [
                    "path": record.identity.path,
                    "error": error.localizedDescription
                ])
            }
        }

        return updatedCount
    }

#if canImport(UserNotifications)
    private func notifyAutoUnblockedTasksIfEnabled(paths: [String], records: [TaskRecord]) {
        let shouldNotify = UserDefaults.standard.object(forKey: Self.settingsNotifyAutoUnblockedKey) as? Bool ?? true
        guard shouldNotify else { return }

        let byPath = Dictionary(uniqueKeysWithValues: records.map { ($0.identity.path, $0) })
        let uniquePaths = Array(Set(paths))

        Task {
            for path in uniquePaths {
                guard let record = byPath[path] else { continue }
                await notificationScheduler.scheduleAutoUnblockedNotification(
                    taskPath: path,
                    title: record.document.frontmatter.title
                )
            }
        }
    }
#else
    private func notifyAutoUnblockedTasksIfEnabled(paths: [String], records: [TaskRecord]) {
        _ = paths
        _ = records
    }
#endif

    @discardableResult
    private func reconfigureStorageIfNeeded(force: Bool = false) -> Bool {
        let resolvedRoot = Self.resolveRootURL()
        let normalizedResolvedRoot = resolvedRoot.standardizedFileURL.resolvingSymlinksInPath()
        let normalizedCurrentRoot = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        guard force || normalizedResolvedRoot != normalizedCurrentRoot else {
            return false
        }

        stopMetadataQuery()

        rootURL = normalizedResolvedRoot
        repository = FileTaskRepository(rootURL: rootURL)
        fileWatcher = FileWatcherService(rootURL: rootURL, repository: repository)
        manualOrderService = ManualOrderService(rootURL: rootURL)
        perspectivesRepository = PerspectivesRepository()

        canonicalByPath = [:]
        allIndexedRecords = []
        records = []
        diagnostics = []
        conflicts = []
        cachedPerspectivesDocument = PerspectivesDocument()
        perspectives = []
        perspectivesWarningMessage = nil
        loadPerspectivesFromDisk()

        startMetadataQuery()
        return true
    }

    private static func resolveRootURL() -> URL {
        let folderLocator = TaskFolderLocator()
        if let resolved = try? folderLocator.ensureFolderExists() {
            return resolved.standardizedFileURL.resolvingSymlinksInPath()
        }

        let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("todo.md", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback.standardizedFileURL.resolvingSymlinksInPath()
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

    func upcomingSections(today: LocalDate = LocalDate.today(in: .current)) -> [UpcomingSection] {
        let upcoming = allIndexedRecords.filter {
            queryEngine.matches($0, view: .builtIn(.upcoming), today: today)
        }
        var grouped: [LocalDate: [TaskRecord]] = [:]

        for record in upcoming {
            guard let groupDate = upcomingGroupDate(for: record, today: today) else { continue }
            grouped[groupDate, default: []].append(record)
        }

        return grouped.keys.sorted().map { date in
            let recordsForDate = grouped[date] ?? []
            let ordered = manualOrderService.ordered(records: recordsForDate, view: .builtIn(.upcoming))
                .sorted { lhs, rhs in
                    let leftDue = lhs.document.frontmatter.due
                    let rightDue = rhs.document.frontmatter.due
                    switch (leftDue, rightDue) {
                    case let (l?, r?):
                        return l < r
                    case (.some, .none):
                        return true
                    case (.none, .some):
                        return false
                    case (.none, .none):
                        return lhs.document.frontmatter.created < rhs.document.frontmatter.created
                    }
                }
            return UpcomingSection(date: date, records: ordered)
        }
    }

    func availableAreas() -> [String] {
        Set(allIndexedRecords.compactMap { $0.document.frontmatter.area?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func availableTags() -> [String] {
        Set(allIndexedRecords.flatMap { $0.document.frontmatter.tags }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func searchRecords(query: String, limit: Int = 150) -> [TaskRecord] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }
        let lowered = normalized.lowercased()

        let matches = allIndexedRecords.filter { record in
            let frontmatter = record.document.frontmatter
            let components: [String] = [
                frontmatter.title,
                frontmatter.description ?? "",
                frontmatter.area ?? "",
                frontmatter.project ?? "",
                frontmatter.source,
                frontmatter.tags.joined(separator: " "),
                record.identity.filename
            ]

            return components.contains { $0.lowercased().contains(lowered) }
        }

        let ordered = manualOrderService.ordered(records: matches, view: selectedView)
        if ordered.count <= limit {
            return ordered
        }
        return Array(ordered.prefix(limit))
    }

    func allProjects() -> [String] {
        Set(allIndexedRecords.compactMap { $0.document.frontmatter.project?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func availableProjects(inArea area: String?) -> [String] {
        let normalizedArea = area?.trimmingCharacters(in: .whitespacesAndNewlines)
        let projects = allIndexedRecords.filter { record in
            guard let normalizedArea, !normalizedArea.isEmpty else { return true }
            return record.document.frontmatter.area == normalizedArea
        }.compactMap { $0.document.frontmatter.project?.trimmingCharacters(in: .whitespacesAndNewlines) }

        return Set(projects.filter { !$0.isEmpty })
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func projectsByArea() -> [(area: String, projects: [String])] {
        availableAreas().map { area in
            (area: area, projects: availableProjects(inArea: area))
        }
    }

    func savePerspective(_ perspective: PerspectiveDefinition) {
        let trimmedName = perspective.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(100)
        guard !trimmedName.isEmpty else { return }

        var updated = perspective
        updated.name = String(trimmedName)
        updated.icon = updated.icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "list.bullet" : updated.icon
        if let index = perspectives.firstIndex(where: { $0.id == updated.id }) {
            perspectives[index] = updated
        } else {
            perspectives.append(updated)
        }
        persistPerspectivesToDisk()
        _ = applyCurrentViewFilter()
    }

    func createPerspective(name: String) -> PerspectiveDefinition {
        let sanitized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let perspective = PerspectiveDefinition(name: sanitized.isEmpty ? "Untitled Perspective" : sanitized)
        perspectives.append(perspective)
        persistPerspectivesToDisk()
        _ = applyCurrentViewFilter()
        return perspective
    }

    @discardableResult
    func duplicatePerspective(id: String) -> PerspectiveDefinition? {
        guard let index = perspectives.firstIndex(where: { $0.id == id }) else { return nil }
        let original = perspectives[index]
        var duplicate = original
        duplicate.id = UUID().uuidString
        duplicate.name = "\(original.name) Copy"
        perspectives.insert(duplicate, at: index + 1)
        persistPerspectivesToDisk()
        _ = applyCurrentViewFilter()
        return duplicate
    }

    func builtInPerspectiveDefinition(for view: BuiltInView) -> PerspectiveDefinition {
        let activeStatusesRule = PerspectiveRule(
            field: .status,
            operator: .in,
            jsonValue: .array([.string(TaskStatus.todo.rawValue), .string(TaskStatus.inProgress.rawValue), .string(TaskStatus.someday.rawValue)])
        )
        let completedStatusesRule = PerspectiveRule(
            field: .status,
            operator: .in,
            jsonValue: .array([.string(TaskStatus.done.rawValue), .string(TaskStatus.cancelled.rawValue)])
        )

        switch view {
        case .inbox:
            return PerspectiveDefinition(
                id: "builtin.inbox",
                name: "Inbox",
                icon: "tray",
                rules: PerspectiveRuleGroup(
                    operator: .and,
                    conditions: [
                        .rule(activeStatusesRule),
                        .rule(PerspectiveRule(field: .area, operator: .isNotSet)),
                        .rule(PerspectiveRule(field: .project, operator: .isNotSet)),
                        .group(PerspectiveRuleGroup(operator: .not, conditions: [.rule(completedStatusesRule)]))
                    ]
                )
            )
        case .myTasks:
            return PerspectiveDefinition(
                id: "builtin.my-tasks",
                name: "My Tasks",
                icon: "person",
                rules: PerspectiveRuleGroup(
                    operator: .and,
                    conditions: [
                        .rule(PerspectiveRule(
                            field: .status,
                            operator: .in,
                            jsonValue: .array([.string(TaskStatus.todo.rawValue), .string(TaskStatus.inProgress.rawValue)])
                        )),
                        .group(PerspectiveRuleGroup(
                            operator: .or,
                            conditions: [
                                .rule(PerspectiveRule(field: .assignee, operator: .isNil)),
                                .rule(PerspectiveRule(field: .assignee, operator: .equals, value: "user"))
                            ]
                        ))
                    ]
                )
            )
        case .delegated:
            return PerspectiveDefinition(
                id: "builtin.delegated",
                name: "Delegated",
                icon: "person.2",
                rules: PerspectiveRuleGroup(
                    operator: .and,
                    conditions: [
                        .rule(PerspectiveRule(
                            field: .status,
                            operator: .in,
                            jsonValue: .array([.string(TaskStatus.todo.rawValue), .string(TaskStatus.inProgress.rawValue)])
                        )),
                        .rule(PerspectiveRule(field: .assignee, operator: .isNotNil)),
                        .rule(PerspectiveRule(field: .assignee, operator: .notEquals, value: "user"))
                    ]
                )
            )
        case .today:
            return PerspectiveDefinition(
                id: "builtin.today",
                name: "Today",
                icon: "sun.max",
                rules: PerspectiveRuleGroup(
                    operator: .and,
                    conditions: [
                        .group(PerspectiveRuleGroup(
                            operator: .or,
                            conditions: [
                                .rule(PerspectiveRule(field: .due, operator: .onToday)),
                                .rule(PerspectiveRule(field: .scheduled, operator: .onToday)),
                                .rule(PerspectiveRule(field: .defer, operator: .onOrBefore, jsonValue: .object(["op": .string("today")]))
                                )
                            ]
                        )),
                        .group(PerspectiveRuleGroup(
                            operator: .or,
                            conditions: [
                                .rule(PerspectiveRule(field: .assignee, operator: .isNil)),
                                .rule(PerspectiveRule(field: .assignee, operator: .equals, value: "user"))
                            ]
                        )),
                        .group(PerspectiveRuleGroup(operator: .not, conditions: [.rule(completedStatusesRule)]))
                    ]
                )
            )
        case .upcoming:
            return PerspectiveDefinition(
                id: "builtin.upcoming",
                name: "Upcoming",
                icon: "calendar",
                rules: PerspectiveRuleGroup(
                    operator: .and,
                    conditions: [
                        .group(PerspectiveRuleGroup(
                            operator: .or,
                            conditions: [
                                .rule(PerspectiveRule(field: .due, operator: .afterToday)),
                                .rule(PerspectiveRule(field: .scheduled, operator: .afterToday))
                            ]
                        )),
                        .group(PerspectiveRuleGroup(operator: .not, conditions: [.rule(completedStatusesRule)]))
                    ]
                )
            )
        case .anytime:
            return PerspectiveDefinition(
                id: "builtin.anytime",
                name: "Anytime",
                icon: "list.bullet",
                rules: PerspectiveRuleGroup(
                    operator: .and,
                    conditions: [
                        .group(PerspectiveRuleGroup(
                            operator: .or,
                            conditions: [
                                .rule(PerspectiveRule(field: .status, operator: .equals, value: TaskStatus.todo.rawValue)),
                                .rule(PerspectiveRule(field: .status, operator: .equals, value: TaskStatus.inProgress.rawValue))
                            ]
                        )),
                        .group(PerspectiveRuleGroup(
                            operator: .or,
                            conditions: [
                                .rule(PerspectiveRule(field: .defer, operator: .isNotSet)),
                                .rule(PerspectiveRule(field: .defer, operator: .onOrBefore, jsonValue: .object(["op": .string("today")]))
                                )
                            ]
                        ))
                    ]
                )
            )
        case .someday:
            return PerspectiveDefinition(
                id: "builtin.someday",
                name: "Someday",
                icon: "clock",
                rules: PerspectiveRuleGroup(
                    operator: .and,
                    conditions: [.rule(PerspectiveRule(field: .status, operator: .equals, value: TaskStatus.someday.rawValue))]
                )
            )
        case .flagged:
            return PerspectiveDefinition(
                id: "builtin.flagged",
                name: "Flagged",
                icon: "flag",
                rules: PerspectiveRuleGroup(
                    operator: .and,
                    conditions: [
                        .rule(PerspectiveRule(field: .flagged, operator: .isTrue)),
                        .group(PerspectiveRuleGroup(operator: .not, conditions: [.rule(completedStatusesRule)]))
                    ]
                )
            )
        }
    }

    @discardableResult
    func duplicateBuiltInPerspective(_ view: BuiltInView) -> PerspectiveDefinition {
        var duplicate = builtInPerspectiveDefinition(for: view)
        duplicate.id = UUID().uuidString
        duplicate.name = "\(duplicate.name) Copy"
        if let index = perspectives.firstIndex(where: { $0.name == builtInPerspectiveDefinition(for: view).name }) {
            perspectives.insert(duplicate, at: index + 1)
        } else {
            perspectives.append(duplicate)
        }
        persistPerspectivesToDisk()
        _ = applyCurrentViewFilter()
        return duplicate
    }

    func deletePerspective(id: String) {
        perspectives.removeAll { $0.id == id }
        if perspectiveID(for: selectedView) == id {
            selectedView = .builtIn(.inbox)
        }
        persistPerspectivesToDisk()
        _ = applyCurrentViewFilter()
    }

    func movePerspectives(from source: IndexSet, to destination: Int) {
        let moving = source.sorted().map { perspectives[$0] }
        let remaining = perspectives.enumerated()
            .filter { !source.contains($0.offset) }
            .map(\.element)
        var reordered = remaining
        let safeDestination = min(max(0, destination), reordered.count)
        reordered.insert(contentsOf: moving, at: safeDestination)
        perspectives = reordered
        persistPerspectivesToDisk()
    }

    func perspectiveViewIdentifier(for perspectiveID: String) -> ViewIdentifier {
        .custom("perspective:\(perspectiveID)")
    }

    func perspectiveName(for view: ViewIdentifier) -> String? {
        guard let id = perspectiveID(for: view) else { return nil }
        return perspectives.first(where: { $0.id == id })?.name
    }

    func canManuallyReorderSelectedView() -> Bool {
        guard let id = perspectiveID(for: selectedView),
              let perspective = perspectives.first(where: { $0.id == id }) else {
            return true
        }
        return perspective.sort.field == .manual
    }

    func clearPendingNavigationPath() {
        navigationTaskPath = nil
    }

    func clearQuickEntryRequest() {
        shouldPresentQuickEntry = false
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
            dueDate: dateFromLocalDate(frontmatter.due) ?? Date(),
            hasDueTime: frontmatter.dueTime != nil,
            dueTime: dateFromLocalTime(frontmatter.dueTime) ?? Date(),
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

    @discardableResult
    func updateTask(path: String, editState: TaskEditState) -> Bool {
        let optimisticRecord = record(for: path).map { current in
            var copy = current
            apply(editState: editState, to: &copy.document)
            return copy
        }
        if let optimisticRecord {
            canonicalByPath[path] = optimisticRecord
            if let index = allIndexedRecords.firstIndex(where: { $0.identity.path == path }) {
                allIndexedRecords[index] = optimisticRecord
            }
            _ = applyCurrentViewFilter()
        }

        do {
            let updated = try repository.update(path: path) { document in
                apply(editState: editState, to: &document)
            }

            markSelfWrite(path: updated.identity.path)
            refresh()
            return true
        } catch {
            refresh()
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
    func setDefer(path: String, date: Date?) -> Bool {
        do {
            let updated = try repository.update(path: path) { document in
                if let date {
                    document.frontmatter.defer = localDateFromDate(date)
                } else {
                    document.frontmatter.defer = nil
                }
                document.frontmatter.modified = Date()
            }
            markSelfWrite(path: updated.identity.path)
            refresh()
            return true
        } catch {
            logger.error("Set defer failed", metadata: ["path": path, "error": error.localizedDescription])
            return false
        }
    }

    @discardableResult
    func setPriority(path: String, priority: TaskPriority) -> Bool {
        do {
            let updated = try repository.update(path: path) { document in
                document.frontmatter.priority = priority
                document.frontmatter.modified = Date()
            }
            markSelfWrite(path: updated.identity.path)
            refresh()
            return true
        } catch {
            logger.error("Set priority failed", metadata: ["path": path, "error": error.localizedDescription])
            return false
        }
    }

    @discardableResult
    func moveTask(path: String, area: String?, project: String?) -> Bool {
        do {
            let updated = try repository.update(path: path) { document in
                document.frontmatter.area = area?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                document.frontmatter.project = project?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                document.frontmatter.modified = Date()
            }
            markSelfWrite(path: updated.identity.path)
            refresh()
            return true
        } catch {
            logger.error("Move task failed", metadata: ["path": path, "error": error.localizedDescription])
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

    @discardableResult
    func setBlocked(path: String, blockedBy: TaskBlockedBy?) -> Bool {
        do {
            let updated = try repository.update(path: path) { document in
                document.frontmatter.blockedBy = blockedBy
                document.frontmatter.modified = Date()
            }
            markSelfWrite(path: updated.identity.path)
            refresh()
            return true
        } catch {
            logger.error("Set blocked failed", metadata: ["path": path, "error": error.localizedDescription])
            return false
        }
    }

    func createTask(
        title: String,
        naturalDate: String?,
        tags: [String] = [],
        explicitDue: LocalDate? = nil,
        explicitDueTime: LocalTime? = nil,
        priorityOverride: TaskPriority? = nil,
        flagged: Bool = false,
        area: String? = nil,
        project: String? = nil,
        defaultView: BuiltInView? = nil
    ) {
        let destinationView = defaultView ?? BuiltInView(rawValue: UserDefaults.standard.string(forKey: Self.settingsQuickEntryDefaultViewKey) ?? "")
            ?? .inbox
        var due = explicitDue
        if due == nil, let naturalDate, !naturalDate.isEmpty {
            due = dateParser.parse(naturalDate)
        }
        if due == nil, destinationView == .today {
            due = LocalDate.today(in: .current)
        }

        let priorityRaw = UserDefaults.standard.string(forKey: Self.settingsDefaultPriorityKey) ?? TaskPriority.none.rawValue
        let defaultPriority = TaskPriority(rawValue: priorityRaw) ?? .none
        let resolvedPriority = priorityOverride ?? defaultPriority
        let normalizedTags = normalizeTags(tags)
        let normalizedArea = area?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let normalizedProject = project?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        let now = Date()
        let frontmatter = TaskFrontmatterV1(
            title: title,
            status: .todo,
            due: due,
            dueTime: due == nil ? nil : explicitDueTime,
            priority: resolvedPriority,
            flagged: flagged,
            area: normalizedArea,
            project: normalizedProject,
            tags: normalizedTags,
            created: now,
            modified: now,
            source: "user"
        )

        let document = TaskDocument(frontmatter: frontmatter, body: "")
        persistTaskAsync(document: document, errorContext: "Task creation failed")
    }

    @discardableResult
    func createTask(
        fromQuickEntryText text: String,
        explicitDue: LocalDate? = nil,
        explicitDueTime: LocalTime? = nil,
        priority: TaskPriority? = nil,
        flagged: Bool = false,
        tags: [String] = [],
        area: String? = nil,
        project: String? = nil,
        defaultView: BuiltInView? = nil
    ) -> Bool {
        guard let parsed = quickEntryParser.parse(text) else {
            return false
        }

        let mergedTags = normalizeTags(parsed.tags + tags)
        createTask(
            title: parsed.title,
            naturalDate: nil,
            tags: mergedTags,
            explicitDue: explicitDue ?? parsed.due,
            explicitDueTime: explicitDueTime,
            priorityOverride: priority,
            flagged: flagged,
            area: area,
            project: project,
            defaultView: defaultView
        )
        return true
    }

    func createTask(request: TaskCreateRequest) {
        let now = Date()
        let frontmatter = TaskFrontmatterV1(
            title: request.title,
            status: .todo,
            due: request.due,
            dueTime: request.dueTime,
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
        persistTaskAsync(document: document, errorContext: "Task creation from request failed")
    }

    private func normalizeTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { rawTag in
            let normalized = rawTag
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !normalized.isEmpty, !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return normalized
        }
    }

    func complete(path: String) {
        do {
            let now = Date()
            let current = try repository.load(path: path)
            let recurrence = current.document.frontmatter.recurrence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let shouldRepeat = !recurrence.isEmpty && current.document.frontmatter.status != .done && current.document.frontmatter.status != .cancelled

            if shouldRepeat {
                let result = try repository.completeRepeating(path: path, at: now, completedBy: "user")
                archiveCompletedFilesIfEnabled(paths: [result.completed.identity.path])
                markSelfWrite(path: result.completed.identity.path)
                markSelfWrite(path: result.next.identity.path)
            } else {
                let completed = try repository.complete(path: path, at: now, completedBy: "user")
                archiveCompletedFilesIfEnabled(paths: [completed.identity.path])
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
        if let perspectiveID = perspectiveID(for: selectedView),
           let index = perspectives.firstIndex(where: { $0.id == perspectiveID }) {
            perspectives[index].manualOrder = filenames
            perspectives[index].sort = PerspectiveSort(field: .manual, direction: .asc)
            persistPerspectivesToDisk()
            applyCurrentViewFilter()
            return
        }

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
            case .showTask(let path):
                navigationTaskPath = path
            case .showTaskRef(let ref):
                if let path = pathForTaskRef(ref) {
                    navigationTaskPath = path
                } else {
                    refresh()
                    navigationTaskPath = pathForTaskRef(ref)
                }
            case .quickAdd:
                shouldPresentQuickEntry = true
            }
        } catch {
            logger.error("URL routing failed", metadata: ["url": url.absoluteString, "error": error.localizedDescription])
            urlRoutingErrorMessage = "Could not open link: \(error.localizedDescription)"
        }
    }

    func deleteUnparseable(path: String) {
        _ = deleteTask(path: path)
    }

    private func pathForTaskRef(_ ref: String) -> String? {
        let normalized = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return canonicalByPath.values.first(where: { $0.document.frontmatter.ref == normalized })?.identity.path
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

    func refreshReminderListsIfNeeded() async {
        guard reminderLists.isEmpty else { return }
        await refreshReminderLists()
    }

    func refreshReminderLists() async {
        do {
            let lists = try await remindersImportService.fetchLists()
            reminderLists = lists
            syncSelectedReminderList(with: lists)
            if lists.isEmpty {
                remindersImportStatusMessage = "No Reminders lists are available to import from."
            } else if remindersImportStatusMessage == RemindersImportServiceError.accessDenied.localizedDescription {
                remindersImportStatusMessage = nil
            }
        } catch {
            reminderLists = []
            selectedReminderListID = nil
            remindersImportStatusMessage = error.localizedDescription
            persistReminderListSelection()
        }
    }

    func setReminderListSelected(id: String) {
        guard reminderLists.contains(where: { $0.id == id }) else { return }
        selectedReminderListID = id
        persistReminderListSelection()
    }

    @discardableResult
    func saveLocationFavorite(name: String, latitude: Double, longitude: Double, radiusMeters: Int) -> LocationFavorite? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        guard trimmedName.count <= TaskValidation.maxLocationNameLength else { return nil }
        guard (-90.0...90.0).contains(latitude), (-180.0...180.0).contains(longitude) else { return nil }

        let normalizedRadius = max(50, min(1_000, radiusMeters))
        if let existingIndex = locationFavorites.firstIndex(where: {
            $0.name.compare(trimmedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            let favoriteID = locationFavorites[existingIndex].id
            locationFavorites[existingIndex].name = trimmedName
            locationFavorites[existingIndex].latitude = latitude
            locationFavorites[existingIndex].longitude = longitude
            locationFavorites[existingIndex].radiusMeters = normalizedRadius
            sortLocationFavorites()
            persistLocationFavorites()
            return locationFavorites.first(where: { $0.id == favoriteID })
        }

        let favorite = LocationFavorite(
            name: trimmedName,
            latitude: latitude,
            longitude: longitude,
            radiusMeters: normalizedRadius
        )
        locationFavorites.append(favorite)
        sortLocationFavorites()
        persistLocationFavorites()
        return locationFavorites.first(where: { $0.id == favorite.id })
    }

    func deleteLocationFavorite(id: String) {
        let originalCount = locationFavorites.count
        locationFavorites.removeAll { $0.id == id }
        guard locationFavorites.count != originalCount else { return }
        persistLocationFavorites()
    }

    func importFromReminders() async {
        guard !isRemindersImporting else { return }
        isRemindersImporting = true
        defer { isRemindersImporting = false }

        if reminderLists.isEmpty {
            await refreshReminderLists()
        }

        do {
            let reminders = try await remindersImportService.fetchIncompleteReminders(
                calendarID: selectedReminderListID
            )
            guard !reminders.isEmpty else {
                remindersImportStatusMessage = "No incomplete reminders found in the selected list."
                return
            }

            let candidates = reminders.compactMap(makeReminderImportCandidate(from:))
            let skippedCount = max(0, reminders.count - candidates.count)
            guard !candidates.isEmpty else {
                remindersImportStatusMessage = "No reminders could be converted into valid tasks."
                return
            }

            suppressMetadataRefresh(for: 3)
            let createResult = await createReminderTasks(candidates: candidates, rootPath: rootURL.path)

            for created in createResult.created {
                markSelfWrite(path: created.path)
            }

            if !createResult.created.isEmpty {
                refresh()
            }

            let importedReminderIDs = createResult.created.map(\.reminderID)
            var deletionResult: ReminderDeletionResult?
            var deletionError: String?
            if !importedReminderIDs.isEmpty {
                do {
                    deletionResult = try remindersImportService.removeReminders(withIDs: importedReminderIDs)
                } catch {
                    deletionError = error.localizedDescription
                }
            }

            var summary: [String] = []
            let importedCount = createResult.created.count
            if importedCount > 0 {
                summary.append("Imported \(importedCount) reminder\(importedCount == 1 ? "" : "s") as tasks.")
            }
            if let deletionResult {
                if deletionResult.removedCount == importedCount {
                    summary.append("Removed imported reminders from Apple Reminders.")
                } else {
                    summary.append(
                        "Removed \(deletionResult.removedCount) reminder\(deletionResult.removedCount == 1 ? "" : "s") from Apple Reminders."
                    )
                }
                if deletionResult.missingCount > 0 {
                    summary.append(
                        "\(deletionResult.missingCount) reminder\(deletionResult.missingCount == 1 ? "" : "s") could not be found for deletion."
                    )
                }
            } else if let deletionError {
                summary.append("Imported tasks but failed to remove reminders: \(deletionError)")
            }

            let failedCount = createResult.failedCount + skippedCount
            if failedCount > 0 {
                summary.append(
                    "\(failedCount) reminder\(failedCount == 1 ? "" : "s") were left in Reminders due to import errors."
                )
            }

            remindersImportStatusMessage = summary.joined(separator: " ")
        } catch {
            remindersImportStatusMessage = error.localizedDescription
        }
    }

    var isGoogleCalendarConfigured: Bool {
        googleCalendarClientID() != nil
    }

    func isCalendarSourceSelected(_ sourceID: String) -> Bool {
        selectedCalendarSourceIDs.contains(sourceID)
    }

    func setCalendarSourceSelected(sourceID: String, isSelected: Bool) {
        if isSelected {
            selectedCalendarSourceIDs.insert(sourceID)
        } else {
            selectedCalendarSourceIDs.remove(sourceID)
        }
        persistCalendarSourceSelection()
        scheduleCalendarRefresh(force: true)
    }

    func selectAllCalendarSources() {
        selectedCalendarSourceIDs = Set(calendarSources.map(\.id))
        persistCalendarSourceSelection()
        scheduleCalendarRefresh(force: true)
    }

    func connectGoogleCalendar() async {
        guard let clientID = googleCalendarClientID() else {
            calendarStatusMessage = "Google Calendar is not configured for this app build."
            return
        }

        let redirectURI = googleCalendarRedirectURI()
        isCalendarSyncing = true
        calendarStatusMessage = nil
        do {
            try await googleCalendarService.connect(clientID: clientID, redirectURI: redirectURI)
            isCalendarConnected = true
            await refreshCalendar(force: true)
        } catch {
            calendarStatusMessage = error.localizedDescription
        }
        isCalendarSyncing = false
    }

    func disconnectGoogleCalendar() {
        googleCalendarService.disconnect()
        isCalendarConnected = false
        calendarStatusMessage = nil
        calendarSources = []
        calendarTodayEvents = []
        calendarUpcomingSections = []
        lastCalendarSyncAt = nil
    }

    func refreshCalendar(force: Bool = false) async {
        let defaults = UserDefaults.standard
        let calendarEnabled = defaults.object(forKey: Self.settingsGoogleCalendarEnabledKey) as? Bool ?? true
        guard calendarEnabled else {
            calendarTodayEvents = []
            calendarUpcomingSections = []
            return
        }

        guard googleCalendarService.isConnected else {
            isCalendarConnected = false
            calendarTodayEvents = []
            calendarUpcomingSections = []
            return
        }

        let now = Date()
        if !force,
           let lastSync = lastCalendarSyncAt,
           now.timeIntervalSince(lastSync) < 60 {
            return
        }

        guard let clientID = googleCalendarClientID() else {
            calendarStatusMessage = "Google Calendar is not configured for this app build."
            return
        }

        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: now)
        guard let endDate = calendar.date(byAdding: .day, value: 30, to: startDate) else {
            return
        }

        let useSavedSelection = hasPersistedCalendarSourceSelection()
        let allowedCalendarIDs: Set<String>? = useSavedSelection ? selectedCalendarSourceIDs : nil

        isCalendarSyncing = true
        defer { isCalendarSyncing = false }

        do {
            let result = try await googleCalendarService.fetchUpcomingEvents(
                clientID: clientID,
                redirectURI: googleCalendarRedirectURI(),
                startDate: startDate,
                endDate: endDate,
                allowedCalendarIDs: allowedCalendarIDs
            )
            isCalendarConnected = true
            calendarStatusMessage = nil
            lastCalendarSyncAt = now

            calendarSources = result.sources.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            let availableSourceIDs = Set(calendarSources.map(\.id))
            if !useSavedSelection {
                selectedCalendarSourceIDs = availableSourceIDs
                persistCalendarSourceSelection()
            } else {
                let pruned = selectedCalendarSourceIDs.intersection(availableSourceIDs)
                if pruned != selectedCalendarSourceIDs {
                    selectedCalendarSourceIDs = pruned
                    persistCalendarSourceSelection()
                }
            }

            calendarTodayEvents = eventsForToday(result.events, today: startDate)
            calendarUpcomingSections = groupedUpcomingSections(result.events, today: startDate)
        } catch {
            calendarStatusMessage = error.localizedDescription
            if case GoogleCalendarServiceError.tokenUnavailable = error {
                isCalendarConnected = false
            }
        }
    }

    private func scheduleCalendarRefresh(force: Bool = false) {
        if force {
            calendarRefreshTask?.cancel()
            calendarRefreshTask = nil
        } else if calendarRefreshTask != nil {
            return
        }

        calendarRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refreshCalendar(force: force)
            self.calendarRefreshTask = nil
        }
    }

    private func googleCalendarRedirectURI() -> String {
        (Bundle.main.object(forInfoDictionaryKey: Self.infoGoogleCalendarRedirectURIKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? Self.defaultGoogleCalendarRedirectURI
    }

    private func googleCalendarClientID() -> String? {
        (Bundle.main.object(forInfoDictionaryKey: Self.infoGoogleCalendarClientIDKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private func hasPersistedCalendarSourceSelection() -> Bool {
        UserDefaults.standard.array(forKey: Self.settingsGoogleCalendarSelectedIDsKey) != nil
    }

    private func loadCalendarSourceSelection() {
        let defaults = UserDefaults.standard
        guard let ids = defaults.array(forKey: Self.settingsGoogleCalendarSelectedIDsKey) as? [String] else {
            selectedCalendarSourceIDs = []
            return
        }
        selectedCalendarSourceIDs = Set(ids)
    }

    private func persistCalendarSourceSelection() {
        let defaults = UserDefaults.standard
        defaults.set(Array(selectedCalendarSourceIDs).sorted(), forKey: Self.settingsGoogleCalendarSelectedIDsKey)
    }

    private func loadReminderListSelection() {
        selectedReminderListID = UserDefaults.standard.string(forKey: Self.settingsRemindersImportListIDKey)
    }

    private func loadLocationFavorites() {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: Self.settingsLocationFavoritesKey) else {
            locationFavorites = []
            return
        }

        guard let decoded = try? JSONDecoder().decode([LocationFavorite].self, from: data) else {
            locationFavorites = []
            return
        }

        locationFavorites = decoded.filter { favorite in
            let trimmedName = favorite.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmedName.isEmpty
                && trimmedName.count <= TaskValidation.maxLocationNameLength
                && (-90.0...90.0).contains(favorite.latitude)
                && (-180.0...180.0).contains(favorite.longitude)
                && (50...1_000).contains(favorite.radiusMeters)
        }
        sortLocationFavorites()
    }

    private func syncSelectedReminderList(with lists: [ReminderList]) {
        guard !lists.isEmpty else {
            selectedReminderListID = nil
            persistReminderListSelection()
            return
        }

        if let selectedReminderListID, lists.contains(where: { $0.id == selectedReminderListID }) {
            return
        }

        selectedReminderListID = lists.first?.id
        persistReminderListSelection()
    }

    private func persistReminderListSelection() {
        let defaults = UserDefaults.standard
        defaults.set(selectedReminderListID, forKey: Self.settingsRemindersImportListIDKey)
    }

    private func persistLocationFavorites() {
        let defaults = UserDefaults.standard
        guard let data = try? JSONEncoder().encode(locationFavorites) else { return }
        defaults.set(data, forKey: Self.settingsLocationFavoritesKey)
    }

    private func sortLocationFavorites() {
        locationFavorites.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func eventsForToday(_ events: [CalendarEventItem], today: Date) -> [CalendarEventItem] {
        let calendar = Calendar.current
        return events
            .filter { calendar.isDate($0.startDate, inSameDayAs: today) }
            .sorted(by: Self.calendarEventSort)
    }

    private func groupedUpcomingSections(_ events: [CalendarEventItem], today: Date) -> [CalendarDaySection] {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today)) ?? today

        var grouped: [Date: [CalendarEventItem]] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.startDate)
            guard day >= tomorrow else { continue }
            grouped[day, default: []].append(event)
        }

        return grouped.keys.sorted().map { day in
            let dayEvents = (grouped[day] ?? []).sorted(by: Self.calendarEventSort)
            return CalendarDaySection(date: day, events: dayEvents)
        }
    }

    private static func calendarEventSort(lhs: CalendarEventItem, rhs: CalendarEventItem) -> Bool {
        if lhs.startDate != rhs.startDate {
            return lhs.startDate < rhs.startDate
        }
        if lhs.isAllDay != rhs.isAllDay {
            return lhs.isAllDay && !rhs.isAllDay
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func migrateLegacyPerspectivesFromSettingsIfNeeded() {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: Self.settingsPerspectivesKey) else { return }
        let fileExists = FileManager.default.fileExists(atPath: perspectivesRepository.perspectivesURL(rootURL: rootURL).path)

        defer {
            defaults.removeObject(forKey: Self.settingsPerspectivesKey)
        }

        guard !fileExists,
              let decoded = try? JSONDecoder().decode([PerspectiveDefinition].self, from: data) else {
            return
        }

        perspectives = decoded
        persistPerspectivesToDisk()
    }

    private func loadPerspectivesFromDisk() {
        do {
            let loaded = try perspectivesRepository.load(rootURL: rootURL)
            cachedPerspectivesDocument = loaded
            let orderedIDs = orderedPerspectiveIDs(document: loaded)
            perspectives = orderedIDs.compactMap { loaded.perspectives[$0] }
            perspectivesWarningMessage = nil
        } catch {
            perspectivesWarningMessage = "Perspectives file has errors - using last valid version."
            _ = perspectivesRepository.backupCorruptedFile(rootURL: rootURL)
            logger.error("Failed to load perspectives", metadata: ["error": error.localizedDescription])
        }

        if let selectedPerspectiveID = perspectiveID(for: selectedView),
           !perspectives.contains(where: { $0.id == selectedPerspectiveID }) {
            selectedView = .builtIn(.inbox)
        }
    }

    private func persistPerspectivesToDisk() {
        var byID: [String: PerspectiveDefinition] = [:]
        for perspective in perspectives {
            byID[perspective.id] = perspective
        }

        cachedPerspectivesDocument.version = max(1, cachedPerspectivesDocument.version)
        cachedPerspectivesDocument.order = perspectives.map(\.id)
        cachedPerspectivesDocument.perspectives = byID

        do {
            try perspectivesRepository.save(cachedPerspectivesDocument, rootURL: rootURL)
            perspectivesWarningMessage = nil
        } catch {
            logger.error("Failed to persist perspectives", metadata: ["error": error.localizedDescription])
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

    private func perspectiveID(for view: ViewIdentifier) -> String? {
        guard case .custom(let rawID) = view else { return nil }
        let prefix = "perspective:"
        guard rawID.hasPrefix(prefix) else { return nil }
        let id = String(rawID.dropFirst(prefix.count))
        return id.isEmpty ? nil : id
    }

    @discardableResult
    private func applyCurrentViewFilter(today: LocalDate = LocalDate.today(in: .current)) -> Double {
        let start = ContinuousClock.now
        let filtered: [TaskRecord]
        let orderedRecords: [TaskRecord]
        if let perspectiveID = perspectiveID(for: selectedView),
           let perspective = perspectives.first(where: { $0.id == perspectiveID }) {
            filtered = allIndexedRecords.filter { perspectiveQueryEngine.matches($0, perspective: perspective, today: today) }
            orderedRecords = order(records: filtered, for: perspective, today: today)
        } else {
            filtered = allIndexedRecords.filter { queryEngine.matches($0, view: selectedView, today: today) }
            orderedRecords = manualOrderService.ordered(records: filtered, view: selectedView)
        }
        records = applyCompletionRetention(records: orderedRecords)
        return elapsedMilliseconds(since: start)
    }

    private func order(records: [TaskRecord], for perspective: PerspectiveDefinition, today: LocalDate) -> [TaskRecord] {
        switch perspective.sort.field {
        case .manual:
            return orderedByManualList(records: records, filenames: perspective.manualOrder)
        case .due:
            return records.sorted { compareOptionalDate($0.document.frontmatter.due, $1.document.frontmatter.due, fallback: ($0, $1)) }
        case .scheduled:
            return records.sorted { compareOptionalDate($0.document.frontmatter.scheduled, $1.document.frontmatter.scheduled, fallback: ($0, $1)) }
        case .defer:
            return records.sorted { compareOptionalDate($0.document.frontmatter.defer, $1.document.frontmatter.defer, fallback: ($0, $1)) }
        case .priority:
            return records.sorted { lhs, rhs in
                let left = priorityRank(lhs.document.frontmatter.priority)
                let right = priorityRank(rhs.document.frontmatter.priority)
                if left != right { return left > right }
                return compareOptionalDate(lhs.document.frontmatter.due, rhs.document.frontmatter.due, fallback: (lhs, rhs))
            }
        case .estimatedMinutes:
            return records.sorted { lhs, rhs in
                switch (lhs.document.frontmatter.estimatedMinutes, rhs.document.frontmatter.estimatedMinutes) {
                case let (l?, r?):
                    if l != r { return l < r }
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
            return records.sorted {
                $0.document.frontmatter.title.localizedCaseInsensitiveCompare($1.document.frontmatter.title) == .orderedAscending
            }
        case .created:
            return records.sorted { $0.document.frontmatter.created > $1.document.frontmatter.created }
        case .modified:
            return records.sorted { lhs, rhs in
                let left = lhs.document.frontmatter.modified ?? lhs.document.frontmatter.created
                let right = rhs.document.frontmatter.modified ?? rhs.document.frontmatter.created
                if left != right { return left > right }
                return lhs.document.frontmatter.title.localizedCaseInsensitiveCompare(rhs.document.frontmatter.title) == .orderedAscending
            }
        case .completed:
            return records.sorted { lhs, rhs in
                let left = lhs.document.frontmatter.completed ?? Date.distantPast
                let right = rhs.document.frontmatter.completed ?? Date.distantPast
                if left != right { return left > right }
                return lhs.document.frontmatter.title.localizedCaseInsensitiveCompare(rhs.document.frontmatter.title) == .orderedAscending
            }
        case .flagged:
            return records.sorted { lhs, rhs in
                if lhs.document.frontmatter.flagged != rhs.document.frontmatter.flagged {
                    return lhs.document.frontmatter.flagged && !rhs.document.frontmatter.flagged
                }
                return compareOptionalDate(lhs.document.frontmatter.due, rhs.document.frontmatter.due, fallback: (lhs, rhs))
            }
        case .unknown:
            return records
        }
    }

    private func orderedByManualList(records: [TaskRecord], filenames: [String]?) -> [TaskRecord] {
        guard let filenames, !filenames.isEmpty else {
            return manualOrderService.ordered(records: records, view: selectedView)
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
            if left != right { return left < right }
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
        case .high: return 4
        case .medium: return 3
        case .low: return 2
        case .none: return 1
        }
    }

    private func applyCompletionRetention(records: [TaskRecord]) -> [TaskRecord] {
        let retention = UserDefaults.standard.string(forKey: Self.settingsCompletedRetentionKey) ?? "forever"
        let cutoffDays: Int?
        switch retention {
        case "7d":
            cutoffDays = 7
        case "30d":
            cutoffDays = 30
        default:
            cutoffDays = nil
        }

        guard let cutoffDays else { return records }
        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -cutoffDays, to: Date()) else {
            return records
        }

        return records.filter { record in
            let status = record.document.frontmatter.status
            guard status == .done || status == .cancelled else { return true }
            guard let completed = record.document.frontmatter.completed else { return false }
            return completed >= cutoffDate
        }
    }

    private func upcomingGroupDate(for record: TaskRecord, today: LocalDate) -> LocalDate? {
        let frontmatter = record.document.frontmatter
        let candidates = [frontmatter.scheduled, frontmatter.due]
            .compactMap { $0 }
            .filter { $0 > today }
            .sorted()
        return candidates.first
    }

    private func archiveCompletedFilesIfEnabled(paths: [String]) {
        guard UserDefaults.standard.bool(forKey: Self.settingsArchiveCompletedKey) else { return }
        let fileManager = FileManager.default
        let archiveFolder = rootURL.appendingPathComponent("Archive", isDirectory: true)
        do {
            try fileManager.createDirectory(at: archiveFolder, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create archive folder", metadata: ["error": error.localizedDescription])
            return
        }

        for path in paths {
            let sourceURL = URL(fileURLWithPath: path)
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            var destinationURL = archiveFolder.appendingPathComponent(sourceURL.lastPathComponent)
            destinationURL = uniqueDestinationURL(for: destinationURL, fileManager: fileManager)
            do {
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
            } catch {
                logger.error("Failed to archive completed task", metadata: [
                    "source": sourceURL.path,
                    "destination": destinationURL.path,
                    "error": error.localizedDescription
                ])
            }
        }
    }

    private func uniqueDestinationURL(for url: URL, fileManager: FileManager) -> URL {
        guard fileManager.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let parent = url.deletingLastPathComponent()
        var suffix = 2
        while true {
            let filename = ext.isEmpty ? "\(base)-\(suffix)" : "\(base)-\(suffix).\(ext)"
            let candidate = parent.appendingPathComponent(filename)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }

    private func notificationPlannerForCurrentSettings() -> NotificationPlanner {
        let defaults = UserDefaults.standard
        let hour = defaults.object(forKey: Self.settingsNotificationHourKey) as? Int ?? 9
        let minute = defaults.object(forKey: Self.settingsNotificationMinuteKey) as? Int ?? 0
        let persistentEnabled = defaults.object(forKey: Self.settingsPersistentRemindersEnabledKey) as? Bool ?? false
        let persistentIntervalMinutes = defaults.object(forKey: Self.settingsPersistentReminderIntervalMinutesKey) as? Int ?? 1
        let normalizedHour = min(23, max(0, hour))
        let normalizedMinute = min(59, max(0, minute))
        let normalizedInterval = max(1, min(240, persistentIntervalMinutes))
        return NotificationPlanner(
            calendar: .current,
            defaultHour: normalizedHour,
            defaultMinute: normalizedMinute,
            persistentRemindersEnabled: persistentEnabled,
            persistentReminderIntervalMinutes: normalizedInterval
        )
    }

    private func configureLifecycleObservers() {
        let center = NotificationCenter.default

        lifecycleObserverTokens.append(center.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.loadPerspectivesFromDisk()
                self?.debounceMetadataRefresh()
                self?.scheduleCalendarRefresh(force: true)
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
        ) { [weak self] notification in
            guard let metadataQuery = notification.object as? NSMetadataQuery else { return }
            metadataQuery.disableUpdates()
            Task { @MainActor [weak self] in
                self?.debounceMetadataRefresh()
            }
            metadataQuery.enableUpdates()
        })

        metadataObserverTokens.append(center.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.debounceMetadataRefresh()
            }
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
        if isMetadataRefreshSuppressed() {
            return
        }

        metadataRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard !self.isMetadataRefreshSuppressed() else { return }
                self.refresh()
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
                    ref: record.document.frontmatter.ref,
                    title: record.document.frontmatter.title,
                    subtitle: record.document.frontmatter.description,
                    status: record.document.frontmatter.status.rawValue,
                    dueISODate: record.document.frontmatter.due?.isoString,
                    dueTime: record.document.frontmatter.dueTime?.isoString,
                    deferISODate: record.document.frontmatter.defer?.isoString,
                    scheduledISODate: record.document.frontmatter.scheduled?.isoString,
                    priority: record.document.frontmatter.priority.rawValue,
                    flagged: record.document.frontmatter.flagged,
                    area: record.document.frontmatter.area,
                    project: record.document.frontmatter.project,
                    tags: record.document.frontmatter.tags,
                    recurrence: record.document.frontmatter.recurrence,
                    estimatedMinutes: record.document.frontmatter.estimatedMinutes,
                    assignee: record.document.frontmatter.assignee,
                    completedBy: record.document.frontmatter.completedBy,
                    blockedByFlag: record.document.frontmatter.blockedBy == .manual,
                    blockedByRefs: record.document.frontmatter.blockedByRefs,
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
        model.ref = record.document.frontmatter.ref
        model.title = record.document.frontmatter.title
        model.subtitle = record.document.frontmatter.description
        model.status = record.document.frontmatter.status.rawValue
        model.dueISODate = record.document.frontmatter.due?.isoString
        model.dueTime = record.document.frontmatter.dueTime?.isoString
        model.deferISODate = record.document.frontmatter.defer?.isoString
        model.scheduledISODate = record.document.frontmatter.scheduled?.isoString
        model.priority = record.document.frontmatter.priority.rawValue
        model.flagged = record.document.frontmatter.flagged
        model.area = record.document.frontmatter.area
        model.project = record.document.frontmatter.project
        model.tags = record.document.frontmatter.tags
        model.recurrence = record.document.frontmatter.recurrence
        model.estimatedMinutes = record.document.frontmatter.estimatedMinutes
        model.assignee = record.document.frontmatter.assignee
        model.completedBy = record.document.frontmatter.completedBy
        model.blockedByFlag = record.document.frontmatter.blockedBy == .manual
        model.blockedByRefs = record.document.frontmatter.blockedByRefs
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
        let dueTime = model.dueTime.flatMap { try? LocalTime(isoTime: $0) }
        let deferDate = model.deferISODate.flatMap { try? LocalDate(isoDate: $0) }
        let scheduled = model.scheduledISODate.flatMap { try? LocalDate(isoDate: $0) }

        let frontmatter = TaskFrontmatterV1(
            ref: model.ref,
            title: model.title,
            status: status,
            due: due,
            dueTime: dueTime,
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
            assignee: model.assignee,
            completedBy: model.completedBy,
            blockedBy: model.blockedByFlag ? .manual : (model.blockedByRefs.isEmpty ? nil : .refs(model.blockedByRefs)),
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

    private func apply(editState: TaskEditState, to document: inout TaskDocument) {
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
        document.frontmatter.locationReminder = locationReminder(from: editState)
        document.body = String(editState.body.prefix(TaskValidation.maxBodyLength))

        let isNowCompleted = editState.status == .done || editState.status == .cancelled
        let wasCompleted = previousStatus == .done || previousStatus == .cancelled
        if isNowCompleted && !wasCompleted {
            document.frontmatter.completed = Date()
            document.frontmatter.completedBy = "user"
        } else if !isNowCompleted && wasCompleted {
            document.frontmatter.completed = nil
            document.frontmatter.completedBy = nil
        }
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

    private func upsertRecordInMemory(_ record: TaskRecord) {
        canonicalByPath[record.identity.path] = record

        if let existingIndex = allIndexedRecords.firstIndex(where: { $0.identity.path == record.identity.path }) {
            allIndexedRecords[existingIndex] = record
        } else {
            allIndexedRecords.append(record)
        }

        _ = applyCurrentViewFilter()
    }

    private func makeReminderImportCandidate(from reminder: ReminderImportItem) -> ReminderImportCandidate? {
        let titleInput = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !titleInput.isEmpty else { return nil }

        let parsedTitle = quickEntryParser.parse(titleInput)
        let parsedNotes = reminder.notes.flatMap { quickEntryParser.parse($0) }

        let resolvedTitle = (parsedTitle?.title ?? titleInput).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedTitle.isEmpty else { return nil }

        var due = parsedTitle?.due ?? parsedNotes?.due
        var dueTime: LocalTime?
        if let dueDateComponents = reminder.dueDateComponents {
            let dueParts = localDateAndTime(from: dueDateComponents)
            if let mappedDue = dueParts.date {
                due = mappedDue
            }
            dueTime = dueParts.time
        }
        if due == nil {
            dueTime = nil
        }

        let scheduled = reminder.startDateComponents.flatMap { localDateAndTime(from: $0).date }

        let parserTags = (parsedTitle?.tags ?? []) + (parsedNotes?.tags ?? [])
        let tags = mergedReminderTags(
            parserTags: parserTags,
            textSources: [titleInput, reminder.notes ?? ""]
        )

        let createdAt = reminder.createdAt ?? Date()
        let modifiedAt = reminder.modifiedAt ?? createdAt
        let title = String(resolvedTitle.prefix(TaskValidation.maxTitleLength))
        let body = String((reminder.notes ?? "").prefix(TaskValidation.maxBodyLength))

        let frontmatter = TaskFrontmatterV1(
            title: title,
            status: .todo,
            due: due,
            dueTime: dueTime,
            scheduled: scheduled,
            priority: taskPriority(fromReminderPriority: reminder.priority),
            tags: tags,
            created: createdAt,
            modified: modifiedAt,
            source: "import-reminders"
        )

        return ReminderImportCandidate(
            reminderID: reminder.id,
            document: TaskDocument(frontmatter: frontmatter, body: body)
        )
    }

    private func createReminderTasks(
        candidates: [ReminderImportCandidate],
        rootPath: String
    ) async -> ReminderImportCreateResult {
        await Task.detached(priority: .userInitiated) {
            let repository = FileTaskRepository(rootURL: URL(fileURLWithPath: rootPath, isDirectory: true))
            var created: [ReminderImportCreateResult.CreatedRecord] = []
            var failedCount = 0

            for candidate in candidates {
                do {
                    let record = try repository.create(document: candidate.document, preferredFilename: nil)
                    created.append(
                        ReminderImportCreateResult.CreatedRecord(
                            path: record.identity.path,
                            reminderID: candidate.reminderID
                        )
                    )
                } catch {
                    failedCount += 1
                }
            }

            return ReminderImportCreateResult(created: created, failedCount: failedCount)
        }.value
    }

    private func mergedReminderTags(parserTags: [String], textSources: [String]) -> [String] {
        var seen: Set<String> = []
        var merged: [String] = []
        let discoveredTags = textSources.flatMap(reminderTags(in:))

        for candidate in parserTags + discoveredTags {
            guard let normalizedTag = normalizeReminderTag(candidate) else { continue }
            let dedupeKey = normalizedTag.lowercased()
            guard !seen.contains(dedupeKey) else { continue }

            seen.insert(dedupeKey)
            merged.append(normalizedTag)

            if merged.count >= TaskValidation.maxTagsCount {
                break
            }
        }

        return merged
    }

    private func reminderTags(in text: String) -> [String] {
        guard let regex = Self.hashtagRegex else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match -> String? in
            guard match.numberOfRanges > 1,
                  let tagRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[tagRange])
        }
    }

    private func normalizeReminderTag(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count <= TaskValidation.maxTagLength else { return nil }
        let allowedCharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard trimmed.rangeOfCharacter(from: allowedCharacterSet.inverted) == nil else { return nil }
        return trimmed
    }

    private func localDateAndTime(from components: DateComponents) -> (date: LocalDate?, time: LocalTime?) {
        let date: LocalDate?
        if let year = components.year, let month = components.month, let day = components.day {
            date = try? LocalDate(year: year, month: month, day: day)
        } else if let resolvedDate = components.date {
            date = localDateFromDate(resolvedDate)
        } else {
            date = nil
        }

        let hasExplicitTime = components.hour != nil || components.minute != nil
        let time: LocalTime?
        if hasExplicitTime {
            let hour = components.hour ?? 0
            let minute = components.minute ?? 0
            time = try? LocalTime(hour: hour, minute: minute)
        } else {
            time = nil
        }

        return (date, time)
    }

    private func taskPriority(fromReminderPriority priority: Int) -> TaskPriority {
        switch priority {
        case 1...4:
            return .high
        case 5:
            return .medium
        case 6...9:
            return .low
        default:
            return .none
        }
    }

    private func persistTaskAsync(document: TaskDocument, errorContext: String) {
        suppressMetadataRefresh(for: 3)
        let rootPath = rootURL.path

        Task { @MainActor [weak self] in
            let result: Result<TaskRecord, Error> = await Task.detached(priority: .userInitiated) {
                let repository = FileTaskRepository(rootURL: URL(fileURLWithPath: rootPath, isDirectory: true))
                return Result {
                    try repository.create(document: document, preferredFilename: nil)
                }
            }.value

            guard let self else { return }

            switch result {
            case .success(let created):
                if self.rootURL.path == rootPath {
                    self.markSelfWrite(path: created.identity.path)
                    self.upsertRecordInMemory(created)
                } else {
                    self.refresh()
                }
            case .failure(let error):
                self.logger.error(errorContext, metadata: ["error": error.localizedDescription])
            }
        }
    }

    private func isMetadataRefreshSuppressed(now: Date = Date()) -> Bool {
        guard let suppressUntil = suppressMetadataRefreshUntil else { return false }
        return suppressUntil > now
    }

    private func suppressMetadataRefresh(for seconds: TimeInterval) {
        let candidate = Date().addingTimeInterval(seconds)
        if let existing = suppressMetadataRefreshUntil, existing > candidate {
            return
        }
        suppressMetadataRefreshUntil = candidate
        metadataRefreshWorkItem?.cancel()
        metadataRefreshWorkItem = nil
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

    private func dateFromLocalTime(_ localTime: LocalTime?) -> Date? {
        guard let localTime else { return nil }
        var components = DateComponents()
        components.hour = localTime.hour
        components.minute = localTime.minute
        components.second = 0
        components.calendar = .current
        return Calendar.current.date(from: components)
    }

    private func localTimeFromDate(_ date: Date) -> LocalTime {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (try? LocalTime(
            hour: components.hour ?? 0,
            minute: components.minute ?? 0
        )) ?? .midnight
    }

    private func markSelfWrite(path: String) {
        suppressMetadataRefresh(for: 2)

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
