import Foundation

public enum PerspectiveField: String, Codable, CaseIterable, Sendable {
    case status
    case due
    case scheduled
    case `defer`
    case priority
    case flagged
    case area
    case project
    case tags
    case source
}

public enum PerspectiveOperator: String, Codable, CaseIterable, Sendable {
    case equals
    case contains
    case isSet
    case isNotSet
    case beforeToday
    case onToday
    case afterToday
    case isTrue
    case isFalse
}

public struct PerspectiveRule: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var field: PerspectiveField
    public var `operator`: PerspectiveOperator
    public var value: String

    public init(
        id: String = UUID().uuidString,
        field: PerspectiveField,
        operator: PerspectiveOperator,
        value: String = ""
    ) {
        self.id = id
        self.field = field
        self.operator = `operator`
        self.value = value
    }
}

public struct PerspectiveDefinition: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var allRules: [PerspectiveRule]
    public var anyRules: [PerspectiveRule]
    public var noneRules: [PerspectiveRule]

    public init(
        id: String = UUID().uuidString,
        name: String,
        allRules: [PerspectiveRule] = [],
        anyRules: [PerspectiveRule] = [],
        noneRules: [PerspectiveRule] = []
    ) {
        self.id = id
        self.name = name
        self.allRules = allRules
        self.anyRules = anyRules
        self.noneRules = noneRules
    }
}

public struct PerspectiveQueryEngine {
    public init() {}

    public func matches(_ record: TaskRecord, perspective: PerspectiveDefinition, today: LocalDate) -> Bool {
        let allMatch = perspective.allRules.allSatisfy { matchesRule(record, rule: $0, today: today) }
        let anyMatch = perspective.anyRules.isEmpty || perspective.anyRules.contains { matchesRule(record, rule: $0, today: today) }
        let noneMatch = perspective.noneRules.allSatisfy { !matchesRule(record, rule: $0, today: today) }
        return allMatch && anyMatch && noneMatch
    }

    public func matchesRule(_ record: TaskRecord, rule: PerspectiveRule, today: LocalDate) -> Bool {
        let frontmatter = record.document.frontmatter

        switch rule.field {
        case .status:
            return compareString(frontmatter.status.rawValue, rule: rule)

        case .priority:
            return compareString(frontmatter.priority.rawValue, rule: rule)

        case .area:
            return compareOptionalString(frontmatter.area, rule: rule)

        case .project:
            return compareOptionalString(frontmatter.project, rule: rule)

        case .source:
            return compareString(frontmatter.source, rule: rule)

        case .tags:
            return compareTags(frontmatter.tags, rule: rule)

        case .flagged:
            return compareBool(frontmatter.flagged, rule: rule)

        case .due:
            return compareDate(frontmatter.due, rule: rule, today: today)

        case .scheduled:
            return compareDate(frontmatter.scheduled, rule: rule, today: today)

        case .defer:
            return compareDate(frontmatter.defer, rule: rule, today: today)
        }
    }

    private func compareString(_ value: String, rule: PerspectiveRule) -> Bool {
        let lhs = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rhs = rule.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch rule.operator {
        case .equals:
            return !rhs.isEmpty && lhs == rhs
        case .contains:
            return !rhs.isEmpty && lhs.contains(rhs)
        case .isSet:
            return !lhs.isEmpty
        case .isNotSet:
            return lhs.isEmpty
        default:
            return false
        }
    }

    private func compareOptionalString(_ value: String?, rule: PerspectiveRule) -> Bool {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch rule.operator {
        case .isSet:
            return !(trimmed?.isEmpty ?? true)
        case .isNotSet:
            return trimmed?.isEmpty ?? true
        default:
            return compareString(trimmed ?? "", rule: rule)
        }
    }

    private func compareTags(_ tags: [String], rule: PerspectiveRule) -> Bool {
        let normalizedTags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let lookup = rule.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch rule.operator {
        case .equals:
            return !lookup.isEmpty && normalizedTags.contains(lookup)
        case .contains:
            return !lookup.isEmpty && normalizedTags.contains(where: { $0.contains(lookup) })
        case .isSet:
            return normalizedTags.contains(where: { !$0.isEmpty })
        case .isNotSet:
            return !normalizedTags.contains(where: { !$0.isEmpty })
        default:
            return false
        }
    }

    private func compareBool(_ value: Bool, rule: PerspectiveRule) -> Bool {
        switch rule.operator {
        case .isTrue:
            return value
        case .isFalse:
            return !value
        case .equals:
            let normalized = rule.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["1", "true", "yes", "flagged", "on"].contains(normalized) {
                return value
            }
            if ["0", "false", "no", "off"].contains(normalized) {
                return !value
            }
            return false
        default:
            return false
        }
    }

    private func compareDate(_ value: LocalDate?, rule: PerspectiveRule, today: LocalDate) -> Bool {
        switch rule.operator {
        case .isSet:
            return value != nil
        case .isNotSet:
            return value == nil
        case .beforeToday:
            guard let value else { return false }
            return value < today
        case .onToday:
            guard let value else { return false }
            return value == today
        case .afterToday:
            guard let value else { return false }
            return value > today
        case .equals:
            guard let value else { return false }
            guard let rhs = try? LocalDate(isoDate: rule.value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return false
            }
            return value == rhs
        default:
            return false
        }
    }
}
