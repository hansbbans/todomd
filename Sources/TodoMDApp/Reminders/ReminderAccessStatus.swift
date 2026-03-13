import EventKit
import Foundation

enum ReminderAccessRequestAction: Equatable {
    case canRefresh
    case needsExplanationBeforeRequest
    case requiresSettingsRedirect
}

enum ReminderAccessStatus {
    static func hasReadAccess(_ status: EKAuthorizationStatus) -> Bool {
        switch status {
        case .fullAccess, .authorized:
            return true
        default:
            return false
        }
    }

    static func needsExplanationBeforeRequest(_ status: EKAuthorizationStatus) -> Bool {
        status == .notDetermined
    }

    static func requiresSettingsRedirect(_ status: EKAuthorizationStatus) -> Bool {
        switch status {
        case .denied, .restricted:
            return true
        default:
            return false
        }
    }

    static func refreshAction(
        for status: EKAuthorizationStatus,
        allowsPermissionPrompt: Bool
    ) -> ReminderAccessRequestAction {
        if hasReadAccess(status) {
            return .canRefresh
        }
        if requiresSettingsRedirect(status) {
            return .requiresSettingsRedirect
        }
        if needsExplanationBeforeRequest(status), !allowsPermissionPrompt {
            return .needsExplanationBeforeRequest
        }
        return .canRefresh
    }
}
