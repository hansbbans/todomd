import Foundation
import EventKit

/// Manages the connection to Apple Calendar and coordinates event fetching.
///
/// Extracted from AppContainer to isolate calendar integration responsibilities.
/// AppContainer continues to own the `AppleCalendarService` instance and the
/// relevant `@Published` properties; this class provides a composable layer
/// around the raw service with higher-level connection / fetch helpers and
/// source-selection logic.
@MainActor
final class CalendarIntegrationManager {
    private let service: AppleCalendarService

    // UserDefaults keys mirroring AppContainer's constants.
    private static let settingsCalendarEnabledKey = "settings_google_calendar_enabled"
    private static let settingsCalendarSelectedIDsKey = "settings_google_calendar_selected_ids"

    // MARK: - Initialisation

    init(service: AppleCalendarService = AppleCalendarService()) {
        self.service = service
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

    // MARK: - Fetching events

    /// Result type returned by `fetchUpcomingEvents`.
    struct FetchResult {
        let sources: [CalendarSource]
        let todayEvents: [CalendarEventItem]
        let upcomingSections: [CalendarDaySection]
    }

    /// Fetches upcoming calendar events within the next 30 days, starting today.
    ///
    /// - Parameters:
    ///   - allowedCalendarIDs: When non-nil, only events from these calendar IDs are included.
    ///     Pass `nil` to include events from all available calendars.
    /// - Returns: A `FetchResult` with the available calendar sources, today's events, and
    ///   upcoming event sections grouped by day.
    /// - Throws: `AppleCalendarServiceError` when access is denied or the service is unavailable.
    func fetchUpcomingEvents(allowedCalendarIDs: Set<String>?) throws -> FetchResult {
        guard isConnected else {
            throw AppleCalendarServiceError.accessDenied
        }

        let now = Date()
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: now)
        guard let endDate = calendar.date(byAdding: .day, value: 30, to: startDate) else {
            return FetchResult(sources: [], todayEvents: [], upcomingSections: [])
        }

        let (sources, events) = try service.fetchUpcomingEvents(
            startDate: startDate,
            endDate: endDate,
            allowedCalendarIDs: allowedCalendarIDs
        )

        let todayEvents = eventsForToday(events, today: startDate)
        let upcomingSections = groupedUpcomingSections(events, today: startDate)

        return FetchResult(sources: sources, todayEvents: todayEvents, upcomingSections: upcomingSections)
    }

    // MARK: - Source selection helpers

    /// Loads persisted calendar source selection from UserDefaults.
    ///
    /// - Returns: The stored set of selected calendar source IDs, or an empty set if
    ///   no selection has been saved yet.
    func loadPersistedSourceSelection() -> Set<String> {
        guard let ids = UserDefaults.standard.array(forKey: Self.settingsCalendarSelectedIDsKey) as? [String] else {
            return []
        }
        return Set(ids)
    }

    /// Persists the given set of calendar source IDs to UserDefaults.
    ///
    /// - Parameter selectedIDs: The set to persist.
    func persistSourceSelection(_ selectedIDs: Set<String>) {
        UserDefaults.standard.set(Array(selectedIDs).sorted(), forKey: Self.settingsCalendarSelectedIDsKey)
    }

    /// Returns `true` when a previous calendar source selection has been stored in UserDefaults.
    func hasPersistedSourceSelection() -> Bool {
        UserDefaults.standard.array(forKey: Self.settingsCalendarSelectedIDsKey) != nil
    }

    /// Prunes the `selectedIDs` set down to only IDs present in `availableIDs`,
    /// returning the pruned set (which equals `selectedIDs` when no pruning was needed).
    func pruneSelection(_ selectedIDs: Set<String>, against availableIDs: Set<String>) -> Set<String> {
        selectedIDs.intersection(availableIDs)
    }

    /// Returns whether the calendar integration is enabled by the user's settings.
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.settingsCalendarEnabledKey) as? Bool ?? true
    }

    // MARK: - Private event grouping

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
