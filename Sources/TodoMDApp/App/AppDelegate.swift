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
    private var shouldManageBackgroundRefreshTasks: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
#if canImport(BackgroundTasks)
        if shouldManageBackgroundRefreshTasks {
            NotificationBackgroundRefreshCoordinator.registerBackgroundTask()
            NotificationBackgroundRefreshCoordinator.scheduleNextRefresh()
        }
#endif

        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let done = UNNotificationAction(
            identifier: NotificationActionIdentifiers.done,
            title: "Mark as done",
            options: [.authenticationRequired]
        )

        let dismiss = UNNotificationAction(
            identifier: NotificationActionIdentifiers.dismiss,
            title: "Dismiss",
            options: []
        )

        let snoozeOneDay = UNNotificationAction(
            identifier: NotificationActionIdentifiers.snoozeOneDay,
            title: "Snooze +1 day",
            options: [.authenticationRequired]
        )

        let removeDueDate = UNNotificationAction(
            identifier: NotificationActionIdentifiers.removeDueDate,
            title: "Remove due date",
            options: [.authenticationRequired]
        )

        let category = UNNotificationCategory(
            identifier: NotificationActionIdentifiers.category,
            actions: [done, dismiss, snoozeOneDay, removeDueDate],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([category])
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
#if canImport(BackgroundTasks)
        if shouldManageBackgroundRefreshTasks {
            NotificationBackgroundRefreshCoordinator.scheduleNextRefresh()
        }
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
        case NotificationActionIdentifiers.dismiss, UNNotificationDismissActionIdentifier:
            return
        case NotificationActionIdentifiers.snoozeOneDay:
            snoozeTaskOneDay(path: path)
        case NotificationActionIdentifiers.removeDueDate:
            clearDueDate(path: path)
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

    nonisolated private func makeRepository() -> FileTaskRepository? {
        do {
            let root = try TaskFolderLocator().ensureFolderExists()
            return FileTaskRepository(rootURL: root)
        } catch {
            return nil
        }
    }

    nonisolated private func completeTask(path: String) {
        guard let repository = makeRepository() else {
            return
        }

        let now = Date()
        guard let current = try? repository.load(path: path),
              isActiveStatus(current.document.frontmatter.status) else {
            return
        }

        do {
            if let recurrence = current.document.frontmatter.recurrence?.trimmingCharacters(in: .whitespacesAndNewlines),
               !recurrence.isEmpty {
                _ = try repository.completeRepeating(path: path, at: now)
            } else {
                _ = try repository.complete(path: path, at: now)
            }
            Task { @MainActor in
                UserNotificationScheduler().cancelNotifications(forTaskPath: path)
            }
            refreshNotificationsBestEffort()
        } catch {
            return
        }
    }

    nonisolated private func snoozeTaskOneDay(path: String) {
        guard let repository = makeRepository(),
              let current = try? repository.load(path: path),
              isActiveStatus(current.document.frontmatter.status),
              let due = current.document.frontmatter.due,
              let snoozedDue = localDateByAddingDays(due, days: 1),
              snoozedDue != due else {
            return
        }

        do {
            _ = try repository.update(path: path) { document in
                document.frontmatter.due = snoozedDue
                if document.frontmatter.dueTime == nil {
                    document.frontmatter.persistentReminder = nil
                }
            }
            refreshNotificationsBestEffort()
        } catch {
            return
        }
    }

    nonisolated private func clearDueDate(path: String) {
        guard let repository = makeRepository(),
              let current = try? repository.load(path: path),
              isActiveStatus(current.document.frontmatter.status) else {
            return
        }

        let hasDueData = current.document.frontmatter.due != nil
            || current.document.frontmatter.dueTime != nil
            || current.document.frontmatter.persistentReminder == true
        guard hasDueData else {
            return
        }

        do {
            _ = try repository.update(path: path) { document in
                document.frontmatter.due = nil
                document.frontmatter.dueTime = nil
                document.frontmatter.persistentReminder = nil
            }
            refreshNotificationsBestEffort()
        } catch {
            return
        }
    }

    nonisolated private func refreshNotificationsBestEffort() {
        Task.detached(priority: .utility) {
            do {
                let rootURL = try TaskFolderLocator().ensureFolderExists()
                let repository = FileTaskRepository(rootURL: rootURL)
                let records = try TaskRecordSnapshotStore().hydrate(rootURL: rootURL, repository: repository).records
                let planner = Self.notificationPlannerFromSettings()
                let hasLocationReminders = records.contains { $0.document.frontmatter.locationReminder != nil }
                let scheduler = await MainActor.run { UserNotificationScheduler() }
                await scheduler.requestAuthorizationIfNeeded(requestLocation: hasLocationReminders)
                await scheduler.synchronize(records: records, planner: planner)
            } catch {
                // Non-fatal.
            }

#if canImport(BackgroundTasks)
            NotificationBackgroundRefreshCoordinator.scheduleNextRefresh()
#endif
        }
    }

    nonisolated private func localDateByAddingDays(_ localDate: LocalDate, days: Int) -> LocalDate? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        var components = DateComponents()
        components.calendar = calendar
        components.year = localDate.year
        components.month = localDate.month
        components.day = localDate.day

        guard let baseDate = components.date,
              let adjustedDate = calendar.date(byAdding: .day, value: days, to: baseDate) else {
            return nil
        }

        let adjusted = calendar.dateComponents([.year, .month, .day], from: adjustedDate)
        guard let year = adjusted.year, let month = adjusted.month, let day = adjusted.day else {
            return nil
        }
        return try? LocalDate(year: year, month: month, day: day)
    }

    nonisolated private func isActiveStatus(_ status: TaskStatus) -> Bool {
        status == .todo || status == .inProgress
    }

    nonisolated private static func notificationPlannerFromSettings() -> NotificationPlanner {
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
#else
final class AppDelegate: NSObject {}
#endif

#if canImport(UIKit) && canImport(UserNotifications) && canImport(BackgroundTasks)
enum NotificationBackgroundRefreshCoordinator {
    static let taskIdentifier = "com.hans.todomd.notifications.refresh"
    private static let minimumRefreshInterval: TimeInterval = 30 * 60
    private static var isDisabledForCurrentProcess: Bool {
        let processInfo = ProcessInfo.processInfo
        if processInfo.arguments.contains("-ui-testing") {
            return true
        }
        return processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static func registerBackgroundTask() {
        guard !isDisabledForCurrentProcess else { return }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let appRefreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(appRefreshTask)
        }
    }

    static func scheduleNextRefresh() {
        guard !isDisabledForCurrentProcess else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumRefreshInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Keep non-fatal: best effort scheduling only.
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        guard !isDisabledForCurrentProcess else {
            task.setTaskCompleted(success: false)
            return
        }
        scheduleNextRefresh()

        let refreshTask = Task {
            let success = await runRefresh()
            task.setTaskCompleted(success: !Task.isCancelled && success)
        }

        task.expirationHandler = {
            refreshTask.cancel()
        }
    }

    private static func runRefresh() async -> Bool {
        do {
            let rootURL = try TaskFolderLocator().ensureFolderExists()
            let repository = FileTaskRepository(rootURL: rootURL)
            let records = try TaskRecordSnapshotStore().hydrate(rootURL: rootURL, repository: repository).records
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
