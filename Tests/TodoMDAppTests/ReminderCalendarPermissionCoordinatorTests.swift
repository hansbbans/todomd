import EventKit
import Testing
@testable import TodoMDApp

struct ReminderCalendarPermissionCoordinatorTests {
    @Test("Calendar primer follows a newly granted reminders prompt")
    func newlyGrantedRemindersAccessTriggersCalendarPrimer() {
        let coordinator = makeCoordinator(
            remindersStatusBeforeRefresh: .notDetermined,
            remindersStatusAfterRefresh: .fullAccess
        )

        #expect(coordinator.shouldPresentCalendarAccessPrimer)
    }

    @Test("Legacy reminders authorization still counts as granted access")
    func legacyGrantedRemindersAccessTriggersCalendarPrimer() {
        let coordinator = makeCoordinator(
            remindersStatusBeforeRefresh: .notDetermined,
            remindersStatusAfterRefresh: legacyAuthorizedStatus
        )

        #expect(ReminderAccessStatus.hasReadAccess(legacyAuthorizedStatus))
        #expect(coordinator.shouldPresentCalendarAccessPrimer)
    }

    @Test("Calendar primer requires an enabled calendar integration and an undetermined calendar status")
    func calendarPrimerRequiresEligibleCalendarState() {
        #expect(
            makeCoordinator(
                remindersStatusBeforeRefresh: .notDetermined,
                remindersStatusAfterRefresh: .fullAccess,
                calendarStatus: .notDetermined,
                isCalendarIntegrationEnabled: false
            ).shouldPresentCalendarAccessPrimer == false
        )
        #expect(
            makeCoordinator(
                remindersStatusBeforeRefresh: .notDetermined,
                remindersStatusAfterRefresh: .fullAccess,
                calendarStatus: .fullAccess
            ).shouldPresentCalendarAccessPrimer == false
        )
        #expect(
            makeCoordinator(
                remindersStatusBeforeRefresh: .notDetermined,
                remindersStatusAfterRefresh: .fullAccess,
                calendarStatus: .denied
            ).shouldPresentCalendarAccessPrimer == false
        )
    }

    @Test("Calendar primer does not follow unchanged or denied reminders access")
    func calendarPrimerSkipsNonGrantedReminderOutcomes() {
        #expect(
            makeCoordinator(
                remindersStatusBeforeRefresh: .fullAccess,
                remindersStatusAfterRefresh: .fullAccess
            ).shouldPresentCalendarAccessPrimer == false
        )
        #expect(
            makeCoordinator(
                remindersStatusBeforeRefresh: .notDetermined,
                remindersStatusAfterRefresh: .denied
            ).shouldPresentCalendarAccessPrimer == false
        )
        #expect(
            makeCoordinator(
                remindersStatusBeforeRefresh: .notDetermined,
                remindersStatusAfterRefresh: .restricted
            ).shouldPresentCalendarAccessPrimer == false
        )
    }

    private func makeCoordinator(
        remindersStatusBeforeRefresh: EKAuthorizationStatus,
        remindersStatusAfterRefresh: EKAuthorizationStatus,
        calendarStatus: EKAuthorizationStatus = .notDetermined,
        isCalendarIntegrationEnabled: Bool = true
    ) -> ReminderCalendarPermissionCoordinator {
        ReminderCalendarPermissionCoordinator(
            remindersStatusBeforeRefresh: remindersStatusBeforeRefresh,
            remindersStatusAfterRefresh: remindersStatusAfterRefresh,
            calendarStatus: calendarStatus,
            isCalendarIntegrationEnabled: isCalendarIntegrationEnabled
        )
    }

    // Raw value 3 preserves the pre-iOS 17 granted state without pulling in the deprecated symbol.
    private var legacyAuthorizedStatus: EKAuthorizationStatus {
        EKAuthorizationStatus(rawValue: 3) ?? .denied
    }
}
