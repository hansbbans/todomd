import Foundation

enum OnboardingIntegrationPrimer: String, Identifiable {
    case reminders
    case calendar

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .reminders:
            "Allow Reminders Access"
        case .calendar:
            "Allow Calendar Access"
        }
    }

    var message: String {
        switch self {
        case .reminders:
            "Allow Reminders access to import tasks from Reminders."
        case .calendar:
            "Allow Calendar access to show calendar events alongside your tasks."
        }
    }

    var settingsKey: String {
        switch self {
        case .reminders:
            "settings_reminders_import_enabled"
        case .calendar:
            "settings_google_calendar_enabled"
        }
    }
}

struct OnboardingIntegrationPrimerCoordinator {
    let remindersNeedsExplanation: Bool
    let calendarNeedsExplanation: Bool

    func initialPrimer() -> OnboardingIntegrationPrimer? {
        if remindersNeedsExplanation {
            return .reminders
        }
        if calendarNeedsExplanation {
            return .calendar
        }
        return nil
    }

    func nextPrimer(after primer: OnboardingIntegrationPrimer) -> OnboardingIntegrationPrimer? {
        switch primer {
        case .reminders:
            return calendarNeedsExplanation ? .calendar : nil
        case .calendar:
            return nil
        }
    }
}
