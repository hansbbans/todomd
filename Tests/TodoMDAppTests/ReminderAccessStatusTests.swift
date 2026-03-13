import EventKit
import Testing
@testable import TodoMDApp

struct ReminderAccessStatusTests {
    @Test("Undetermined reminders access needs an explanation until prompting is allowed")
    func notDeterminedAccessNeedsExplanationBeforePrompt() {
        #expect(ReminderAccessStatus.needsExplanationBeforeRequest(.notDetermined))
        #expect(
            ReminderAccessStatus.refreshAction(
                for: .notDetermined,
                allowsPermissionPrompt: false
            ) == .needsExplanationBeforeRequest
        )
        #expect(
            ReminderAccessStatus.refreshAction(
                for: .notDetermined,
                allowsPermissionPrompt: true
            ) == .canRefresh
        )
    }

    @Test("Granted reminders access can refresh immediately")
    func grantedAccessCanRefreshImmediately() {
        #expect(ReminderAccessStatus.refreshAction(for: .fullAccess, allowsPermissionPrompt: false) == .canRefresh)
        #expect(
            ReminderAccessStatus.refreshAction(
                for: legacyAuthorizedStatus,
                allowsPermissionPrompt: false
            ) == .canRefresh
        )
    }

    @Test("Denied and restricted reminders access require Settings")
    func deniedAndRestrictedAccessRequireSettingsRedirect() {
        #expect(ReminderAccessStatus.requiresSettingsRedirect(.denied))
        #expect(ReminderAccessStatus.requiresSettingsRedirect(.restricted))
        #expect(
            ReminderAccessStatus.refreshAction(
                for: .denied,
                allowsPermissionPrompt: true
            ) == .requiresSettingsRedirect
        )
        #expect(
            ReminderAccessStatus.refreshAction(
                for: .restricted,
                allowsPermissionPrompt: false
            ) == .requiresSettingsRedirect
        )
    }

    @Test("Missing stored integration flags stay off until access is granted")
    func missingStoredIntegrationFlagsDefaultOff() {
        #expect(IntegrationEnablementDefaults.resolvedStoredValue(nil, hasGrantedAccess: false) == false)
        #expect(IntegrationEnablementDefaults.resolvedStoredValue(nil, hasGrantedAccess: true))
    }

    @Test("Stored integration flags preserve the user's explicit choice")
    func storedIntegrationFlagsOverrideGrantedAccessFallback() {
        #expect(IntegrationEnablementDefaults.resolvedStoredValue(false, hasGrantedAccess: true) == false)
        #expect(IntegrationEnablementDefaults.resolvedStoredValue(true, hasGrantedAccess: false))
    }

    // Raw value 3 preserves the pre-iOS 17 granted state without pulling in the deprecated symbol.
    private var legacyAuthorizedStatus: EKAuthorizationStatus {
        EKAuthorizationStatus(rawValue: 3) ?? .denied
    }
}
