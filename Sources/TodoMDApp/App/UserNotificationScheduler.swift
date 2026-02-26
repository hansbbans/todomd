import Foundation
#if canImport(UserNotifications)
import UserNotifications

@MainActor
final class UserNotificationScheduler {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func synchronize(records: [TaskRecord], planner: NotificationPlanner) async {
        let allPlans = records.flatMap { planner.planNotifications(for: $0) }
        let existingIDs = await pendingTodoNotificationIdentifiers()
        let identifiers = Set(allPlans.map(\.identifier)).union(existingIDs)

        center.removePendingNotificationRequests(withIdentifiers: Array(identifiers))

        for plan in allPlans {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            content.categoryIdentifier = NotificationActionIdentifiers.category
            content.userInfo = [
                "task_path": plan.taskPath,
                "notification_kind": plan.kind.rawValue
            ]

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)
            do {
                try await center.add(request)
            } catch {
                // Keep non-fatal: notification errors must not block task data flow.
            }
        }
    }

    func requestAuthorizationIfNeeded() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // Non-fatal.
        }
    }

    private func pendingTodoNotificationIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                let ids = requests
                    .map(\.identifier)
                    .filter { $0.hasSuffix("#due") || $0.hasSuffix("#defer") }
                continuation.resume(returning: ids)
            }
        }
    }
}
#endif
