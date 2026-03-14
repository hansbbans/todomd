import Foundation

struct NotificationTimePreference {
    static let hourKey = "settings_notification_hour"
    static let minuteKey = "settings_notification_minute"

    let hour: Int
    let minute: Int

    init(hour: Int, minute: Int) {
        self.hour = Self.normalizedHour(hour)
        self.minute = Self.normalizedMinute(minute)
    }

    init(userDefaults: UserDefaults = .standard) {
        self.init(
            hour: userDefaults.object(forKey: Self.hourKey) as? Int ?? 9,
            minute: userDefaults.object(forKey: Self.minuteKey) as? Int ?? 0
        )
    }

    func date(on day: Date, calendar: Calendar = .current) -> Date {
        let anchor = calendar.startOfDay(for: day)
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: anchor) ?? anchor
    }

    func matches(_ date: Date, calendar: Calendar = .current) -> Bool {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return components.hour == hour && components.minute == minute
    }

    private static func normalizedHour(_ hour: Int) -> Int {
        min(23, max(0, hour))
    }

    private static func normalizedMinute(_ minute: Int) -> Int {
        min(59, max(0, minute))
    }
}
