import Foundation
import Testing
#if canImport(UserNotifications)
@testable import TodoMDApp

@MainActor
struct NotificationCoordinatorTests {
    @Test("First refresh seeds pending counts from all records and schedules a full sync")
    func firstRefreshSeedsPendingCountsFromAllRecords() async throws {
        let suiteName = "NotificationCoordinatorTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let scheduler = FakeNotificationScheduler()
        let coordinator = NotificationCoordinator(scheduler: scheduler, userDefaults: defaults)
        let dueRecord = try makeDueRecord(title: "Pay rent", path: "/tmp/pay-rent.md")
        let locationRecord = makeLocationRecord(title: "Pick up order", path: "/tmp/pick-up-order.md")

        let pendingCount = coordinator.handleRefresh(
            upsertedRecords: [dueRecord],
            deletedPaths: [],
            allRecords: [dueRecord, locationRecord]
        )

        #expect(pendingCount == 2)

        let sync = await scheduler.nextSync()
        #expect(sync.requestedLocationAuthorization)
        #expect(sync.recordPaths == ["/tmp/pay-rent.md", "/tmp/pick-up-order.md"])
        #expect(sync.deletedPaths.isEmpty)
    }

    @Test("Later refreshes synchronize deltas and clear deleted notification counts")
    func laterRefreshesSynchronizeDeltasAndClearDeletedCounts() async throws {
        let suiteName = "NotificationCoordinatorTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let scheduler = FakeNotificationScheduler()
        let coordinator = NotificationCoordinator(scheduler: scheduler, userDefaults: defaults)
        let dueRecord = try makeDueRecord(title: "Pay rent", path: "/tmp/pay-rent.md")
        let locationRecord = makeLocationRecord(title: "Pick up order", path: "/tmp/pick-up-order.md")

        _ = coordinator.handleRefresh(
            upsertedRecords: [dueRecord],
            deletedPaths: [],
            allRecords: [dueRecord, locationRecord]
        )
        _ = await scheduler.nextSync()

        let pendingCount = coordinator.handleRefresh(
            upsertedRecords: [dueRecord],
            deletedPaths: [locationRecord.identity.path],
            allRecords: [dueRecord]
        )

        #expect(pendingCount == 1)

        let sync = await scheduler.nextSync()
        #expect(sync.requestedLocationAuthorization == false)
        #expect(sync.recordPaths == ["/tmp/pay-rent.md"])
        #expect(Set(sync.deletedPaths) == Set(["/tmp/pick-up-order.md"]))
    }

    private func makeDueRecord(title: String, path: String) throws -> TaskRecord {
        let frontmatter = TaskFrontmatterV1(
            title: title,
            status: .todo,
            due: try LocalDate(isoDate: "2026-03-27"),
            priority: .none,
            flagged: false,
            created: Date(timeIntervalSince1970: 1_700_000_000),
            modified: Date(timeIntervalSince1970: 1_700_000_000),
            source: "test"
        )

        return TaskRecord(
            identity: TaskFileIdentity(path: path),
            document: TaskDocument(frontmatter: frontmatter, body: "")
        )
    }

    private func makeLocationRecord(title: String, path: String) -> TaskRecord {
        let frontmatter = TaskFrontmatterV1(
            title: title,
            status: .todo,
            priority: .none,
            flagged: false,
            locationReminder: TaskLocationReminder(
                name: "Store",
                latitude: 40.7128,
                longitude: -74.0060,
                trigger: .onArrival
            ),
            created: Date(timeIntervalSince1970: 1_700_000_000),
            modified: Date(timeIntervalSince1970: 1_700_000_000),
            source: "test"
        )

        return TaskRecord(
            identity: TaskFileIdentity(path: path),
            document: TaskDocument(frontmatter: frontmatter, body: "")
        )
    }
}

@MainActor
private final class FakeNotificationScheduler: NotificationScheduling, @unchecked Sendable {
    private let syncRecorder = SyncRecorder()
    private let authorizationState = AuthorizationState()

    func requestAuthorizationIfNeeded(requestLocation: Bool) async {
        await authorizationState.record(requestLocation: requestLocation)
    }

    func synchronize(upsertedRecords: [TaskRecord], deletedPaths: [String], planner: NotificationPlanner) async {
        let requestedLocationAuthorization = await authorizationState.consumeLatest()
        await syncRecorder.record(
            SyncCall(
                requestedLocationAuthorization: requestedLocationAuthorization,
                recordPaths: upsertedRecords.map(\.identity.path),
                deletedPaths: deletedPaths
            )
        )
    }

    func scheduleAutoUnblockedNotification(taskPath: String, title: String) async {
        _ = taskPath
        _ = title
    }

    func nextSync() async -> SyncCall {
        await syncRecorder.next()
    }
}

private struct SyncCall: Sendable {
    let requestedLocationAuthorization: Bool
    let recordPaths: [String]
    let deletedPaths: [String]
}

private actor AuthorizationState {
    private var latest = false

    func record(requestLocation: Bool) {
        latest = requestLocation
    }

    func consumeLatest() -> Bool {
        latest
    }
}

private actor SyncRecorder {
    private var pending: [SyncCall] = []
    private var continuations: [CheckedContinuation<SyncCall, Never>] = []

    func record(_ value: SyncCall) {
        if let continuation = continuations.first {
            continuations.removeFirst()
            continuation.resume(returning: value)
        } else {
            pending.append(value)
        }
    }

    func next() async -> SyncCall {
        if !pending.isEmpty {
            return pending.removeFirst()
        }

        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }
}
#endif
