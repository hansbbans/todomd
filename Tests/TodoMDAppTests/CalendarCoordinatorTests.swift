import Foundation
import Testing
@testable import TodoMDApp

@MainActor
struct CalendarCoordinatorTests {
    @Test("Initial state reflects connection and stored source selection")
    func initialStateReflectsStoredSelection() {
        let defaults = makeUserDefaults()
        defaults.set(true, forKey: "settings_google_calendar_enabled")

        let service = FakeCalendarIntegrationService(isConnected: true)
        let manager = CalendarIntegrationManager(service: service, userDefaults: defaults)
        manager.persistSourceSelection(["personal"])

        let coordinator = CalendarCoordinator(manager: manager)
        let state = coordinator.initialState()

        #expect(state.isConnected)
        #expect(state.selectedSourceIDs == ["personal"])
    }

    @Test("Refresh populates calendar state from fetched events")
    func refreshPopulatesState() async {
        let defaults = makeUserDefaults()
        defaults.set(true, forKey: "settings_google_calendar_enabled")

        let calendar = Calendar.current
        let now = Date(timeIntervalSince1970: 1_710_000_000)
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        let sources = [
            CalendarSource(id: "work", name: "Work", colorHex: "#3B82F6", isDefaultSelected: true)
        ]
        let events = [
            CalendarEventItem(
                id: "today-event",
                calendarID: "work",
                calendarName: "Work",
                calendarColorHex: "#3B82F6",
                title: "Standup",
                startDate: calendar.date(byAdding: .hour, value: 9, to: today)!,
                endDate: calendar.date(byAdding: .hour, value: 10, to: today)!,
                isAllDay: false
            ),
            CalendarEventItem(
                id: "tomorrow-event",
                calendarID: "work",
                calendarName: "Work",
                calendarColorHex: "#3B82F6",
                title: "Planning",
                startDate: calendar.date(byAdding: .hour, value: 11, to: tomorrow)!,
                endDate: calendar.date(byAdding: .hour, value: 12, to: tomorrow)!,
                isAllDay: false
            )
        ]

        let service = FakeCalendarIntegrationService(
            isConnected: true,
            fetchedSources: sources,
            fetchedEvents: events
        )
        let manager = CalendarIntegrationManager(
            service: service,
            userDefaults: defaults,
            now: { now }
        )
        let coordinator = CalendarCoordinator(manager: manager)

        let updated = await coordinator.refresh(state: coordinator.initialState(), force: true)

        #expect(updated.isConnected)
        #expect(updated.isSyncing == false)
        #expect(updated.sources == sources)
        #expect(updated.selectedSourceIDs == ["work"])
        #expect(updated.todayEvents.map(\.id) == ["today-event"])
        #expect(updated.upcomingSections.count == 1)
        #expect(updated.upcomingSections.first?.events.map(\.id) == ["tomorrow-event"])
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "CalendarCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

@MainActor
private final class FakeCalendarIntegrationService: CalendarIntegrationServicing {
    var isConnected: Bool
    var fetchedSources: [CalendarSource]
    var fetchedEvents: [CalendarEventItem]
    var requestAccessError: Error?
    var fetchError: Error?

    init(
        isConnected: Bool,
        fetchedSources: [CalendarSource] = [],
        fetchedEvents: [CalendarEventItem] = [],
        requestAccessError: Error? = nil,
        fetchError: Error? = nil
    ) {
        self.isConnected = isConnected
        self.fetchedSources = fetchedSources
        self.fetchedEvents = fetchedEvents
        self.requestAccessError = requestAccessError
        self.fetchError = fetchError
    }

    func requestAccessIfNeeded() async throws {
        if let requestAccessError {
            throw requestAccessError
        }
        isConnected = true
    }

    func fetchUpcomingEvents(
        startDate: Date,
        endDate: Date,
        allowedCalendarIDs: Set<String>?
    ) throws -> (sources: [CalendarSource], events: [CalendarEventItem]) {
        if let fetchError {
            throw fetchError
        }

        let filteredEvents: [CalendarEventItem]
        if let allowedCalendarIDs {
            filteredEvents = fetchedEvents.filter { allowedCalendarIDs.contains($0.calendarID) }
        } else {
            filteredEvents = fetchedEvents
        }

        return (fetchedSources, filteredEvents)
    }
}
