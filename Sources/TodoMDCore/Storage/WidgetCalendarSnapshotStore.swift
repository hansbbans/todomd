import Foundation

public struct WidgetCalendarEventSnapshot: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let calendarID: String
    public let calendarName: String
    public let calendarColorHex: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool

    public init(
        id: String,
        calendarID: String,
        calendarName: String,
        calendarColorHex: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool
    ) {
        self.id = id
        self.calendarID = calendarID
        self.calendarName = calendarName
        self.calendarColorHex = calendarColorHex
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
    }
}

public struct WidgetCalendarDaySnapshot: Identifiable, Codable, Equatable, Sendable {
    public let day: LocalDate
    public let events: [WidgetCalendarEventSnapshot]

    public init(day: LocalDate, events: [WidgetCalendarEventSnapshot]) {
        self.day = day
        self.events = events
    }

    public var id: String {
        day.isoString
    }
}

public struct WidgetCalendarSnapshot: Codable, Equatable, Sendable {
    public let capturedAt: Date
    public let capturedDay: LocalDate
    public let todayEvents: [WidgetCalendarEventSnapshot]
    public let upcomingSections: [WidgetCalendarDaySnapshot]

    public init(
        capturedAt: Date,
        capturedDay: LocalDate,
        todayEvents: [WidgetCalendarEventSnapshot],
        upcomingSections: [WidgetCalendarDaySnapshot]
    ) {
        self.capturedAt = capturedAt
        self.capturedDay = capturedDay
        self.todayEvents = todayEvents
        self.upcomingSections = upcomingSections
    }

    public func events(for day: LocalDate) -> [WidgetCalendarEventSnapshot] {
        if day == capturedDay {
            return todayEvents
        }

        return upcomingSections.first { $0.day == day }?.events ?? []
    }

    public func events(for day: Date, calendar: Calendar = .current) -> [WidgetCalendarEventSnapshot] {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        guard let localDate = try? LocalDate(
            year: components.year ?? 1970,
            month: components.month ?? 1,
            day: components.day ?? 1
        ) else {
            return []
        }

        return events(for: localDate)
    }
}

public enum WidgetCalendarSnapshotStore {
    public static let storageKey = "widget_calendar_snapshot_v1"

    public static func load(defaults: UserDefaults = TaskFolderPreferences.shared) -> WidgetCalendarSnapshot? {
        guard let data = defaults.data(forKey: storageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetCalendarSnapshot.self, from: data)
    }

    public static func save(_ snapshot: WidgetCalendarSnapshot, defaults: UserDefaults = TaskFolderPreferences.shared) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    public static func clear(defaults: UserDefaults = TaskFolderPreferences.shared) {
        defaults.removeObject(forKey: storageKey)
    }
}
