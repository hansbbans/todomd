import Foundation
#if canImport(UserNotifications)
import UserNotifications

@MainActor
protocol NotificationScheduling: AnyObject {
    func requestAuthorizationIfNeeded(requestLocation: Bool) async
    func synchronize(upsertedRecords: [TaskRecord], deletedPaths: [String], planner: NotificationPlanner) async
    func scheduleAutoUnblockedNotification(taskPath: String, title: String) async
}

extension UserNotificationScheduler: NotificationScheduling {}

@MainActor
final class NotificationCoordinator {
    private let scheduler: any NotificationScheduling
    private let userDefaults: UserDefaults
    private var notificationPlanCountByPath: [String: Int] = [:]
    private var locationNotificationCountByPath: [String: Int] = [:]
    private var notificationsPrimed = false

    private static let settingsNotificationHourKey = "settings_notification_hour"
    private static let settingsNotificationMinuteKey = "settings_notification_minute"
    private static let settingsNotifyAutoUnblockedKey = "settings_notify_auto_unblocked"
    private static let settingsPersistentRemindersEnabledKey = "settings_persistent_reminders_enabled"
    private static let settingsPersistentReminderIntervalMinutesKey = "settings_persistent_reminder_interval_minutes"

    init(
        scheduler: any NotificationScheduling = UserNotificationScheduler(),
        userDefaults: UserDefaults = .standard
    ) {
        self.scheduler = scheduler
        self.userDefaults = userDefaults
    }

    @discardableResult
    func handleRefresh(
        upsertedRecords: [TaskRecord],
        deletedPaths: Set<String>,
        allRecords: [TaskRecord]
    ) -> Int {
        let planner = plannerFromCurrentSettings()
        updateNotificationCounts(
            upsertedRecords: upsertedRecords,
            deletedPaths: deletedPaths,
            planner: planner,
            allRecords: allRecords
        )

        let hasLocationReminders = allRecords.contains { $0.document.frontmatter.locationReminder != nil }
        let recordsToSynchronize = notificationsPrimed ? upsertedRecords : allRecords
        let deletedPathsToSynchronize = notificationsPrimed ? Array(deletedPaths) : []

        Task {
            await scheduler.requestAuthorizationIfNeeded(requestLocation: hasLocationReminders)
            await scheduler.synchronize(
                upsertedRecords: recordsToSynchronize,
                deletedPaths: deletedPathsToSynchronize,
                planner: planner
            )
        }

        notificationsPrimed = true
        return pendingNotificationCount
    }

    func reset() {
        notificationPlanCountByPath.removeAll()
        locationNotificationCountByPath.removeAll()
        notificationsPrimed = false
    }

    func scheduleAutoUnblockedNotification(taskPath: String, title: String) {
        Task {
            await scheduler.scheduleAutoUnblockedNotification(taskPath: taskPath, title: title)
        }
    }

    func plannerFromCurrentSettings() -> NotificationPlanner {
        let hour = userDefaults.object(forKey: Self.settingsNotificationHourKey) as? Int ?? 9
        let minute = userDefaults.object(forKey: Self.settingsNotificationMinuteKey) as? Int ?? 0
        let persistentEnabled = userDefaults.object(forKey: Self.settingsPersistentRemindersEnabledKey) as? Bool ?? false
        let persistentIntervalMinutes = userDefaults.object(forKey: Self.settingsPersistentReminderIntervalMinutesKey) as? Int ?? 1

        return NotificationPlanner(
            calendar: .current,
            defaultHour: min(23, max(0, hour)),
            defaultMinute: min(59, max(0, minute)),
            persistentRemindersEnabled: persistentEnabled,
            persistentReminderIntervalMinutes: max(1, min(240, persistentIntervalMinutes))
        )
    }

    var isAutoUnblockedNotificationsEnabled: Bool {
        userDefaults.object(forKey: Self.settingsNotifyAutoUnblockedKey) as? Bool ?? true
    }

    private func updateNotificationCounts(
        upsertedRecords: [TaskRecord],
        deletedPaths: Set<String>,
        planner: NotificationPlanner,
        allRecords: [TaskRecord]
    ) {
        let seedRecords = notificationsPrimed ? upsertedRecords : allRecords

        for path in deletedPaths {
            notificationPlanCountByPath.removeValue(forKey: path)
            locationNotificationCountByPath.removeValue(forKey: path)
        }

        for record in seedRecords {
            notificationPlanCountByPath[record.identity.path] = planner.planNotifications(for: record).count
            let status = record.document.frontmatter.status
            let hasLocationReminder = (status == .todo || status == .inProgress) && record.document.frontmatter.locationReminder != nil
            locationNotificationCountByPath[record.identity.path] = hasLocationReminder ? 1 : 0
        }
    }

    private var pendingNotificationCount: Int {
        notificationPlanCountByPath.values.reduce(0, +) + locationNotificationCountByPath.values.reduce(0, +)
    }
}
#endif
