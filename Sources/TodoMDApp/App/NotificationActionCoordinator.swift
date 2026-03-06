import Foundation

enum NotificationActionIdentifiers {
    static let category = "TODO_MD_TASK"
    static let done = "TODO_MD_DONE"
    static let dismiss = "TODO_MD_DISMISS"
    static let snoozeOneDay = "TODO_MD_SNOOZE_ONE_DAY"
    static let removeDueDate = "TODO_MD_REMOVE_DUE_DATE"
    static let open = "TODO_MD_OPEN"
}

@MainActor
final class NotificationActionCoordinator {
    static let shared = NotificationActionCoordinator()

    private let defaults = UserDefaults.standard
    private let pendingNavigationPathKey = "pending_notification_task_path"

    private init() {}

    func setPendingNavigationPath(_ path: String) {
        defaults.set(path, forKey: pendingNavigationPathKey)
    }

    func consumePendingNavigationPath() -> String? {
        guard let path = defaults.string(forKey: pendingNavigationPathKey), !path.isEmpty else {
            return nil
        }
        defaults.removeObject(forKey: pendingNavigationPathKey)
        return path
    }
}
