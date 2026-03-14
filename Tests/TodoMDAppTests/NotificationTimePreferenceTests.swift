import Foundation
import Testing
@testable import TodoMDApp

struct NotificationTimePreferenceTests {
    @Test("Stored settings define the default notification time")
    func storedSettingsDefineTheDefaultNotificationTime() throws {
        let suiteName = "NotificationTimePreferenceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(22, forKey: NotificationTimePreference.hourKey)
        defaults.set(15, forKey: NotificationTimePreference.minuteKey)

        let preference = NotificationTimePreference(userDefaults: defaults)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 13)))

        let dueDate = preference.date(on: day, calendar: calendar)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)

        #expect(preference.hour == 22)
        #expect(preference.minute == 15)
        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 13)
        #expect(components.hour == 22)
        #expect(components.minute == 15)
    }

    @Test("Stored settings are normalized before use")
    func storedSettingsAreNormalizedBeforeUse() throws {
        let suiteName = "NotificationTimePreferenceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(99, forKey: NotificationTimePreference.hourKey)
        defaults.set(-20, forKey: NotificationTimePreference.minuteKey)

        let preference = NotificationTimePreference(userDefaults: defaults)

        #expect(preference.hour == 23)
        #expect(preference.minute == 0)
    }

    @Test("Time matching only compares hour and minute")
    func timeMatchingOnlyComparesHourAndMinute() throws {
        let preference = NotificationTimePreference(hour: 19, minute: 45)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let matchingDate = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 13,
            hour: 19,
            minute: 45,
            second: 30
        )))
        let nonMatchingDate = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 13,
            hour: 20,
            minute: 0
        )))

        #expect(preference.matches(matchingDate, calendar: calendar))
        #expect(preference.matches(nonMatchingDate, calendar: calendar) == false)
    }
}
