import Foundation
#if canImport(UserNotifications)
import UserNotifications

/// Coordinates notification scheduling for task records.
///
/// Extracted from AppContainer to isolate notification scheduling
/// responsibilities. AppContainer continues to own the scheduler instance
/// and settings keys; this class provides a clean, composable wrapper
/// for the scheduling logic.
@MainActor
final class NotificationCoordinator {
    private let scheduler: UserNotificationScheduler

    // UserDefaults keys mirroring AppContainer's constants.
    private static let settingsNotificationHourKey = "settings_notification_hour"
    private static let settingsNotificationMinuteKey = "settings_notification_minute"
    private static let settingsNotifyAutoUnblockedKey = "settings_notify_auto_unblocked"
    private static let settingsPersistentRemindersEnabledKey = "settings_persistent_reminders_enabled"
    private static let settingsPersistentReminderIntervalMinutesKey = "settings_persistent_reminder_interval_minutes"

    init(scheduler: UserNotificationScheduler = UserNotificationScheduler()) {
        self.scheduler = scheduler
    }

    /// Schedules (or reschedules) all pending notifications for the given records.
    ///
    /// Requests notification authorization first if it has not been granted yet.
    /// Passes the current settings-derived `NotificationPlanner` to the scheduler.
    ///
    /// - Parameter records: The full set of task records to plan notifications for.
    func schedule(records: [TaskRecord]) {
        let hasLocationReminders = records.contains { $0.document.frontmatter.locationReminder != nil }
        let planner = plannerFromCurrentSettings()

        Task {
            await requestAuthorizationIfNeeded(hasLocationReminders: hasLocationReminders)
            await scheduler.synchronize(records: records, planner: planner)
        }
    }

    /// Requests notification (and optionally location) authorization from the user.
    ///
    /// Safe to call repeatedly — the underlying system prompt is shown at most once.
    ///
    /// - Parameter hasLocationReminders: Pass `true` when any task has a location-based reminder so
    ///   the location authorization prompt is also shown.
    func requestAuthorizationIfNeeded(hasLocationReminders: Bool) async {
        await scheduler.requestAuthorizationIfNeeded(requestLocation: hasLocationReminders)
    }

    /// Schedules a one-shot "auto-unblocked" notification for the given task.
    ///
    /// - Parameters:
    ///   - taskPath: The file path of the unblocked task.
    ///   - title: The task's title used as the notification headline.
    func scheduleAutoUnblockedNotification(taskPath: String, title: String) {
        Task {
            await scheduler.scheduleAutoUnblockedNotification(taskPath: taskPath, title: title)
        }
    }

    // MARK: - Settings helpers

    /// Builds a `NotificationPlanner` from the user's current `UserDefaults` settings.
    func plannerFromCurrentSettings() -> NotificationPlanner {
        let defaults = UserDefaults.standard
        let hour = defaults.object(forKey: Self.settingsNotificationHourKey) as? Int ?? 9
        let minute = defaults.object(forKey: Self.settingsNotificationMinuteKey) as? Int ?? 0
        let persistentEnabled = defaults.object(forKey: Self.settingsPersistentRemindersEnabledKey) as? Bool ?? false
        let persistentIntervalMinutes = defaults.object(forKey: Self.settingsPersistentReminderIntervalMinutesKey) as? Int ?? 1

        return NotificationPlanner(
            calendar: .current,
            defaultHour: min(23, max(0, hour)),
            defaultMinute: min(59, max(0, minute)),
            persistentRemindersEnabled: persistentEnabled,
            persistentReminderIntervalMinutes: max(1, min(240, persistentIntervalMinutes))
        )
    }

    /// Returns `true` when the user setting to notify on auto-unblocked tasks is enabled (defaults to `true`).
    var isAutoUnblockedNotificationsEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.settingsNotifyAutoUnblockedKey) as? Bool ?? true
    }
}
#endif
