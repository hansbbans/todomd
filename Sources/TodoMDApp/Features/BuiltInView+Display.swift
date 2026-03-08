import Foundation

extension BuiltInView {
    var displayTitle: String {
        switch self {
        case .inbox:
            return "Inbox"
        case .myTasks:
            return "My Tasks"
        case .delegated:
            return "Delegated"
        case .today:
            return "Today"
        case .upcoming:
            return "Upcoming"
        case .logbook:
            return "Logbook"
        case .review:
            return "Review"
        case .anytime:
            return "Anytime"
        case .someday:
            return "Someday"
        case .flagged:
            return "Flagged"
        case .pomodoro:
            return "Pomodoro"
        }
    }

    var displaySystemImage: String {
        switch self {
        case .inbox:
            return "tray"
        case .myTasks:
            return "person"
        case .delegated:
            return "person.2"
        case .today:
            return "star"
        case .upcoming:
            return "calendar"
        case .logbook:
            return "checkmark.circle"
        case .review:
            return "checklist"
        case .anytime:
            return "list.bullet"
        case .someday:
            return "clock"
        case .flagged:
            return "flag"
        case .pomodoro:
            return "timer"
        }
    }
}
