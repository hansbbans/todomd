import Foundation

enum QuickEntryField: String, CaseIterable, Identifiable {
    case dueDate = "due_date"
    case priority = "priority"
    case reminder = "reminder"
    case flag = "flag"
    case tags = "tags"
    case project = "project"

    static let defaults: [QuickEntryField] = [.dueDate, .priority, .reminder]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dueDate:
            return "Date"
        case .priority:
            return "Priority"
        case .reminder:
            return "Reminders"
        case .flag:
            return "Flag"
        case .tags:
            return "Tags"
        case .project:
            return "Project"
        }
    }

    var systemImage: String {
        switch self {
        case .dueDate:
            return "calendar"
        case .priority:
            return "flag"
        case .reminder:
            return "alarm"
        case .flag:
            return "flag.fill"
        case .tags:
            return "tag"
        case .project:
            return "tray"
        }
    }
}

enum QuickEntryDefaultDateMode: String, CaseIterable, Identifiable {
    case today
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            return "Today"
        case .none:
            return "No date"
        }
    }
}

enum QuickEntrySettings {
    static let fieldsKey = "settings_quick_entry_fields"
    static let defaultDateModeKey = "settings_quick_entry_default_due_date"

    static var defaultFieldsRawValue: String {
        encodeFields(QuickEntryField.defaults)
    }

    static func decodeFields(_ rawValue: String) -> [QuickEntryField] {
        if rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }
        let parsed = rawValue
            .split(separator: ",")
            .compactMap { QuickEntryField(rawValue: String($0)) }
        let deduplicated = parsed.reduce(into: [QuickEntryField]()) { result, field in
            if !result.contains(field) {
                result.append(field)
            }
        }
        return deduplicated.isEmpty ? QuickEntryField.defaults : deduplicated
    }

    static func encodeFields(_ fields: [QuickEntryField]) -> String {
        fields.map(\.rawValue).joined(separator: ",")
    }
}
