import Foundation
import EventKit

@MainActor
protocol CalendarIntegrationServicing: AnyObject {
    var isConnected: Bool { get }
    func requestAccessIfNeeded() async throws
    func fetchUpcomingEvents(
        startDate: Date,
        endDate: Date,
        allowedCalendarIDs: Set<String>?
    ) throws -> (sources: [CalendarSource], events: [CalendarEventItem])
}

extension AppleCalendarService: CalendarIntegrationServicing {}

struct CalendarRefreshResult: Equatable {
    let isConnected: Bool
    let statusMessage: String?
    let sources: [CalendarSource]
    let selectedSourceIDs: Set<String>
    let todayEvents: [CalendarEventItem]
    let upcomingSections: [CalendarDaySection]
    let capturedAt: Date?
    let shouldClearSnapshot: Bool
    let wasThrottled: Bool

    func updating(
        isConnected: Bool? = nil,
        statusMessage: String? = nil,
        sources: [CalendarSource]? = nil,
        selectedSourceIDs: Set<String>? = nil,
        todayEvents: [CalendarEventItem]? = nil,
        upcomingSections: [CalendarDaySection]? = nil,
        capturedAt: Date?? = nil,
        shouldClearSnapshot: Bool? = nil,
        wasThrottled: Bool? = nil
    ) -> Self {
        Self(
            isConnected: isConnected ?? self.isConnected,
            statusMessage: statusMessage ?? self.statusMessage,
            sources: sources ?? self.sources,
            selectedSourceIDs: selectedSourceIDs ?? self.selectedSourceIDs,
            todayEvents: todayEvents ?? self.todayEvents,
            upcomingSections: upcomingSections ?? self.upcomingSections,
            capturedAt: capturedAt ?? self.capturedAt,
            shouldClearSnapshot: shouldClearSnapshot ?? self.shouldClearSnapshot,
            wasThrottled: wasThrottled ?? self.wasThrottled
        )
    }
}

/// Manages the connection to Apple Calendar and coordinates event fetching.
///
/// Extracted from AppContainer to isolate calendar integration responsibilities.
/// AppContainer continues to own the `AppleCalendarService` instance and the
/// relevant `@Published` properties; this class provides a composable layer
/// around the raw service with higher-level connection / fetch helpers and
/// source-selection logic.
@MainActor
final class CalendarIntegrationManager {
    private let service: any CalendarIntegrationServicing
    private let userDefaults: UserDefaults
    private let now: () -> Date
    private var lastRefreshAt: Date?
    private var lastRefreshResult: CalendarRefreshResult?

    // UserDefaults keys mirroring AppContainer's constants.
    private static let settingsCalendarEnabledKey = "settings_google_calendar_enabled"
    private static let settingsCalendarSelectedIDsKey = "settings_google_calendar_selected_ids"

    // MARK: - Initialisation

    init(
        service: any CalendarIntegrationServicing = AppleCalendarService(),
        userDefaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.userDefaults = userDefaults
        self.now = now
    }

    // MARK: - Connection state

    /// Whether the user has granted calendar access and the service is ready to fetch events.
    var isConnected: Bool {
        service.isConnected
    }

    // MARK: - Connect / disconnect

    /// Requests calendar access from the user if it has not been granted yet.
    ///
    /// Throws `AppleCalendarServiceError` on access denial or missing usage description.
    func connect() async throws {
        try await service.requestAccessIfNeeded()
    }

    func refresh(force: Bool, selectedSourceIDs: Set<String>) -> CalendarRefreshResult {
        let baseState = currentState(selectedSourceIDs: selectedSourceIDs)

        guard isEnabled else {
            let result = baseState.updating(
                isConnected: false,
                todayEvents: [],
                upcomingSections: [],
                capturedAt: .some(nil),
                shouldClearSnapshot: true,
                wasThrottled: false
            )
            lastRefreshResult = result
            lastRefreshAt = nil
            return result
        }

        guard isConnected else {
            let result = baseState.updating(
                isConnected: false,
                todayEvents: [],
                upcomingSections: [],
                capturedAt: .some(nil),
                shouldClearSnapshot: true,
                wasThrottled: false
            )
            lastRefreshResult = result
            lastRefreshAt = nil
            return result
        }

        let currentDate = now()
        if !force,
           let lastRefreshAt,
           currentDate.timeIntervalSince(lastRefreshAt) < 60,
           lastRefreshResult != nil {
            return baseState.updating(wasThrottled: true)
        }

        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: currentDate)
        guard let endDate = calendar.date(byAdding: .day, value: TaskQueryEngine.upcomingHorizonDays + 1, to: startDate) else {
            return baseState
        }

        let useSavedSelection = hasPersistedSourceSelection()
        let allowedCalendarIDs: Set<String>? = useSavedSelection ? selectedSourceIDs : nil

        do {
            let fetched = try service.fetchUpcomingEvents(
                startDate: startDate,
                endDate: endDate,
                allowedCalendarIDs: allowedCalendarIDs
            )
            let sources = fetched.sources.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            let availableSourceIDs = Set(sources.map(\.id))

            let resolvedSelection: Set<String>
            if !useSavedSelection {
                resolvedSelection = availableSourceIDs
                persistSourceSelection(resolvedSelection)
            } else {
                let prunedSelection = pruneSelection(selectedSourceIDs, against: availableSourceIDs)
                resolvedSelection = prunedSelection
                if prunedSelection != selectedSourceIDs {
                    persistSourceSelection(prunedSelection)
                }
            }

            let result = CalendarRefreshResult(
                isConnected: true,
                statusMessage: nil,
                sources: sources,
                selectedSourceIDs: resolvedSelection,
                todayEvents: eventsForToday(fetched.events, today: startDate),
                upcomingSections: groupedUpcomingSections(fetched.events, today: startDate),
                capturedAt: currentDate,
                shouldClearSnapshot: false,
                wasThrottled: false
            )
            lastRefreshAt = currentDate
            lastRefreshResult = result
            return result
        } catch {
            let message = error.localizedDescription
            let result: CalendarRefreshResult
            if case AppleCalendarServiceError.accessDenied = error {
                result = baseState.updating(
                    isConnected: false,
                    statusMessage: message,
                    todayEvents: [],
                    upcomingSections: [],
                    capturedAt: .some(nil),
                    shouldClearSnapshot: true,
                    wasThrottled: false
                )
                lastRefreshAt = nil
            } else {
                result = baseState.updating(
                    statusMessage: message,
                    shouldClearSnapshot: false,
                    wasThrottled: false
                )
            }
            lastRefreshResult = result
            return result
        }
    }

    // MARK: - Source selection helpers

    /// Loads persisted calendar source selection from UserDefaults.
    ///
    /// - Returns: The stored set of selected calendar source IDs, or an empty set if
    ///   no selection has been saved yet.
    func loadPersistedSourceSelection() -> Set<String> {
        guard let ids = userDefaults.array(forKey: Self.settingsCalendarSelectedIDsKey) as? [String] else {
            return []
        }
        return Set(ids)
    }

    /// Persists the given set of calendar source IDs to UserDefaults.
    ///
    /// - Parameter selectedIDs: The set to persist.
    func persistSourceSelection(_ selectedIDs: Set<String>) {
        userDefaults.set(Array(selectedIDs).sorted(), forKey: Self.settingsCalendarSelectedIDsKey)
    }

    /// Returns `true` when a previous calendar source selection has been stored in UserDefaults.
    func hasPersistedSourceSelection() -> Bool {
        userDefaults.array(forKey: Self.settingsCalendarSelectedIDsKey) != nil
    }

    /// Prunes the `selectedIDs` set down to only IDs present in `availableIDs`,
    /// returning the pruned set (which equals `selectedIDs` when no pruning was needed).
    func pruneSelection(_ selectedIDs: Set<String>, against availableIDs: Set<String>) -> Set<String> {
        selectedIDs.intersection(availableIDs)
    }

    /// Returns whether the calendar integration is enabled by the user's settings.
    var isEnabled: Bool {
        userDefaults.object(forKey: Self.settingsCalendarEnabledKey) as? Bool ?? false
    }

    // MARK: - Private event grouping

    private func currentState(selectedSourceIDs: Set<String>) -> CalendarRefreshResult {
        if let lastRefreshResult {
            return lastRefreshResult.updating(
                isConnected: isConnected,
                selectedSourceIDs: selectedSourceIDs,
                wasThrottled: false
            )
        }

        return CalendarRefreshResult(
            isConnected: isConnected,
            statusMessage: nil,
            sources: [],
            selectedSourceIDs: selectedSourceIDs,
            todayEvents: [],
            upcomingSections: [],
            capturedAt: nil,
            shouldClearSnapshot: false,
            wasThrottled: false
        )
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
}
