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

        @Test("Agent-created task notifications include the source and task path")
        func agentCreatedTaskNotificationsIncludeTheSourceAndTaskPath() async {
            let center = FakeUserNotificationCenter()
            let scheduler = UserNotificationScheduler(center: center)
            let taskPath = "/tmp/agent-task.md"

            await scheduler.scheduleAgentCreatedTaskNotification(
                taskPath: taskPath,
                title: "Review generated task",
                source: "claude-agent"
            )

            let added = await center.nextAddedRequest()
            #expect(added.identifier == "agent-created-\(abs(taskPath.hashValue))")
            #expect(added.title == "Review generated task")
            #expect(added.body == "Created by claude-agent")
            #expect(added.taskPath == taskPath)
            #expect(added.notificationKind == "agent_created")
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
        private let addRecorder = RequestRecorder<AddedRequestSnapshot>()
        private let removalRecorder = RemovalRecorder()

        init(pendingRequests: [UNNotificationRequest] = []) {
            self.pendingRequests = pendingRequests
        }

        func add(_ request: UNNotificationRequest) async throws {
            await addRecorder.record(
                AddedRequestSnapshot(
                    identifier: request.identifier,
                    title: request.content.title,
                    body: request.content.body,
                    taskPath: request.content.userInfo["task_path"] as? String,
                    notificationKind: request.content.userInfo["notification_kind"] as? String
                )
            )
        }

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

        func nextAddedRequest() async -> AddedRequestSnapshot {
            await addRecorder.next()
        }
    }

    private struct AddedRequestSnapshot: Sendable {
        let identifier: String
        let title: String
        let body: String
        let taskPath: String?
        let notificationKind: String?
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

    private actor RequestRecorder<Value: Sendable> {
        private var pending: Value?
        private var continuation: CheckedContinuation<Value, Never>?

        func record(_ value: Value) {
            if let continuation {
                self.continuation = nil
                continuation.resume(returning: value)
            } else {
                pending = value
            }
        }

        func next() async -> Value {
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
