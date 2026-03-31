import EventKit
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
protocol CalendarManaging: AnyObject {
    var isServiceConnected: Bool { get }
    func loadPersistedSourceSelection() -> Set<String>
    func persistSourceSelection(_ selectedIDs: Set<String>)
    func connect() async throws
    func refresh(force: Bool, selectedSourceIDs: Set<String>) -> CalendarRefreshResult
}

extension CalendarIntegrationManager: CalendarManaging {
    var isServiceConnected: Bool {
        isConnected
    }
}

struct CalendarCoordinatorState: Equatable {
    var isConnected = false
    var isSyncing = false
    var statusMessage: String?
    var sources: [CalendarSource] = []
    var selectedSourceIDs: Set<String> = []
    var todayEvents: [CalendarEventItem] = []
    var upcomingSections: [CalendarDaySection] = []
}

@MainActor
final class CalendarCoordinator {
    typealias SnapshotSaver = @MainActor (CalendarCoordinatorState, Date) -> Void
    typealias SnapshotClearer = @MainActor () -> Void

    private let manager: any CalendarManaging
    private let saveSnapshot: SnapshotSaver
    private let clearSnapshot: SnapshotClearer
    private var refreshTask: Task<Void, Never>?

    init(
        manager: any CalendarManaging = CalendarIntegrationManager(),
        saveSnapshot: @escaping SnapshotSaver = CalendarCoordinator.defaultSaveSnapshot,
        clearSnapshot: @escaping SnapshotClearer = CalendarCoordinator.defaultClearSnapshot
    ) {
        self.manager = manager
        self.saveSnapshot = saveSnapshot
        self.clearSnapshot = clearSnapshot
    }

    func initialState() -> CalendarCoordinatorState {
        CalendarCoordinatorState(
            isConnected: manager.isServiceConnected,
            selectedSourceIDs: manager.loadPersistedSourceSelection()
        )
    }

    func isSourceSelected(_ sourceID: String, state: CalendarCoordinatorState) -> Bool {
        state.selectedSourceIDs.contains(sourceID)
    }

    func setSourceSelected(
        sourceID: String,
        isSelected: Bool,
        state: inout CalendarCoordinatorState
    ) {
        if isSelected {
            state.selectedSourceIDs.insert(sourceID)
        } else {
            state.selectedSourceIDs.remove(sourceID)
        }
        manager.persistSourceSelection(state.selectedSourceIDs)
    }

    func selectAllSources(state: inout CalendarCoordinatorState) {
        state.selectedSourceIDs = Set(state.sources.map(\.id))
        manager.persistSourceSelection(state.selectedSourceIDs)
    }

    func connect(state: CalendarCoordinatorState) async -> CalendarCoordinatorState {
        var updated = state
        updated.isSyncing = true
        updated.statusMessage = nil

        do {
            try await manager.connect()
            updated.isConnected = true

            let result = manager.refresh(force: true, selectedSourceIDs: updated.selectedSourceIDs)
            updated = applyRefreshResult(result, to: updated)
        } catch {
            updated.statusMessage = error.localizedDescription
            if case AppleCalendarServiceError.accessDenied = error {
                updated.isConnected = false
                updated.todayEvents = []
                updated.upcomingSections = []
                clearSnapshot()
            }
        }

        updated.isSyncing = false
        return updated
    }

    func refresh(
        state: CalendarCoordinatorState,
        force: Bool = false
    ) async -> CalendarCoordinatorState {
        var updated = state
        updated.isSyncing = true

        let result = manager.refresh(force: force, selectedSourceIDs: state.selectedSourceIDs)
        guard !result.wasThrottled else {
            updated.isSyncing = false
            return updated
        }

        updated = applyRefreshResult(result, to: updated)
        updated.isSyncing = false
        return updated
    }

    func scheduleRefresh(
        force: Bool = false,
        stateProvider: @escaping @MainActor () -> CalendarCoordinatorState,
        apply: @escaping @MainActor (CalendarCoordinatorState) -> Void
    ) {
        if force {
            refreshTask?.cancel()
            refreshTask = nil
        } else if refreshTask != nil {
            return
        }

        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let updated = await self.refresh(state: stateProvider(), force: force)
            apply(updated)
            self.refreshTask = nil
        }
    }

    private func applyRefreshResult(
        _ result: CalendarRefreshResult,
        to state: CalendarCoordinatorState
    ) -> CalendarCoordinatorState {
        var updated = state
        updated.isConnected = result.isConnected
        updated.statusMessage = result.statusMessage
        updated.sources = result.sources
        updated.selectedSourceIDs = result.selectedSourceIDs
        updated.todayEvents = result.todayEvents
        updated.upcomingSections = result.upcomingSections

        if result.shouldClearSnapshot {
            clearSnapshot()
        } else if let capturedAt = result.capturedAt {
            saveSnapshot(updated, capturedAt)
        }

        return updated
    }

    private static func defaultSaveSnapshot(
        state: CalendarCoordinatorState,
        capturedAt: Date
    ) {
        let snapshot = WidgetCalendarSnapshot(
            capturedAt: capturedAt,
            capturedDay: LocalDate.today(in: .current),
            todayEvents: state.todayEvents.map(\.widgetSnapshotValue),
            upcomingSections: state.upcomingSections.map(\.widgetSnapshotValue)
        )
        WidgetCalendarSnapshotStore.save(snapshot)
        reloadTodayTomorrowWidgetTimeline()
    }

    private static func defaultClearSnapshot() {
        WidgetCalendarSnapshotStore.clear()
        reloadTodayTomorrowWidgetTimeline()
    }

    private static func reloadTodayTomorrowWidgetTimeline() {
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "TodoMDTodayTomorrowWidget")
#endif
    }
}
