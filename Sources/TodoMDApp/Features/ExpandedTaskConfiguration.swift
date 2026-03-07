import Foundation

enum ExpandedTaskQuickAction: String, CaseIterable, Identifiable {
    case today = "today"
    case calendar = "calendar"
    case priority = "priority"
    case tags = "tags"
    case more = "more"

    static let defaults: [ExpandedTaskQuickAction] = [.today, .calendar, .priority, .tags, .more]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            return "Today"
        case .calendar:
            return "Calendar"
        case .priority:
            return "Flag & Priority"
        case .tags:
            return "Tags"
        case .more:
            return "More"
        }
    }

    var systemImage: String {
        switch self {
        case .today:
            return "sun.max"
        case .calendar:
            return "calendar"
        case .priority:
            return "flag"
        case .tags:
            return "tag"
        case .more:
            return "ellipsis"
        }
    }
}

enum ExpandedTaskSettings {
    static let actionsKey = "settings_expanded_task_actions"

    static var defaultActionsRawValue: String {
        encodeActions(ExpandedTaskQuickAction.defaults)
    }

    static func decodeActions(_ rawValue: String) -> [ExpandedTaskQuickAction] {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ExpandedTaskQuickAction.defaults }

        let parsed = trimmed
            .split(separator: ",")
            .compactMap { ExpandedTaskQuickAction(rawValue: String($0)) }

        let deduplicated = parsed.reduce(into: [ExpandedTaskQuickAction]()) { result, action in
            if !result.contains(action) {
                result.append(action)
            }
        }

        guard !deduplicated.isEmpty else { return ExpandedTaskQuickAction.defaults }
        if deduplicated.contains(.more) {
            return deduplicated
        }
        return deduplicated + [.more]
    }

    static func encodeActions(_ actions: [ExpandedTaskQuickAction]) -> String {
        let normalized = decodeActions(actions.map(\.rawValue).joined(separator: ","))
        return normalized.map(\.rawValue).joined(separator: ",")
    }
}
