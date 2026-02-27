import Foundation

struct CalendarSource: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let colorHex: String
    let isDefaultSelected: Bool
}

struct CalendarEventItem: Identifiable, Equatable {
    let id: String
    let calendarID: String
    let calendarName: String
    let calendarColorHex: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
}

struct CalendarDaySection: Identifiable, Equatable {
    let date: Date
    let events: [CalendarEventItem]

    var id: String {
        String(Calendar.current.startOfDay(for: date).timeIntervalSinceReferenceDate)
    }
}
