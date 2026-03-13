import EventKit
import Foundation

struct ReminderCalendarPermissionCoordinator {
    let remindersStatusBeforeRefresh: EKAuthorizationStatus
    let remindersStatusAfterRefresh: EKAuthorizationStatus
    let calendarStatus: EKAuthorizationStatus
    let isCalendarIntegrationEnabled: Bool

    var shouldPresentCalendarAccessPrimer: Bool {
        guard isCalendarIntegrationEnabled else { return false }
        guard remindersStatusBeforeRefresh == .notDetermined else { return false }
        guard ReminderAccessStatus.hasReadAccess(remindersStatusAfterRefresh) else { return false }
        guard calendarStatus == .notDetermined else { return false }
        return true
    }
}
