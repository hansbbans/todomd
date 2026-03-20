import Foundation
import Testing
@testable import TodoMDCore

struct WidgetCalendarSnapshotStoreTests {
    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    @Test("Shared calendar snapshots round-trip through defaults")
    func snapshotsRoundTrip() throws {
        let suiteName = "WidgetCalendarSnapshotStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let snapshot = WidgetCalendarSnapshot(
            capturedAt: makeDate(day: 20, hour: 8),
            capturedDay: try LocalDate(year: 2026, month: 3, day: 20),
            todayEvents: [
                makeEvent(id: "today", day: 20, hour: 9)
            ],
            upcomingSections: [
                WidgetCalendarDaySnapshot(
                    day: try LocalDate(year: 2026, month: 3, day: 21),
                    events: [makeEvent(id: "tomorrow", day: 21, hour: 14)]
                )
            ]
        )

        WidgetCalendarSnapshotStore.save(snapshot, defaults: defaults)
        let loaded = try #require(WidgetCalendarSnapshotStore.load(defaults: defaults))

        #expect(loaded == snapshot)
    }

    @Test("Shared calendar snapshots can be cleared")
    func snapshotsCanBeCleared() {
        let suiteName = "WidgetCalendarSnapshotStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        WidgetCalendarSnapshotStore.save(
            WidgetCalendarSnapshot(
                capturedAt: Date(),
                capturedDay: .epoch,
                todayEvents: [],
                upcomingSections: []
            ),
            defaults: defaults
        )
        WidgetCalendarSnapshotStore.clear(defaults: defaults)

        #expect(WidgetCalendarSnapshotStore.load(defaults: defaults) == nil)
    }

    @Test("Day lookup uses today's events for the captured day and sections for later days")
    func dayLookupPrefersMatchingSection() throws {
        let capturedAt = makeDate(day: 20, hour: 8)
        let todayEvent = makeEvent(id: "today", day: 20, hour: 9)
        let tomorrowEvent = makeEvent(id: "tomorrow", day: 21, hour: 14)
        let snapshot = WidgetCalendarSnapshot(
            capturedAt: capturedAt,
            capturedDay: try LocalDate(year: 2026, month: 3, day: 20),
            todayEvents: [todayEvent],
            upcomingSections: [
                WidgetCalendarDaySnapshot(
                    day: try LocalDate(year: 2026, month: 3, day: 21),
                    events: [tomorrowEvent]
                )
            ]
        )

        #expect(snapshot.events(for: makeDate(day: 20, hour: 0), calendar: testCalendar) == [todayEvent])
        #expect(snapshot.events(for: makeDate(day: 21, hour: 0), calendar: testCalendar) == [tomorrowEvent])
        #expect(snapshot.events(for: makeDate(day: 22, hour: 0), calendar: testCalendar).isEmpty)
    }

    @Test("Day lookup stays stable when the reader uses a different time zone")
    func dayLookupIsStableAcrossTimeZones() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))

        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))

        let snapshot = WidgetCalendarSnapshot(
            capturedAt: try #require(newYork.date(from: DateComponents(year: 2026, month: 3, day: 20, hour: 8))),
            capturedDay: try LocalDate(year: 2026, month: 3, day: 20),
            todayEvents: [makeEvent(id: "today", day: 20, hour: 9)],
            upcomingSections: [
                WidgetCalendarDaySnapshot(
                    day: try LocalDate(year: 2026, month: 3, day: 21),
                    events: [makeEvent(id: "tomorrow", day: 21, hour: 14)]
                )
            ]
        )

        let losAngelesMarch20 = try #require(losAngeles.date(from: DateComponents(year: 2026, month: 3, day: 20, hour: 9)))
        let losAngelesMarch21 = try #require(losAngeles.date(from: DateComponents(year: 2026, month: 3, day: 21, hour: 9)))

        #expect(snapshot.events(for: losAngelesMarch20, calendar: losAngeles).count == 1)
        #expect(snapshot.events(for: losAngelesMarch21, calendar: losAngeles).count == 1)
    }

    private func makeEvent(id: String, day: Int, hour: Int) -> WidgetCalendarEventSnapshot {
        WidgetCalendarEventSnapshot(
            id: id,
            calendarID: "calendar-\(id)",
            calendarName: "Calendar",
            calendarColorHex: "#3366FF",
            title: "Event \(id)",
            startDate: makeDate(day: day, hour: hour),
            endDate: makeDate(day: day, hour: hour + 1),
            isAllDay: false
        )
    }

    private func makeDate(day: Int, hour: Int) -> Date {
        testCalendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour)) ?? Date()
    }
}
