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
    private var timedPlansByPath: [String: [PlannedNotification]] = [:]
    private var locationPlansByPath: [String: [PlannedLocationNotification]] = [:]
    private var scheduledTimedPlansByIdentifier: [String: PlannedNotification] = [:]
    private var scheduledLocationPlansByIdentifier: [String: PlannedLocationNotification] = [:]
#if canImport(CoreLocation)
    private let locationAuthorizationRequester = LocationAuthorizationRequester()
#endif

    private struct PlannedLocationNotification: Equatable {
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
        timedPlansByPath = Dictionary(uniqueKeysWithValues: records.map {
            ($0.identity.path, planner.planNotifications(for: $0, referenceDate: Date()))
        })
        locationPlansByPath = Dictionary(uniqueKeysWithValues: records.map {
            ($0.identity.path, locationNotificationPlans(for: $0))
        })
        await applyPendingNotifications(now: Date())
    }

    func synchronize(upsertedRecords: [TaskRecord], deletedPaths: [String], planner: NotificationPlanner) async {
        let now = Date()

        for path in deletedPaths {
            timedPlansByPath.removeValue(forKey: path)
            locationPlansByPath.removeValue(forKey: path)
        }

        for record in upsertedRecords {
            timedPlansByPath[record.identity.path] = planner.planNotifications(for: record, referenceDate: now)
            locationPlansByPath[record.identity.path] = locationNotificationPlans(for: record)
        }

        await applyPendingNotifications(now: now)
    }

    private func applyPendingNotifications(now: Date) async {
        let allPlans = timedPlansByPath.values
            .flatMap { $0 }
            .sorted { $0.fireDate < $1.fireDate }
        let allLocationPlans = locationPlansByPath.values
            .flatMap { $0 }
            .sorted { $0.identifier < $1.identifier }

        let futurePlans = allPlans.filter { $0.fireDate > now }
        let catchUpPlans = dueCatchUpPlans(from: allPlans, now: now)

        let futureBudget = max(0, maxPendingTimedNotifications - catchUpPlans.count)
        let selectedFuturePlans = Array(futurePlans.prefix(futureBudget))
        let selectedLocationPlans = Array(allLocationPlans.prefix(maxPendingLocationNotifications))
        let existingIDs = await pendingManagedNotificationIdentifiers()
        let existingIDSet = Set(existingIDs)
        let catchUpIdentifiers = Set(catchUpPlans.map(\.identifier))
        let desiredTimedPlansByIdentifier = Dictionary(
            uniqueKeysWithValues: (selectedFuturePlans + catchUpPlans).map { ($0.identifier, $0) }
        )
        let desiredLocationPlansByIdentifier = Dictionary(
            uniqueKeysWithValues: selectedLocationPlans.map { ($0.identifier, $0) }
        )

        var identifiersToRemove = existingIDSet
            .subtracting(desiredTimedPlansByIdentifier.keys)
            .subtracting(desiredLocationPlansByIdentifier.keys)
        var timedPlansToAdd: [PlannedNotification] = []
        var locationPlansToAdd: [PlannedLocationNotification] = []

        for plan in desiredTimedPlansByIdentifier.values {
            let current = scheduledTimedPlansByIdentifier[plan.identifier]
            let needsReplace = current != plan || (current == nil && existingIDSet.contains(plan.identifier))
            if needsReplace {
                identifiersToRemove.insert(plan.identifier)
                timedPlansToAdd.append(plan)
            }
        }

        for plan in desiredLocationPlansByIdentifier.values {
            let current = scheduledLocationPlansByIdentifier[plan.identifier]
            let needsReplace = current != plan || (current == nil && existingIDSet.contains(plan.identifier))
            if needsReplace {
                identifiersToRemove.insert(plan.identifier)
                locationPlansToAdd.append(plan)
            }
        }

        if !identifiersToRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(identifiersToRemove))
        }

        for plan in timedPlansToAdd.sorted(by: { $0.fireDate < $1.fireDate }) {
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
                if catchUpIdentifiers.contains(plan.identifier) {
                    recordCatchUpIdentifier(plan.identifier, now: now)
                }
            } catch {
                // Keep non-fatal: notification errors must not block task data flow.
            }
        }

#if canImport(CoreLocation) && !os(macOS)
        for plan in locationPlansToAdd.sorted(by: { $0.identifier < $1.identifier }) {
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

        scheduledTimedPlansByIdentifier = desiredTimedPlansByIdentifier
        scheduledLocationPlansByIdentifier = desiredLocationPlansByIdentifier
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
            // Always catch up for same-day due notifications: the user may have created
            // the task after the default notification time (e.g. task added at 10 AM for a
            // due date whose default fire time is 9 AM). For tasks from earlier days the
            // original 30-minute window is sufficient — a same-day check avoids a flood
            // of notifications for long-overdue tasks.
            let isDueToday = Calendar.current.isDate(plan.fireDate, inSameDayAs: now)
            guard isDueToday || plan.fireDate >= oldestAllowed else { continue }

            let catchUpIdentifier = catchUpNotificationIdentifier(for: plan)
            guard ledger[catchUpIdentifier] == nil else { continue }

            selected.append(
                PlannedNotification(
                    identifier: catchUpIdentifier,
                    taskPath: plan.taskPath,
                    kind: .due,
                    fireDate: now,
                    title: plan.title,
                    body: "Due now"
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

    private func locationNotificationPlans(for record: TaskRecord) -> [PlannedLocationNotification] {
        let status = record.document.frontmatter.status
        guard (status == .todo || status == .inProgress),
              let locationReminder = record.document.frontmatter.locationReminder else {
            return []
        }

        let locationName = locationReminder.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: String
        if let locationName, !locationName.isEmpty {
            body = locationReminder.trigger == .onArrival ? "Arriving at \(locationName)" : "Leaving \(locationName)"
        } else {
            body = locationReminder.trigger == .onArrival ? "Arrived at location" : "Left location"
        }

        return [
            PlannedLocationNotification(
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
        ]
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
