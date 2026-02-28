import EventKit
import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum AppleCalendarServiceError: LocalizedError {
    case accessDenied
    case missingUsageDescription

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Calendar access is unavailable. Enable it in iOS Settings for todo.md."
        case .missingUsageDescription:
            return "This build is missing Calendar permission text. Regenerate the Xcode project and rebuild."
        }
    }
}

@MainActor
final class AppleCalendarService {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    var isConnected: Bool {
        Self.hasReadAccess(status: EKEventStore.authorizationStatus(for: .event))
    }

    func requestAccessIfNeeded() async throws {
        try ensureUsageDescription()

        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            return
        case .notDetermined:
            let granted = try await eventStore.requestFullAccessToEvents()
            if granted {
                return
            }
            throw AppleCalendarServiceError.accessDenied
        default:
            throw AppleCalendarServiceError.accessDenied
        }
    }

    func fetchUpcomingEvents(
        startDate: Date,
        endDate: Date,
        allowedCalendarIDs: Set<String>? = nil
    ) throws -> (sources: [CalendarSource], events: [CalendarEventItem]) {
        guard startDate < endDate else { return ([], []) }
        try ensureUsageDescription()
        guard isConnected else { throw AppleCalendarServiceError.accessDenied }

        let calendars = eventStore.calendars(for: .event)
        let sources = calendars.map { calendar in
            CalendarSource(
                id: calendar.calendarIdentifier,
                name: calendar.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Calendar",
                colorHex: Self.hexColor(for: calendar),
                isDefaultSelected: true
            )
        }

        let selectedCalendars: [EKCalendar]
        if let allowedCalendarIDs {
            selectedCalendars = calendars.filter { allowedCalendarIDs.contains($0.calendarIdentifier) }
        } else {
            selectedCalendars = calendars
        }

        guard !selectedCalendars.isEmpty else {
            return (sources, [])
        }

        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: selectedCalendars
        )
        let events = eventStore.events(matching: predicate)
            .filter { $0.status != .canceled }
            .compactMap { event in
                guard let calendar = event.calendar else { return nil }
                let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled Event"
                let start = event.startDate ?? event.endDate ?? startDate
                let end = event.endDate ?? start

                return CalendarEventItem(
                    id: event.eventIdentifier ?? "\(calendar.calendarIdentifier)|\(start.timeIntervalSinceReferenceDate)|\(title)",
                    calendarID: calendar.calendarIdentifier,
                    calendarName: calendar.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Calendar",
                    calendarColorHex: Self.hexColor(for: calendar),
                    title: title,
                    startDate: start,
                    endDate: max(end, start),
                    isAllDay: event.isAllDay
                )
            }
            .sorted(by: Self.eventSort)

        return (sources, events)
    }

    private func ensureUsageDescription() throws {
        let usageDescription = (Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard usageDescription?.isEmpty == false else {
            throw AppleCalendarServiceError.missingUsageDescription
        }
    }

    private static func eventSort(lhs: CalendarEventItem, rhs: CalendarEventItem) -> Bool {
        if lhs.startDate != rhs.startDate {
            return lhs.startDate < rhs.startDate
        }
        if lhs.endDate != rhs.endDate {
            return lhs.endDate < rhs.endDate
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func hasReadAccess(status: EKAuthorizationStatus) -> Bool {
        switch status {
        case .fullAccess:
            return true
        default:
            return false
        }
    }

    private static func hexColor(for calendar: EKCalendar) -> String {
#if canImport(UIKit)
        let color = UIColor(cgColor: calendar.cgColor)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "#3B82F6"
        }
        let r = Int((red * 255.0).rounded())
        let g = Int((green * 255.0).rounded())
        let b = Int((blue * 255.0).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
#else
        return "#3B82F6"
#endif
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
