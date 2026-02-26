import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

#if canImport(UIKit) && canImport(UserNotifications)
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let done = UNNotificationAction(
            identifier: NotificationActionIdentifiers.done,
            title: "Done",
            options: [.authenticationRequired]
        )

        let open = UNNotificationAction(
            identifier: NotificationActionIdentifiers.open,
            title: "Open",
            options: [.foreground]
        )

        let category = UNNotificationCategory(
            identifier: NotificationActionIdentifiers.category,
            actions: [done, open],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([category])
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        let userInfo = response.notification.request.content.userInfo
        guard let path = userInfo["task_path"] as? String, !path.isEmpty else {
            return
        }

        switch response.actionIdentifier {
        case NotificationActionIdentifiers.done:
            completeTask(path: path)
        case NotificationActionIdentifiers.open, UNNotificationDefaultActionIdentifier:
            Task { @MainActor in
                NotificationActionCoordinator.shared.setPendingNavigationPath(path)
            }
        default:
            Task { @MainActor in
                NotificationActionCoordinator.shared.setPendingNavigationPath(path)
            }
        }
    }

    nonisolated private func completeTask(path: String) {
        let repository: FileTaskRepository
        do {
            let root = try TaskFolderLocator().ensureFolderExists()
            repository = FileTaskRepository(rootURL: root)
        } catch {
            return
        }

        let now = Date()
        if let current = try? repository.load(path: path),
           let recurrence = current.document.frontmatter.recurrence?.trimmingCharacters(in: .whitespacesAndNewlines),
           !recurrence.isEmpty,
           current.document.frontmatter.status != .done,
           current.document.frontmatter.status != .cancelled {
            _ = try? repository.completeRepeating(path: path, at: now)
        } else {
            _ = try? repository.complete(path: path, at: now)
        }
    }
}
#else
final class AppDelegate: NSObject {}
#endif
