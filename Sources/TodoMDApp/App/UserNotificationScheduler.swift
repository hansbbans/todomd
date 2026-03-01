import Foundation
#if canImport(UserNotifications)
import UserNotifications
#if canImport(CoreLocation)
import CoreLocation
#endif

@MainActor
final class UserNotificationScheduler {
    private let center: UNUserNotificationCenter
    private let maxPendingTimedNotifications = 64
    private let maxPendingLocationNotifications = 20
    private let maxCatchUpNotificationsPerSync = 8
    private let catchUpGraceWindowSeconds: TimeInterval = 30 * 60
    private let catchUpLedgerTTLSeconds: TimeInterval = 7 * 24 * 60 * 60
    private let catchUpLedgerLimit = 1024
    private let catchUpLedgerKey = "notifications_due_catchup_ledger_v1"
#if canImport(CoreLocation)
    private let locationAuthorizationRequester = LocationAuthorizationRequester()
#endif

    private struct PlannedLocationNotification {
        let identifier: String
        let taskPath: String
        let kind: TaskLocationReminderTrigger
        let title: String
        let body: String
        let latitude: Double
        let longitude: Double
        let radiusMeters: Double
    }

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func synchronize(records: [TaskRecord], planner: NotificationPlanner) async {
        let now = Date()
        let allPlans = records
            .flatMap { planner.planNotifications(for: $0, referenceDate: now) }
            .sorted { $0.fireDate < $1.fireDate }
        let allLocationPlans = locationNotificationPlans(records: records)

        let futurePlans = allPlans.filter { $0.fireDate > now }
        let catchUpPlans = dueCatchUpPlans(from: allPlans, now: now)

        let futureBudget = max(0, maxPendingTimedNotifications - catchUpPlans.count)
        let selectedFuturePlans = Array(futurePlans.prefix(futureBudget))
        let selectedLocationPlans = Array(allLocationPlans.prefix(maxPendingLocationNotifications))
        let existingIDs = await pendingManagedNotificationIdentifiers()

        let identifiers = Set(selectedFuturePlans.map(\.identifier))
            .union(selectedLocationPlans.map(\.identifier))
            .union(catchUpPlans.map(\.identifier))
            .union(existingIDs)

        center.removePendingNotificationRequests(withIdentifiers: Array(identifiers))

        for plan in selectedFuturePlans {
            let content = notificationContent(
                title: plan.title,
                body: plan.body,
                taskPath: plan.taskPath,
                kind: plan.kind.rawValue
            )
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: plan.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)
            do {
                try await center.add(request)
            } catch {
                // Keep non-fatal: notification errors must not block task data flow.
            }
        }

        for plan in catchUpPlans {
            let content = notificationContent(
                title: plan.title,
                body: "Due now",
                taskPath: plan.taskPath,
                kind: plan.kind.rawValue
            )
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)
            do {
                try await center.add(request)
                recordCatchUpIdentifier(plan.identifier, now: now)
            } catch {
                // Keep non-fatal: notification errors must not block task data flow.
            }
        }

#if canImport(CoreLocation)
        for plan in selectedLocationPlans {
            let content = notificationContent(
                title: plan.title,
                body: plan.body,
                taskPath: plan.taskPath,
                kind: notificationKind(for: plan.kind)
            )
            let center = CLLocationCoordinate2D(latitude: plan.latitude, longitude: plan.longitude)
            let region = CLCircularRegion(center: center, radius: plan.radiusMeters, identifier: plan.identifier)
            region.notifyOnEntry = plan.kind == .onArrival
            region.notifyOnExit = plan.kind == .onDeparture
            let trigger = UNLocationNotificationTrigger(region: region, repeats: true)
            let request = UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)
            do {
                try await self.center.add(request)
            } catch {
                // Keep non-fatal: notification errors must not block task data flow.
            }
        }
#endif
    }

    func requestAuthorizationIfNeeded(requestLocation: Bool) async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // Non-fatal.
        }

#if canImport(CoreLocation)
        if requestLocation {
            await locationAuthorizationRequester.requestIfNeeded()
        }
#endif
    }

    func scheduleAutoUnblockedNotification(taskPath: String, title: String) async {
        let content = notificationContent(
            title: title,
            body: "Task is now unblocked and ready to work on.",
            taskPath: taskPath,
            kind: "auto_unblocked"
        )
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let identifier = "auto-unblocked-\(abs(taskPath.hashValue))"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            // Keep non-fatal.
        }
    }

    private func dueCatchUpPlans(from allPlans: [PlannedNotification], now: Date) -> [PlannedNotification] {
        let oldestAllowed = now.addingTimeInterval(-catchUpGraceWindowSeconds)
        let ledger = loadCatchUpLedger(now: now)
        var selected: [PlannedNotification] = []
        selected.reserveCapacity(maxCatchUpNotificationsPerSync)

        for plan in allPlans {
            guard plan.kind == .due else { continue }
            guard plan.fireDate <= now else { continue }
            guard plan.fireDate >= oldestAllowed else { continue }

            let catchUpIdentifier = catchUpNotificationIdentifier(for: plan)
            guard ledger[catchUpIdentifier] == nil else { continue }

            selected.append(
                PlannedNotification(
                    identifier: catchUpIdentifier,
                    taskPath: plan.taskPath,
                    kind: .due,
                    fireDate: now,
                    title: plan.title,
                    body: plan.body
                )
            )

            if selected.count >= maxCatchUpNotificationsPerSync {
                break
            }
        }

        return selected
    }

    private func catchUpNotificationIdentifier(for plan: PlannedNotification) -> String {
        "\(plan.identifier)#catchup-\(Int(plan.fireDate.timeIntervalSince1970))"
    }

    private func loadCatchUpLedger(now: Date) -> [String: TimeInterval] {
        let raw = UserDefaults.standard.dictionary(forKey: catchUpLedgerKey) as? [String: TimeInterval] ?? [:]
        guard !raw.isEmpty else { return [:] }

        let cutoff = now.timeIntervalSince1970 - catchUpLedgerTTLSeconds
        var filtered: [String: TimeInterval] = [:]
        filtered.reserveCapacity(min(raw.count, catchUpLedgerLimit))

        for (id, timestamp) in raw where timestamp >= cutoff {
            filtered[id] = timestamp
        }

        return trimCatchUpLedger(filtered)
    }

    private func recordCatchUpIdentifier(_ identifier: String, now: Date) {
        var ledger = loadCatchUpLedger(now: now)
        ledger[identifier] = now.timeIntervalSince1970
        let trimmed = trimCatchUpLedger(ledger)
        UserDefaults.standard.set(trimmed, forKey: catchUpLedgerKey)
    }

    private func trimCatchUpLedger(_ ledger: [String: TimeInterval]) -> [String: TimeInterval] {
        guard ledger.count > catchUpLedgerLimit else { return ledger }
        let sorted = ledger.sorted { $0.value > $1.value }
        var trimmed: [String: TimeInterval] = [:]
        trimmed.reserveCapacity(catchUpLedgerLimit)
        for (index, pair) in sorted.enumerated() where index < catchUpLedgerLimit {
            trimmed[pair.key] = pair.value
        }
        return trimmed
    }

    private func notificationContent(title: String, body: String, taskPath: String, kind: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = NotificationActionIdentifiers.category
        if #available(iOS 15.0, *) {
            // Respect Focus mode defaults; do not elevate reminders.
            content.interruptionLevel = .active
        }
        content.userInfo = [
            "task_path": taskPath,
            "notification_kind": kind
        ]
        return content
    }

    private func locationNotificationPlans(records: [TaskRecord]) -> [PlannedLocationNotification] {
        records
            .filter { record in
                let status = record.document.frontmatter.status
                return (status == .todo || status == .inProgress) && record.document.frontmatter.locationReminder != nil
            }
            .sorted { $0.identity.filename < $1.identity.filename }
            .compactMap { record in
                guard let locationReminder = record.document.frontmatter.locationReminder else { return nil }
                let locationName = locationReminder.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                let body: String
                if let locationName, !locationName.isEmpty {
                    body = locationReminder.trigger == .onArrival ? "Arriving at \(locationName)" : "Leaving \(locationName)"
                } else {
                    body = locationReminder.trigger == .onArrival ? "Arrived at location" : "Left location"
                }

                return PlannedLocationNotification(
                    identifier: locationNotificationIdentifier(
                        filename: record.identity.filename,
                        trigger: locationReminder.trigger
                    ),
                    taskPath: record.identity.path,
                    kind: locationReminder.trigger,
                    title: record.document.frontmatter.title,
                    body: body,
                    latitude: locationReminder.latitude,
                    longitude: locationReminder.longitude,
                    radiusMeters: min(1_000, max(50, locationReminder.radiusMeters))
                )
            }
    }

    private func locationNotificationIdentifier(filename: String, trigger: TaskLocationReminderTrigger) -> String {
        let suffix = trigger == .onArrival ? "arrive" : "leave"
        return "\(filename)#loc-\(suffix)"
    }

    private func notificationKind(for trigger: TaskLocationReminderTrigger) -> String {
        switch trigger {
        case .onArrival:
            return "location_arrive"
        case .onDeparture:
            return "location_leave"
        }
    }

    private func pendingManagedNotificationIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                let ids = requests
                    .map(\.identifier)
                    .filter(Self.isManagedNotificationIdentifier)
                continuation.resume(returning: ids)
            }
        }
    }

    nonisolated private static func isManagedNotificationIdentifier(_ identifier: String) -> Bool {
        identifier.hasSuffix("#due")
            || identifier.hasSuffix("#defer")
            || identifier.contains("#nag-")
            || identifier.hasSuffix("#loc-arrive")
            || identifier.hasSuffix("#loc-leave")
    }
}

#if canImport(CoreLocation)
@MainActor
private final class LocationAuthorizationRequester: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuations: [CheckedContinuation<Void, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestIfNeeded() async {
        guard CLLocationManager.locationServicesEnabled() else { return }

        let authorization = manager.authorizationStatus
        guard authorization == .notDetermined else { return }

        await withCheckedContinuation { continuation in
            continuations.append(continuation)
            if continuations.count == 1 {
                manager.requestWhenInUseAuthorization()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.resumeIfResolved(status: status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.resumeIfResolved(status: status)
        }
    }

    private func resumeIfResolved(status: CLAuthorizationStatus) {
        guard status != .notDetermined else { return }
        guard !continuations.isEmpty else { return }

        let pending = continuations
        continuations.removeAll(keepingCapacity: true)
        pending.forEach { $0.resume() }
    }
}
#endif
#endif
