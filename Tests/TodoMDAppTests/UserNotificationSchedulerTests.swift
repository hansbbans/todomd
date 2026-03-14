import Dispatch
import Foundation
import Testing
#if canImport(UserNotifications)
    import UserNotifications
#endif
@testable import TodoMDApp

#if canImport(UserNotifications)
    @MainActor
    struct UserNotificationSchedulerTests {
        @Test("Pending notification callbacks can arrive off the main actor")
        func pendingNotificationCallbacksCanArriveOffTheMainActor() async {
            let request = makeRequest(identifier: "example.md#due")
            let center = FakeUserNotificationCenter(pendingRequests: [request])
            let scheduler = UserNotificationScheduler(center: center)

            await scheduler.synchronize(records: [], planner: NotificationPlanner())

            let removed = await center.nextRemoval()
            #expect(removed == ["example.md#due"])
        }

        @Test("Cancelling notifications tolerates pending request callbacks off the main actor")
        func cancellingNotificationsToleratesPendingRequestCallbacksOffTheMainActor() async {
            let taskPath = "/tmp/example.md"
            let request = makeRequest(identifier: "example.md#due", taskPath: taskPath)
            let center = FakeUserNotificationCenter(pendingRequests: [request])
            let scheduler = UserNotificationScheduler(center: center)

            scheduler.cancelNotifications(forTaskPath: taskPath)

            let removed = await center.nextRemoval()
            #expect(removed == ["example.md#due"])
        }

        private func makeRequest(identifier: String, taskPath: String? = nil) -> UNNotificationRequest {
            let content = UNMutableNotificationContent()
            content.title = "Example"
            if let taskPath {
                content.userInfo["task_path"] = taskPath
            }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
            return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        }
    }

    private final class FakeUserNotificationCenter: UserNotificationCentering, @unchecked Sendable {
        let pendingRequests: [UNNotificationRequest]
        private let removalRecorder = RemovalRecorder()

        init(pendingRequests: [UNNotificationRequest]) {
            self.pendingRequests = pendingRequests
        }

        func add(_ request: UNNotificationRequest) async throws {}

        func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
            true
        }

        func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
            Task {
                await removalRecorder.record(identifiers)
            }
        }

        func getPendingNotificationRequests(completionHandler: @escaping @Sendable ([UNNotificationRequest]) -> Void) {
            DispatchQueue.global(qos: .utility).async {
                completionHandler(self.pendingRequests)
            }
        }

        func nextRemoval() async -> [String] {
            await removalRecorder.next()
        }
    }

    private actor RemovalRecorder {
        private var pending: [String]?
        private var continuation: CheckedContinuation<[String], Never>?

        func record(_ identifiers: [String]) {
            if let continuation {
                self.continuation = nil
                continuation.resume(returning: identifiers)
            } else {
                pending = identifiers
            }
        }

        func next() async -> [String] {
            if let pending {
                self.pending = nil
                return pending
            }

            return await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
    }
#endif
