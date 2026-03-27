import Testing
import CoreGraphics
@testable import TodoMDApp

struct CompactTabSelectionPolicyTests {
    private let policy = CompactTabSelectionPolicy(
        primaryView: .custom("perspective:focus"),
        secondaryView: .project("Work")
    )

    @Test("Browse tab reselect returns to Browse root from browse destinations")
    func browseTabReselectReturnsBrowseRoot() {
        #expect(policy.reselectionTarget(for: .areas, currentView: .project("Errands")) == .browse)
        #expect(policy.reselectionTarget(for: .areas, currentView: .builtIn(.myTasks)) == .browse)
        #expect(policy.reselectionTarget(for: .areas, currentView: .tag("home")) == .browse)
    }

    @Test("Browse tab reselect stays put when already at Browse root")
    func browseTabReselectDoesNothingAtBrowseRoot() {
        #expect(policy.reselectionTarget(for: .areas, currentView: .browse) == nil)
    }

    @Test("Switching to Browse tab from another tab opens Browse root")
    func switchingToBrowseTabUsesBrowseRoot() {
        #expect(policy.rootView(for: .areas, currentView: .builtIn(.inbox)) == .browse)
        #expect(policy.rootView(for: .areas, currentView: .custom("perspective:focus")) == .browse)
    }
}

struct RootPullToSearchFeedbackPolicyTests {
    private let policy = RootPullToSearchFeedbackPolicy()

    @Test("Pull-to-search stays hidden until the reveal distance is reached")
    func staysHiddenBeforeRevealDistance() {
        #expect(
            policy.phase(
                isEnabled: true,
                dragStartedAtTop: true,
                translation: CGSize(width: 0, height: 20)
            ) == .hidden
        )
    }

    @Test("Pull-to-search becomes visible before it is armed")
    func becomesVisibleBeforeActivation() {
        #expect(
            policy.phase(
                isEnabled: true,
                dragStartedAtTop: true,
                translation: CGSize(width: 0, height: 48)
            ) == .visible
        )
    }

    @Test("Pull-to-search arms and triggers only after a valid threshold-crossing drag")
    func armsAndTriggersPastActivationDistance() {
        let translation = CGSize(width: 18, height: 112)

        #expect(
            policy.phase(
                isEnabled: true,
                dragStartedAtTop: true,
                translation: translation
            ) == .armed
        )
        #expect(
            policy.shouldTrigger(
                isEnabled: true,
                dragStartedAtTop: true,
                translation: translation
            )
        )
    }

    @Test("Pull-to-search ignores drags that start away from the top or drift too far horizontally")
    func ignoresInvalidDrags() {
        #expect(
            policy.phase(
                isEnabled: true,
                dragStartedAtTop: false,
                translation: CGSize(width: 0, height: 120)
            ) == .hidden
        )
        #expect(
            !policy.shouldTrigger(
                isEnabled: true,
                dragStartedAtTop: true,
                translation: CGSize(width: 180, height: 120)
            )
        )
    }
}
