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

extension CalendarEventItem {
    var widgetSnapshotValue: WidgetCalendarEventSnapshot {
        WidgetCalendarEventSnapshot(
            id: id,
            calendarID: calendarID,
            calendarName: calendarName,
            calendarColorHex: calendarColorHex,
            title: title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay
        )
    }
}

extension CalendarDaySection {
    var widgetSnapshotValue: WidgetCalendarDaySnapshot {
        WidgetCalendarDaySnapshot(
            day: localDate,
            events: events.map(\.widgetSnapshotValue)
        )
    }

    private var localDate: LocalDate {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (try? LocalDate(
            year: components.year ?? 1970,
            month: components.month ?? 1,
            day: components.day ?? 1
        )) ?? .epoch
    }
}
