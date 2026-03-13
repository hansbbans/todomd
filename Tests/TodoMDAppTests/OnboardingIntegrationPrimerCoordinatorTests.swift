import Testing
@testable import TodoMDApp

struct OnboardingIntegrationPrimerCoordinatorTests {
    @Test("Onboarding asks for reminders before calendar when both need explanation")
    func remindersComesBeforeCalendar() {
        let coordinator = OnboardingIntegrationPrimerCoordinator(
            remindersNeedsExplanation: true,
            calendarNeedsExplanation: true
        )

        #expect(coordinator.initialPrimer() == .reminders)
        #expect(coordinator.nextPrimer(after: .reminders) == .calendar)
        #expect(coordinator.nextPrimer(after: .calendar) == nil)
    }

    @Test("Onboarding skips straight to calendar when reminders already has access")
    func calendarPrimerCanBeFirst() {
        let coordinator = OnboardingIntegrationPrimerCoordinator(
            remindersNeedsExplanation: false,
            calendarNeedsExplanation: true
        )

        #expect(coordinator.initialPrimer() == .calendar)
        #expect(coordinator.nextPrimer(after: .calendar) == nil)
    }

    @Test("Onboarding finishes immediately when no integration primer is needed")
    func noPrimerNeeded() {
        let coordinator = OnboardingIntegrationPrimerCoordinator(
            remindersNeedsExplanation: false,
            calendarNeedsExplanation: false
        )

        #expect(coordinator.initialPrimer() == nil)
    }
}
