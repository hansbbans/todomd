import EventKit
import Testing
@testable import TodoMDApp

@MainActor
struct AppleCalendarServiceTests {
    @Test("Legacy authorized calendar access counts as connected")
    func authorizedStatusCountsAsConnected() {
        let service = makeService(status: legacyAuthorizedStatus)

        #expect(service.isConnected)
    }

    @Test("Full calendar access counts as connected")
    func fullAccessCountsAsConnected() {
        let service = makeService(status: .fullAccess)

        #expect(service.isConnected)
    }

    @Test("Denied and restricted calendar access require Settings redirect")
    func deniedAndRestrictedStatusesRequireSettingsRedirect() {
        #expect(makeService(status: .denied).requiresSettingsRedirect)
        #expect(makeService(status: .restricted).requiresSettingsRedirect)
    }

    @Test("Undetermined calendar access needs an explanation before prompting")
    func notDeterminedStatusNeedsExplanationBeforePrompt() {
        #expect(makeService(status: .notDetermined).needsExplanationBeforeRequest)
        #expect(makeService(status: .fullAccess).needsExplanationBeforeRequest == false)
    }

    @Test("Undetermined calendar access requests permission exactly once")
    func notDeterminedRequestsAccessOnce() async throws {
        let authorizer = FakeCalendarAccessAuthorizer(status: .notDetermined, requestResult: true)
        let service = makeService(authorizer: authorizer)

        try await service.requestAccessIfNeeded()

        #expect(authorizer.requestCount == 1)
    }

    @Test("Granted calendar access does not prompt again")
    func grantedStatusesDoNotReRequestAccess() async throws {
        let authorizedAuthorizer = FakeCalendarAccessAuthorizer(status: legacyAuthorizedStatus, requestResult: true)
        let authorizedService = makeService(authorizer: authorizedAuthorizer)

        try await authorizedService.requestAccessIfNeeded()
        #expect(authorizedAuthorizer.requestCount == 0)

        let fullAccessAuthorizer = FakeCalendarAccessAuthorizer(status: .fullAccess, requestResult: true)
        let fullAccessService = makeService(authorizer: fullAccessAuthorizer)

        try await fullAccessService.requestAccessIfNeeded()
        #expect(fullAccessAuthorizer.requestCount == 0)
    }

    private func makeService(
        status: EKAuthorizationStatus
    ) -> AppleCalendarService {
        makeService(authorizer: FakeCalendarAccessAuthorizer(status: status, requestResult: true))
    }

    private func makeService(
        authorizer: FakeCalendarAccessAuthorizer
    ) -> AppleCalendarService {
        AppleCalendarService(
            accessAuthorizer: authorizer,
            usageDescriptionProvider: { "todo.md needs calendar access for tests." }
        )
    }

    // Raw value 3 preserves the pre-iOS 17 granted state without pulling in the deprecated symbol.
    private var legacyAuthorizedStatus: EKAuthorizationStatus {
        EKAuthorizationStatus(rawValue: 3) ?? .denied
    }
}

@MainActor
private final class FakeCalendarAccessAuthorizer: CalendarAccessAuthorizing {
    var authorizationStatus: EKAuthorizationStatus
    var requestResult: Bool
    private(set) var requestCount = 0

    init(status: EKAuthorizationStatus, requestResult: Bool) {
        self.authorizationStatus = status
        self.requestResult = requestResult
    }

    func requestFullAccess() async throws -> Bool {
        requestCount += 1
        return requestResult
    }
}
