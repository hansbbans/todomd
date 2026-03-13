import EventKit
import Foundation

@MainActor
protocol CalendarAccessAuthorizing: AnyObject {
    var authorizationStatus: EKAuthorizationStatus { get }
    func requestFullAccess() async throws -> Bool
}

@MainActor
final class EventKitCalendarAccessAuthorizer: CalendarAccessAuthorizing {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore) {
        self.eventStore = eventStore
    }

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    func requestFullAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToEvents()
    }
}
