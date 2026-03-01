import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(BackgroundTasks)
@preconcurrency import BackgroundTasks
#endif

#if canImport(UIKit) && canImport(UserNotifications)
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
#if canImport(BackgroundTasks)
        NotificationBackgroundRefreshCoordinator.registerBackgroundTask()
        NotificationBackgroundRefreshCoordinator.scheduleNextRefresh()
#endif

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

    func applicationDidEnterBackground(_ application: UIApplication) {
#if canImport(BackgroundTasks)
        NotificationBackgroundRefreshCoordinator.scheduleNextRefresh()
#endif
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

#if canImport(UIKit) && canImport(UserNotifications) && canImport(BackgroundTasks)
enum NotificationBackgroundRefreshCoordinator {
    static let taskIdentifier = "com.hans.todomd.notifications.refresh"
    private static let minimumRefreshInterval: TimeInterval = 30 * 60

    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let appRefreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(appRefreshTask)
        }
    }

    static func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumRefreshInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Keep non-fatal: best effort scheduling only.
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        scheduleNextRefresh()

        let refreshTask = Task {
            let success = await runRefresh()
            if !Task.isCancelled {
                task.setTaskCompleted(success: success)
            }
        }

        task.expirationHandler = {
            refreshTask.cancel()
        }
    }

    private static func runRefresh() async -> Bool {
        do {
            let rootURL = try TaskFolderLocator().ensureFolderExists()
            let repository = FileTaskRepository(rootURL: rootURL)
            let records = try repository.loadAll()
            let planner = plannerFromSettings()
            let hasLocationReminders = records.contains { $0.document.frontmatter.locationReminder != nil }
            let scheduler = await MainActor.run { UserNotificationScheduler() }
            await scheduler.requestAuthorizationIfNeeded(requestLocation: hasLocationReminders)
            await scheduler.synchronize(records: records, planner: planner)
            return true
        } catch {
            return false
        }
    }

    private static func plannerFromSettings() -> NotificationPlanner {
        let defaults = UserDefaults.standard
        let hour = defaults.object(forKey: "settings_notification_hour") as? Int ?? 9
        let minute = defaults.object(forKey: "settings_notification_minute") as? Int ?? 0
        let persistentEnabled = defaults.object(forKey: "settings_persistent_reminders_enabled") as? Bool ?? false
        let persistentIntervalMinutes = defaults.object(forKey: "settings_persistent_reminder_interval_minutes") as? Int ?? 1

        return NotificationPlanner(
            calendar: .current,
            defaultHour: min(23, max(0, hour)),
            defaultMinute: min(59, max(0, minute)),
            persistentRemindersEnabled: persistentEnabled,
            persistentReminderIntervalMinutes: max(1, min(240, persistentIntervalMinutes))
        )
    }
}
#endif
