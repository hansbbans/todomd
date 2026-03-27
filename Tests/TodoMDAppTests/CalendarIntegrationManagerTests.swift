import Foundation
import Testing
@testable import TodoMDApp

@MainActor
struct CalendarIntegrationManagerTests {
    @Test("Refresh selects all sources when no selection has been saved")
    func refreshSelectsAllSourcesWhenNoSelectionHasBeenSaved() async throws {
        let suiteName = "CalendarIntegrationManagerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(true, forKey: "settings_google_calendar_enabled")

        let referenceDate = try #require(
            Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 3, day: 26, hour: 9))
        )
        let availableSources = [
            CalendarSource(id: "personal", name: "Personal", colorHex: "#FF0000", isDefaultSelected: true),
            CalendarSource(id: "work", name: "Work", colorHex: "#00FF00", isDefaultSelected: true)
        ]
        let service = FakeCalendarIntegrationService(
            isConnected: true,
            sources: availableSources,
            events: makeEvents(referenceDate: referenceDate)
        )
        let manager = CalendarIntegrationManager(
            service: service,
            userDefaults: defaults,
            now: { referenceDate }
        )

        let result = manager.refresh(force: true, selectedSourceIDs: [])

        #expect(result.selectedSourceIDs == Set(["personal", "work"]))
        #expect(result.sources.map(\.id) == ["personal", "work"])
        #expect(result.todayEvents.count == 1)
        #expect(result.upcomingSections.count == 1)
        #expect(result.shouldClearSnapshot == false)
    }

    @Test("Refresh prunes persisted source selection to available sources")
    func refreshPrunesPersistedSourceSelectionToAvailableSources() async throws {
        let suiteName = "CalendarIntegrationManagerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(true, forKey: "settings_google_calendar_enabled")
        defaults.set(["work", "missing"], forKey: "settings_google_calendar_selected_ids")

        let referenceDate = try #require(
            Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 3, day: 26, hour: 9))
        )
        let service = FakeCalendarIntegrationService(
            isConnected: true,
            sources: [
                CalendarSource(id: "personal", name: "Personal", colorHex: "#FF0000", isDefaultSelected: true),
                CalendarSource(id: "work", name: "Work", colorHex: "#00FF00", isDefaultSelected: true)
            ],
            events: makeEvents(referenceDate: referenceDate)
        )
        let manager = CalendarIntegrationManager(
            service: service,
            userDefaults: defaults,
            now: { referenceDate }
        )

        let result = manager.refresh(force: true, selectedSourceIDs: Set(["work", "missing"]))

        #expect(result.selectedSourceIDs == Set(["work"]))
        #expect(defaults.array(forKey: "settings_google_calendar_selected_ids") as? [String] == ["work"])
        #expect(service.lastAllowedCalendarIDs == Set(["work", "missing"]))
    }

    @Test("Refresh returns cleared state when calendar integration is disabled")
    func refreshReturnsClearedStateWhenCalendarIntegrationIsDisabled() async throws {
        let suiteName = "CalendarIntegrationManagerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(false, forKey: "settings_google_calendar_enabled")

        let referenceDate = try #require(
            Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 3, day: 26, hour: 9))
        )
        let service = FakeCalendarIntegrationService(
            isConnected: true,
            sources: [CalendarSource(id: "work", name: "Work", colorHex: "#00FF00", isDefaultSelected: true)],
            events: makeEvents(referenceDate: referenceDate)
        )
        let manager = CalendarIntegrationManager(
            service: service,
            userDefaults: defaults,
            now: { referenceDate }
        )

        let result = manager.refresh(force: true, selectedSourceIDs: Set(["work"]))

        #expect(result.isConnected == false)
        #expect(result.sources.isEmpty)
        #expect(result.selectedSourceIDs == Set(["work"]))
        #expect(result.todayEvents.isEmpty)
        #expect(result.upcomingSections.isEmpty)
        #expect(result.shouldClearSnapshot)
        #expect(service.fetchCallCount == 0)
    }

    @Test("Refresh preserves a newer selection when a later refresh exits early")
    func refreshPreservesNewerSelectionAcrossEarlyReturn() async throws {
        let suiteName = "CalendarIntegrationManagerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(true, forKey: "settings_google_calendar_enabled")
        defaults.set(["work"], forKey: "settings_google_calendar_selected_ids")

        let referenceDate = try #require(
            Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 3, day: 26, hour: 9))
        )
        let service = FakeCalendarIntegrationService(
            isConnected: true,
            sources: [
                CalendarSource(id: "personal", name: "Personal", colorHex: "#FF0000", isDefaultSelected: true),
                CalendarSource(id: "work", name: "Work", colorHex: "#00FF00", isDefaultSelected: true)
            ],
            events: makeEvents(referenceDate: referenceDate)
        )
        let manager = CalendarIntegrationManager(
            service: service,
            userDefaults: defaults,
            now: { referenceDate }
        )

        let firstResult = manager.refresh(force: true, selectedSourceIDs: Set(["work"]))
        #expect(firstResult.selectedSourceIDs == Set(["work"]))

        defaults.set(false, forKey: "settings_google_calendar_enabled")
        let secondResult = manager.refresh(force: true, selectedSourceIDs: Set(["personal"]))

        #expect(secondResult.isConnected == false)
        #expect(secondResult.selectedSourceIDs == Set(["personal"]))
        #expect(secondResult.sources.map(\.id) == ["personal", "work"])
        #expect(secondResult.todayEvents.isEmpty)
        #expect(secondResult.upcomingSections.isEmpty)
        #expect(secondResult.shouldClearSnapshot)
    }

    private func makeEvents(referenceDate: Date) -> [CalendarEventItem] {
        let calendar = Calendar(identifier: .gregorian)
        let todayStart = calendar.startOfDay(for: referenceDate)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart

        return [
            CalendarEventItem(
                id: "today",
                calendarID: "work",
                calendarName: "Work",
                calendarColorHex: "#00FF00",
                title: "Standup",
                startDate: todayStart.addingTimeInterval(60 * 60),
                endDate: todayStart.addingTimeInterval(2 * 60 * 60),
                isAllDay: false
            ),
            CalendarEventItem(
                id: "tomorrow",
                calendarID: "work",
                calendarName: "Work",
                calendarColorHex: "#00FF00",
                title: "Planning",
                startDate: tomorrowStart.addingTimeInterval(60 * 60),
                endDate: tomorrowStart.addingTimeInterval(2 * 60 * 60),
                isAllDay: false
            )
        ]
    }
}

@MainActor
private final class FakeCalendarIntegrationService: CalendarIntegrationServicing {
    let isConnected: Bool
    let sources: [CalendarSource]
    let events: [CalendarEventItem]
    var lastAllowedCalendarIDs: Set<String>?
    var fetchCallCount = 0

    init(isConnected: Bool, sources: [CalendarSource], events: [CalendarEventItem]) {
        self.isConnected = isConnected
        self.sources = sources
        self.events = events
    }

    func requestAccessIfNeeded() async throws {}

    func fetchUpcomingEvents(
        startDate: Date,
        endDate: Date,
        allowedCalendarIDs: Set<String>?
    ) throws -> (sources: [CalendarSource], events: [CalendarEventItem]) {
        _ = startDate
        _ = endDate
        fetchCallCount += 1
        lastAllowedCalendarIDs = allowedCalendarIDs
        return (sources, events)
    }
}
