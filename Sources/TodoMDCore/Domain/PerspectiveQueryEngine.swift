import Foundation

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

public enum PerspectiveField: Hashable, Sendable, Codable, CaseIterable {
    case ref
    case status
    case assignee
    case completedBy
    case blockedBy
    case due
    case scheduled
    case `defer`
    case priority
    case flagged
    case area
    case project
    case tags
    case source
    case title
    case body
    case created
    case completed
    case modified
    case estimatedMinutes
    case recurrence
    case unknown(String)

    public static var allCases: [PerspectiveField] {
        [
            .ref, .status, .assignee, .completedBy, .blockedBy,
            .due, .scheduled, .defer, .priority, .flagged, .area, .project, .tags, .source,
            .title, .body, .created, .completed, .modified, .estimatedMinutes, .recurrence
        ]
    }

    public init(rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ref": self = .ref
        case "status": self = .status
        case "assignee": self = .assignee
        case "completed_by", "completedby": self = .completedBy
        case "blocked_by", "blockedby", "blocked": self = .blockedBy
        case "due": self = .due
        case "scheduled": self = .scheduled
        case "defer": self = .defer
        case "priority": self = .priority
        case "flagged": self = .flagged
        case "area": self = .area
        case "project": self = .project
        case "tags": self = .tags
        case "source": self = .source
        case "title": self = .title
        case "body": self = .body
        case "created": self = .created
        case "completed": self = .completed
        case "modified": self = .modified
        case "estimated_minutes", "estimatedminutes": self = .estimatedMinutes
        case "recurrence": self = .recurrence
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .ref: return "ref"
        case .status: return "status"
        case .assignee: return "assignee"
        case .completedBy: return "completed_by"
        case .blockedBy: return "blocked_by"
        case .due: return "due"
        case .scheduled: return "scheduled"
        case .defer: return "defer"
        case .priority: return "priority"
        case .flagged: return "flagged"
        case .area: return "area"
        case .project: return "project"
        case .tags: return "tags"
        case .source: return "source"
        case .title: return "title"
        case .body: return "body"
        case .created: return "created"
        case .completed: return "completed"
        case .modified: return "modified"
        case .estimatedMinutes: return "estimated_minutes"
        case .recurrence: return "recurrence"
        case .unknown(let value): return value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = PerspectiveField(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum PerspectiveOperator: Hashable, Sendable, Codable, CaseIterable {
    case equals
    case notEquals
    case `in`
    case contains
    case containsAny
    case containsAll
    case isSet
    case isNotSet
    case isNil
    case isNotNil
    case beforeToday
    case onToday
    case afterToday
    case before
    case after
    case on
    case onOrBefore
    case between
    case lessThan
    case greaterThan
    case stringContains
    case isTrue
    case isFalse
    case inPast
    case inNext
    case unknown(String)

    public static var allCases: [PerspectiveOperator] {
        [
            .equals, .notEquals, .in, .contains, .containsAny, .containsAll, .isSet, .isNotSet, .isNil, .isNotNil,
            .beforeToday, .onToday, .afterToday, .before, .after, .on, .onOrBefore, .between, .lessThan,
            .greaterThan, .stringContains, .isTrue, .isFalse, .inPast, .inNext
        ]
    }

    public init(rawValue: String) {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        switch normalized {
        case "equals": self = .equals
        case "not_equals", "notequals": self = .notEquals
        case "in": self = .in
        case "contains": self = .contains
        case "contains_any", "containsany": self = .containsAny
        case "contains_all", "containsall": self = .containsAll
        case "isset", "is_set": self = .isSet
        case "isnotset", "is_not_set": self = .isNotSet
        case "isnil", "is_nil": self = .isNil
        case "isnotnil", "is_not_nil": self = .isNotNil
        case "beforetoday", "before_today": self = .beforeToday
        case "ontoday", "on_today": self = .onToday
        case "aftertoday", "after_today": self = .afterToday
        case "before": self = .before
        case "after": self = .after
        case "on": self = .on
        case "onorbefore", "on_or_before": self = .onOrBefore
        case "between": self = .between
        case "lessthan", "less_than": self = .lessThan
        case "greaterthan", "greater_than": self = .greaterThan
        case "stringcontains", "string_contains": self = .stringContains
        case "istrue", "is_true": self = .isTrue
        case "isfalse", "is_false": self = .isFalse
        case "inpast", "in_past": self = .inPast
        case "innext", "in_next": self = .inNext
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .equals: return "equals"
        case .notEquals: return "not_equals"
        case .in: return "in"
        case .contains: return "contains"
        case .containsAny: return "contains_any"
        case .containsAll: return "contains_all"
        case .isSet: return "is_set"
        case .isNotSet: return "is_not_set"
        case .isNil: return "is_nil"
        case .isNotNil: return "is_not_nil"
        case .beforeToday: return "before_today"
        case .onToday: return "on_today"
        case .afterToday: return "after_today"
        case .before: return "before"
        case .after: return "after"
        case .on: return "on"
        case .onOrBefore: return "on_or_before"
        case .between: return "between"
        case .lessThan: return "less_than"
        case .greaterThan: return "greater_than"
        case .stringContains: return "string_contains"
        case .isTrue: return "is_true"
        case .isFalse: return "is_false"
        case .inPast: return "in_past"
        case .inNext: return "in_next"
        case .unknown(let value): return value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = PerspectiveOperator(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum PerspectiveLogicalOperator: Hashable, Sendable, Codable {
    case and
    case or
    case not
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "AND": self = .and
        case "OR": self = .or
        case "NOT": self = .not
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .and: return "AND"
        case .or: return "OR"
        case .not: return "NOT"
        case .unknown(let value): return value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = PerspectiveLogicalOperator(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct PerspectiveRule: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var field: PerspectiveField
    public var `operator`: PerspectiveOperator
    public var value: JSONValue?
    public var isEnabled: Bool
    public var unknown: [String: JSONValue]

    public init(
        id: String = UUID().uuidString,
        field: PerspectiveField,
        operator: PerspectiveOperator,
        value: String = "",
        isEnabled: Bool = true,
        unknown: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.field = field
        self.operator = `operator`
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        self.value = trimmed.isEmpty ? nil : .string(trimmed)
        self.isEnabled = isEnabled
        self.unknown = unknown
    }

    public init(
        id: String = UUID().uuidString,
        field: PerspectiveField,
        operator: PerspectiveOperator,
        jsonValue: JSONValue?,
        isEnabled: Bool = true,
        unknown: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.field = field
        self.operator = `operator`
        self.value = jsonValue
        self.isEnabled = isEnabled
        self.unknown = unknown
    }

    public var stringValue: String {
        get {
            switch value {
            case .string(let string):
                return string
            case .number(let number):
                if number.rounded(.towardZero) == number {
                    return String(Int(number))
                }
                return String(number)
            case .bool(let bool):
                return bool ? "true" : "false"
            case .array(let values):
                return values.compactMap(\.stringValue).joined(separator: ",")
            case .null, .none, .object:
                return ""
            }
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            value = trimmed.isEmpty ? nil : .string(trimmed)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let idKey = DynamicCodingKey(stringValue: "id")!
        let fieldKey = DynamicCodingKey(stringValue: "field")!
        let operatorKey = DynamicCodingKey(stringValue: "operator")!
        let opKey = DynamicCodingKey(stringValue: "op")!
        let valueKey = DynamicCodingKey(stringValue: "value")!
        let enabledKey = DynamicCodingKey(stringValue: "enabled")!
        let disabledKey = DynamicCodingKey(stringValue: "disabled")!

        self.id = try container.decodeIfPresent(String.self, forKey: idKey) ?? UUID().uuidString
        let decodedField = try container.decodeIfPresent(String.self, forKey: fieldKey) ?? "status"
        self.field = PerspectiveField(rawValue: decodedField)
        if let explicit = try container.decodeIfPresent(String.self, forKey: opKey) {
            self.operator = PerspectiveOperator(rawValue: explicit)
        } else {
            self.operator = PerspectiveOperator(rawValue: (try container.decodeIfPresent(String.self, forKey: operatorKey)) ?? "equals")
        }
        self.value = try container.decodeIfPresent(JSONValue.self, forKey: valueKey)
        if let enabled = try container.decodeIfPresent(Bool.self, forKey: enabledKey) {
            self.isEnabled = enabled
        } else if let disabled = try container.decodeIfPresent(Bool.self, forKey: disabledKey) {
            self.isEnabled = !disabled
        } else {
            self.isEnabled = true
        }

        let known = Set(["id", "field", "operator", "op", "value", "enabled", "disabled"])
        var unknown: [String: JSONValue] = [:]
        for key in container.allKeys where !known.contains(key.stringValue) {
            if let decoded = try container.decodeIfPresent(JSONValue.self, forKey: key) {
                unknown[key.stringValue] = decoded
            }
        }
        self.unknown = unknown
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(id, forKey: DynamicCodingKey(stringValue: "id")!)
        try container.encode(field.rawValue, forKey: DynamicCodingKey(stringValue: "field")!)
        try container.encode(`operator`.rawValue, forKey: DynamicCodingKey(stringValue: "op")!)
        try container.encodeIfPresent(value, forKey: DynamicCodingKey(stringValue: "value")!)
        if !isEnabled {
            try container.encode(false, forKey: DynamicCodingKey(stringValue: "enabled")!)
        }
        for (key, value) in unknown {
            try container.encode(value, forKey: DynamicCodingKey(stringValue: key)!)
        }
    }
}

public enum PerspectiveSortField: Hashable, Sendable, Codable {
    case due
    case scheduled
    case `defer`
    case priority
    case estimatedMinutes
    case title
    case created
    case modified
    case completed
    case flagged
    case manual
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "due": self = .due
        case "scheduled": self = .scheduled
        case "defer": self = .defer
        case "priority": self = .priority
        case "estimated_minutes", "estimatedminutes": self = .estimatedMinutes
        case "title": self = .title
        case "created": self = .created
        case "modified": self = .modified
        case "completed": self = .completed
        case "flagged": self = .flagged
        case "manual": self = .manual
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .due: return "due"
        case .scheduled: return "scheduled"
        case .defer: return "defer"
        case .priority: return "priority"
        case .estimatedMinutes: return "estimated_minutes"
        case .title: return "title"
        case .created: return "created"
        case .modified: return "modified"
        case .completed: return "completed"
        case .flagged: return "flagged"
        case .manual: return "manual"
        case .unknown(let value): return value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = PerspectiveSortField(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum PerspectiveSortDirection: String, Codable, Sendable {
    case asc
    case desc
}

public struct PerspectiveSort: Codable, Equatable, Sendable {
    public var field: PerspectiveSortField
    public var direction: PerspectiveSortDirection

    public init(field: PerspectiveSortField = .due, direction: PerspectiveSortDirection = .asc) {
        self.field = field
        self.direction = direction
    }
}

public enum PerspectiveGroupBy: Hashable, Sendable, Codable {
    case none
    case area
    case project
    case tag
    case tags
    case priority
    case due
    case scheduled
    case `defer`
    case flagged
    case source
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "none": self = .none
        case "area": self = .area
        case "project": self = .project
        case "tag": self = .tag
        case "tags": self = .tags
        case "priority": self = .priority
        case "due": self = .due
        case "scheduled": self = .scheduled
        case "defer": self = .defer
        case "flagged": self = .flagged
        case "source": self = .source
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .none: return "none"
        case .area: return "area"
        case .project: return "project"
        case .tag: return "tag"
        case .tags: return "tags"
        case .priority: return "priority"
        case .due: return "due"
        case .scheduled: return "scheduled"
        case .defer: return "defer"
        case .flagged: return "flagged"
        case .source: return "source"
        case .unknown(let value): return value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = PerspectiveGroupBy(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum PerspectiveLayout: Hashable, Sendable, Codable {
    case `default`
    case comfortable
    case compact
    case detailed
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "default": self = .default
        case "comfortable": self = .comfortable
        case "compact": self = .compact
        case "detailed": self = .detailed
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .default: return "default"
        case .comfortable: return "comfortable"
        case .compact: return "compact"
        case .detailed: return "detailed"
        case .unknown(let value): return value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = PerspectiveLayout(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct PerspectiveRuleGroup: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var `operator`: PerspectiveLogicalOperator
    public var conditions: [PerspectiveCondition]
    public var isEnabled: Bool
    public var unknown: [String: JSONValue]

    public init(
        id: String = UUID().uuidString,
        operator: PerspectiveLogicalOperator = .and,
        conditions: [PerspectiveCondition] = [],
        isEnabled: Bool = true,
        unknown: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.operator = `operator`
        self.conditions = conditions
        self.isEnabled = isEnabled
        self.unknown = unknown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let idKey = DynamicCodingKey(stringValue: "id")!
        let operatorKey = DynamicCodingKey(stringValue: "operator")!
        let conditionsKey = DynamicCodingKey(stringValue: "conditions")!
        let enabledKey = DynamicCodingKey(stringValue: "enabled")!
        let disabledKey = DynamicCodingKey(stringValue: "disabled")!

        id = try container.decodeIfPresent(String.self, forKey: idKey) ?? UUID().uuidString
        let rawOperator = try container.decodeIfPresent(String.self, forKey: operatorKey) ?? "AND"
        self.operator = PerspectiveLogicalOperator(rawValue: rawOperator)
        self.conditions = try container.decodeIfPresent([PerspectiveCondition].self, forKey: conditionsKey) ?? []
        if let enabled = try container.decodeIfPresent(Bool.self, forKey: enabledKey) {
            self.isEnabled = enabled
        } else if let disabled = try container.decodeIfPresent(Bool.self, forKey: disabledKey) {
            self.isEnabled = !disabled
        } else {
            self.isEnabled = true
        }

        let known = Set(["id", "operator", "conditions", "enabled", "disabled"])
        var unknown: [String: JSONValue] = [:]
        for key in container.allKeys where !known.contains(key.stringValue) {
            if let decoded = try container.decodeIfPresent(JSONValue.self, forKey: key) {
                unknown[key.stringValue] = decoded
            }
        }
        self.unknown = unknown
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(id, forKey: DynamicCodingKey(stringValue: "id")!)
        try container.encode(`operator`.rawValue, forKey: DynamicCodingKey(stringValue: "operator")!)
        try container.encode(conditions, forKey: DynamicCodingKey(stringValue: "conditions")!)
        if !isEnabled {
            try container.encode(false, forKey: DynamicCodingKey(stringValue: "enabled")!)
        }
        for (key, value) in unknown {
            try container.encode(value, forKey: DynamicCodingKey(stringValue: key)!)
        }
    }
}

public enum PerspectiveCondition: Codable, Equatable, Identifiable, Sendable {
    case rule(PerspectiveRule)
    case group(PerspectiveRuleGroup)

    public var id: String {
        switch self {
        case .rule(let rule):
            return rule.id
        case .group(let group):
            return group.id
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        if container.contains(DynamicCodingKey(stringValue: "conditions")!) {
            self = .group(try PerspectiveRuleGroup(from: decoder))
        } else {
            self = .rule(try PerspectiveRule(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .rule(let rule):
            try rule.encode(to: encoder)
        case .group(let group):
            try group.encode(to: encoder)
        }
    }
}

public struct PerspectiveDefinition: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var icon: String
    public var color: String?
    public var sort: PerspectiveSort
    public var groupBy: PerspectiveGroupBy
    public var layout: PerspectiveLayout
    public var manualOrder: [String]?
    public var allRules: [PerspectiveRule]
    public var anyRules: [PerspectiveRule]
    public var noneRules: [PerspectiveRule]
    public var rules: PerspectiveRuleGroup?
    public var sourceQuery: String?
    public var unknown: [String: JSONValue]

    public init(
        id: String = UUID().uuidString,
        name: String = "Untitled Perspective",
        icon: String = "list.bullet",
        color: String? = nil,
        sort: PerspectiveSort = PerspectiveSort(),
        groupBy: PerspectiveGroupBy = .none,
        layout: PerspectiveLayout = .default,
        manualOrder: [String]? = nil,
        allRules: [PerspectiveRule] = [PerspectiveRule(
            field: .status,
            operator: .in,
            jsonValue: .array([.string(TaskStatus.todo.rawValue), .string(TaskStatus.inProgress.rawValue)])
        )],
        anyRules: [PerspectiveRule] = [],
        noneRules: [PerspectiveRule] = [],
        rules: PerspectiveRuleGroup? = nil,
        sourceQuery: String? = nil,
        unknown: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.sort = sort
        self.groupBy = groupBy
        self.layout = layout
        self.manualOrder = manualOrder
        self.allRules = allRules
        self.anyRules = anyRules
        self.noneRules = noneRules
        self.rules = rules
        self.sourceQuery = sourceQuery
        self.unknown = unknown
    }

    public var effectiveRules: PerspectiveRuleGroup {
        rules ?? Self.makeLegacyRuleGroup(allRules: allRules, anyRules: anyRules, noneRules: noneRules)
    }

    private static func makeLegacyRuleGroup(
        allRules: [PerspectiveRule],
        anyRules: [PerspectiveRule],
        noneRules: [PerspectiveRule]
    ) -> PerspectiveRuleGroup {
        var conditions = allRules.map(PerspectiveCondition.rule)
        if !anyRules.isEmpty {
            conditions.append(.group(PerspectiveRuleGroup(
                operator: .or,
                conditions: anyRules.map(PerspectiveCondition.rule)
            )))
        }
        if !noneRules.isEmpty {
            conditions.append(.group(PerspectiveRuleGroup(
                operator: .not,
                conditions: noneRules.map(PerspectiveCondition.rule)
            )))
        }
        return PerspectiveRuleGroup(operator: .and, conditions: conditions)
    }

    private static func extractLegacyRules(from group: PerspectiveRuleGroup) -> (all: [PerspectiveRule], any: [PerspectiveRule], none: [PerspectiveRule]) {
        guard group.operator == .and else {
            return ([], [], [])
        }

        var allRules: [PerspectiveRule] = []
        var anyRules: [PerspectiveRule] = []
        var noneRules: [PerspectiveRule] = []

        for condition in group.conditions {
            switch condition {
            case .rule(let rule):
                allRules.append(rule)
            case .group(let subgroup):
                switch subgroup.operator {
                case .or:
                    let rules = subgroup.conditions.compactMap { condition -> PerspectiveRule? in
                        if case .rule(let rule) = condition { return rule }
                        return nil
                    }
                    if rules.count == subgroup.conditions.count {
                        anyRules.append(contentsOf: rules)
                    }
                case .not:
                    let rules = subgroup.conditions.compactMap { condition -> PerspectiveRule? in
                        if case .rule(let rule) = condition { return rule }
                        return nil
                    }
                    if rules.count == subgroup.conditions.count {
                        noneRules.append(contentsOf: rules)
                    }
                default:
                    break
                }
            }
        }

        return (allRules, anyRules, noneRules)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let idKey = DynamicCodingKey(stringValue: "id")!
        let nameKey = DynamicCodingKey(stringValue: "name")!
        let iconKey = DynamicCodingKey(stringValue: "icon")!
        let colorKey = DynamicCodingKey(stringValue: "color")!
        let sortKey = DynamicCodingKey(stringValue: "sort")!
        let groupByKey = DynamicCodingKey(stringValue: "group_by")!
        let groupByLegacyKey = DynamicCodingKey(stringValue: "groupBy")!
        let layoutKey = DynamicCodingKey(stringValue: "layout")!
        let manualOrderKey = DynamicCodingKey(stringValue: "manual_order")!
        let manualOrderLegacyKey = DynamicCodingKey(stringValue: "manualOrder")!
        let rulesKey = DynamicCodingKey(stringValue: "rules")!
        let allRulesKey = DynamicCodingKey(stringValue: "allRules")!
        let anyRulesKey = DynamicCodingKey(stringValue: "anyRules")!
        let noneRulesKey = DynamicCodingKey(stringValue: "noneRules")!
        let sourceQueryKey = DynamicCodingKey(stringValue: "source_query")!

        id = try container.decodeIfPresent(String.self, forKey: idKey) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: nameKey) ?? "Untitled Perspective"
        icon = try container.decodeIfPresent(String.self, forKey: iconKey) ?? "list.bullet"
        color = try container.decodeIfPresent(String.self, forKey: colorKey)
        sort = try container.decodeIfPresent(PerspectiveSort.self, forKey: sortKey) ?? PerspectiveSort()

        if let rawGroupBy = try container.decodeIfPresent(String.self, forKey: groupByKey) {
            groupBy = PerspectiveGroupBy(rawValue: rawGroupBy)
        } else if let rawGroupBy = try container.decodeIfPresent(String.self, forKey: groupByLegacyKey) {
            groupBy = PerspectiveGroupBy(rawValue: rawGroupBy)
        } else {
            groupBy = .none
        }

        if let rawLayout = try container.decodeIfPresent(String.self, forKey: layoutKey) {
            layout = PerspectiveLayout(rawValue: rawLayout)
        } else {
            layout = .default
        }

        manualOrder = try container.decodeIfPresent([String].self, forKey: manualOrderKey)
            ?? container.decodeIfPresent([String].self, forKey: manualOrderLegacyKey)

        if let decodedRules = try container.decodeIfPresent(PerspectiveRuleGroup.self, forKey: rulesKey) {
            rules = decodedRules
            let legacy = Self.extractLegacyRules(from: decodedRules)
            allRules = legacy.all
            anyRules = legacy.any
            noneRules = legacy.none
        } else {
            allRules = try container.decodeIfPresent([PerspectiveRule].self, forKey: allRulesKey) ?? []
            anyRules = try container.decodeIfPresent([PerspectiveRule].self, forKey: anyRulesKey) ?? []
            noneRules = try container.decodeIfPresent([PerspectiveRule].self, forKey: noneRulesKey) ?? []
            rules = nil
        }
        sourceQuery = try container.decodeIfPresent(String.self, forKey: sourceQueryKey)

        let known = Set([
            "id", "name", "icon", "color", "sort", "group_by", "groupBy", "layout", "manual_order", "manualOrder",
            "rules", "allRules", "anyRules", "noneRules", "source_query"
        ])
        var unknown: [String: JSONValue] = [:]
        for key in container.allKeys where !known.contains(key.stringValue) {
            if let decoded = try container.decodeIfPresent(JSONValue.self, forKey: key) {
                unknown[key.stringValue] = decoded
            }
        }
        self.unknown = unknown
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(id, forKey: DynamicCodingKey(stringValue: "id")!)
        try container.encode(name, forKey: DynamicCodingKey(stringValue: "name")!)
        try container.encode(icon, forKey: DynamicCodingKey(stringValue: "icon")!)
        try container.encodeIfPresent(color, forKey: DynamicCodingKey(stringValue: "color")!)
        try container.encode(sort, forKey: DynamicCodingKey(stringValue: "sort")!)
        try container.encode(groupBy.rawValue, forKey: DynamicCodingKey(stringValue: "group_by")!)
        try container.encode(layout.rawValue, forKey: DynamicCodingKey(stringValue: "layout")!)
        if let manualOrder {
            try container.encode(manualOrder, forKey: DynamicCodingKey(stringValue: "manual_order")!)
        } else {
            try container.encodeNil(forKey: DynamicCodingKey(stringValue: "manual_order")!)
        }
        try container.encode(effectiveRules, forKey: DynamicCodingKey(stringValue: "rules")!)
        try container.encodeIfPresent(sourceQuery, forKey: DynamicCodingKey(stringValue: "source_query")!)
        for (key, value) in unknown {
            try container.encode(value, forKey: DynamicCodingKey(stringValue: key)!)
        }
    }
}

public struct PerspectiveQueryEngine {
    public init() {}

    public func matches(_ record: TaskRecord, perspective: PerspectiveDefinition, today: LocalDate) -> Bool {
        // TODO: Use TaskMetadataIndex for pre-filtering here
        // Before evaluating the full rule group, check the metadata index for a fast answer:
        //   if let entry = index.entry(for: record.identity.path),
        //      let result = entry.matches(field: rule.field, operator: rule.operator, value: rule.stringValue) {
        //       return result  // skip full evaluation
        //   }
        evaluate(group: perspective.effectiveRules, record: record, today: today) ?? true
    }

    public func matchesRule(_ record: TaskRecord, rule: PerspectiveRule, today: LocalDate) -> Bool {
        evaluate(rule: rule, record: record, today: today) ?? false
    }

    private func evaluate(group: PerspectiveRuleGroup, record: TaskRecord, today: LocalDate) -> Bool? {
        guard group.isEnabled else { return true }
        let evaluations = group.conditions.map { evaluate(condition: $0, record: record, today: today) }

        switch group.operator {
        case .and:
            return evaluations.allSatisfy { $0 ?? true }
        case .or:
            if evaluations.isEmpty { return false }
            return evaluations.contains { $0 ?? false }
        case .not:
            return !evaluations.contains { $0 ?? false }
        case .unknown:
            return true
        }
    }

    private func evaluate(condition: PerspectiveCondition, record: TaskRecord, today: LocalDate) -> Bool? {
        switch condition {
        case .rule(let rule):
            return evaluate(rule: rule, record: record, today: today)
        case .group(let group):
            return evaluate(group: group, record: record, today: today)
        }
    }

    private func evaluate(rule: PerspectiveRule, record: TaskRecord, today: LocalDate) -> Bool? {
        // TODO: Use TaskMetadataIndex for pre-filtering here
        // When a TaskMetadataIndex is available, indexed fields can be evaluated without
        // touching the full frontmatter. Example integration:
        //   if let entry = index.entry(for: record.identity.path) {
        //       if let result = entry.matches(field: rule.field, operator: rule.operator,
        //                                     value: rule.stringValue) {
        //           return result
        //       }
        //   }
        // Fall through to full frontmatter evaluation for un-indexed fields.
        guard rule.isEnabled else { return true }
        let frontmatter = record.document.frontmatter

        switch rule.field {
        case .ref:
            return compareOptionalString(frontmatter.ref, rule: rule)
        case .status:
            return compareString(frontmatter.status.rawValue, rule: rule)
        case .assignee:
            return compareOptionalString(frontmatter.assignee, rule: rule)
        case .completedBy:
            return compareOptionalString(frontmatter.completedBy, rule: rule)
        case .blockedBy:
            return compareBlockedBy(frontmatter.blockedBy, rule: rule)
        case .priority:
            return compareString(frontmatter.priority.rawValue, rule: rule)
        case .area:
            return compareOptionalString(frontmatter.area, rule: rule)
        case .project:
            return compareOptionalString(frontmatter.project, rule: rule)
        case .source:
            return compareString(frontmatter.source, rule: rule)
        case .title:
            return compareString(frontmatter.title, rule: rule)
        case .body:
            return compareString(record.document.body, rule: rule)
        case .recurrence:
            return compareOptionalString(frontmatter.recurrence, rule: rule)
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
        case .created:
            return compareDate(localDate(from: frontmatter.created), rule: rule, today: today)
        case .completed:
            return compareDate(frontmatter.completed.flatMap(localDate(from:)), rule: rule, today: today)
        case .modified:
            return compareDate(frontmatter.modified.flatMap(localDate(from:)), rule: rule, today: today)
        case .estimatedMinutes:
            return compareNumber(frontmatter.estimatedMinutes, rule: rule)
        case .unknown:
            return nil
        }
    }

    private func compareBlockedBy(_ value: TaskBlockedBy?, rule: PerspectiveRule) -> Bool? {
        switch rule.operator {
        case .isSet, .isNotNil:
            return value != nil
        case .isNotSet, .isNil:
            return value == nil
        case .isTrue:
            return value != nil
        case .isFalse:
            return value == nil
        case .contains, .containsAny, .equals:
            guard case .refs(let refs) = value else { return false }
            let probes = Set(normalizedStrings(from: rule.value).map { $0.lowercased() })
            if probes.isEmpty { return false }
            return refs.contains { probes.contains($0.lowercased()) }
        case .containsAll:
            guard case .refs(let refs) = value else { return false }
            let probes = Set(normalizedStrings(from: rule.value).map { $0.lowercased() })
            if probes.isEmpty { return false }
            let refSet = Set(refs.map { $0.lowercased() })
            return probes.isSubset(of: refSet)
        default:
            return nil
        }
    }

    private func compareString(_ value: String, rule: PerspectiveRule) -> Bool? {
        let lhs = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rhs = normalizedStrings(from: rule.value)
        let first = rhs.first?.lowercased() ?? ""

        switch rule.operator {
        case .equals:
            return !first.isEmpty && lhs == first
        case .notEquals:
            return !first.isEmpty && lhs != first
        case .in:
            let set = Set(rhs.map { $0.lowercased() })
            return !set.isEmpty && set.contains(lhs)
        case .contains, .stringContains:
            return !first.isEmpty && lhs.localizedStandardContains(first)
        case .isSet, .isNotNil:
            return !lhs.isEmpty
        case .isNotSet, .isNil:
            return lhs.isEmpty
        default:
            return nil
        }
    }

    private func compareOptionalString(_ value: String?, rule: PerspectiveRule) -> Bool? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch rule.operator {
        case .isSet, .isNotNil:
            return !(trimmed?.isEmpty ?? true)
        case .isNotSet, .isNil:
            return trimmed?.isEmpty ?? true
        default:
            return compareString(trimmed ?? "", rule: rule)
        }
    }

    private func compareTags(_ tags: [String], rule: PerspectiveRule) -> Bool? {
        let normalizedTags = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let values = normalizedStrings(from: rule.value).map { $0.lowercased() }
        let lookup = values.first ?? ""

        switch rule.operator {
        case .equals:
            return !lookup.isEmpty && normalizedTags.contains(lookup)
        case .contains, .stringContains:
            return !lookup.isEmpty && normalizedTags.contains(where: { $0.contains(lookup) })
        case .containsAny, .in:
            let probes = Set(values)
            return !probes.isEmpty && normalizedTags.contains { probes.contains($0) }
        case .containsAll:
            let probes = Set(values)
            return !probes.isEmpty && probes.isSubset(of: Set(normalizedTags))
        case .isSet, .isNotNil:
            return !normalizedTags.isEmpty
        case .isNotSet, .isNil:
            return normalizedTags.isEmpty
        default:
            return nil
        }
    }

    private func compareBool(_ value: Bool, rule: PerspectiveRule) -> Bool? {
        switch rule.operator {
        case .isTrue:
            return value
        case .isFalse:
            return !value
        case .equals:
            guard let bool = coerceBool(rule.value) else { return false }
            return value == bool
        case .notEquals:
            guard let bool = coerceBool(rule.value) else { return false }
            return value != bool
        default:
            return nil
        }
    }

    private func compareNumber(_ value: Int?, rule: PerspectiveRule) -> Bool? {
        switch rule.operator {
        case .isSet, .isNotNil:
            return value != nil
        case .isNotSet, .isNil:
            return value == nil
        case .equals:
            guard let value else { return false }
            guard let probe = coerceInt(rule.value) else { return false }
            return value == probe
        case .lessThan:
            guard let value else { return false }
            guard let probe = coerceInt(rule.value) else { return false }
            return value < probe
        case .greaterThan:
            guard let value else { return false }
            guard let probe = coerceInt(rule.value) else { return false }
            return value > probe
        default:
            return nil
        }
    }

    private func compareDate(_ value: LocalDate?, rule: PerspectiveRule, today: LocalDate) -> Bool? {
        switch rule.operator {
        case .isSet, .isNotNil:
            return value != nil
        case .isNotSet, .isNil:
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
        case .equals, .on:
            guard let value else { return false }
            guard let probe = dateOperands(rule.value, today: today).single else { return false }
            return value == probe
        case .before:
            guard let value else { return false }
            guard let probe = dateOperands(rule.value, today: today).single else { return false }
            return value < probe
        case .after:
            guard let value else { return false }
            guard let probe = dateOperands(rule.value, today: today).single else { return false }
            return value > probe
        case .onOrBefore:
            guard let value else { return false }
            guard let probe = dateOperands(rule.value, today: today).single else { return false }
            return value <= probe
        case .between, .inPast, .inNext:
            guard let value else { return false }
            guard let range = dateOperands(rule.value, today: today).range else { return false }
            return value >= range.lowerBound && value <= range.upperBound
        default:
            return nil
        }
    }

    private func normalizedStrings(from value: JSONValue?) -> [String] {
        guard let value else { return [] }
        switch value {
        case .string(let string):
            if string.contains(",") {
                return string
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        case .number(let number):
            if number.rounded(.towardZero) == number {
                return [String(Int(number))]
            }
            return [String(number)]
        case .bool(let bool):
            return [bool ? "true" : "false"]
        case .array(let values):
            return values.flatMap(normalizedStrings(from:))
        case .null, .object:
            return []
        }
    }

    private func coerceInt(_ value: JSONValue?) -> Int? {
        guard let value else { return nil }
        switch value {
        case .number(let number):
            return Int(number)
        case .string(let string):
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private func coerceBool(_ value: JSONValue?) -> Bool? {
        guard let value else { return nil }
        switch value {
        case .bool(let bool):
            return bool
        case .string(let string):
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["1", "true", "yes", "flagged", "on"].contains(normalized) {
                return true
            }
            if ["0", "false", "no", "off"].contains(normalized) {
                return false
            }
            return nil
        default:
            return nil
        }
    }

    private func localDate(from date: Date) -> LocalDate? {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return nil
        }
        return try? LocalDate(year: year, month: month, day: day)
    }

    private struct DateOperands {
        var single: LocalDate?
        var range: ClosedRange<LocalDate>?
    }

    private func dateOperands(_ value: JSONValue?, today: LocalDate) -> DateOperands {
        guard let value else { return DateOperands(single: nil, range: nil) }

        switch value {
        case .string(let string):
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let date = try? LocalDate(isoDate: trimmed) {
                return DateOperands(single: date, range: date...date)
            }
            return dateOperands(fromRelativeToken: trimmed, today: today) ?? DateOperands(single: nil, range: nil)
        case .array(let values):
            let parsed = values.compactMap { element -> LocalDate? in
                if case .string(let raw) = element {
                    return try? LocalDate(isoDate: raw.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                return nil
            }
            guard parsed.count >= 2 else { return DateOperands(single: parsed.first, range: nil) }
            let lower = min(parsed[0], parsed[1])
            let upper = max(parsed[0], parsed[1])
            return DateOperands(single: parsed[0], range: lower...upper)
        case .object(let object):
            if let relative = dateOperands(fromRelativeObject: object, today: today) {
                return relative
            }
            let from = (object["from"]?.stringValue ?? object["start"]?.stringValue).flatMap { try? LocalDate(isoDate: $0) }
            let to = (object["to"]?.stringValue ?? object["end"]?.stringValue).flatMap { try? LocalDate(isoDate: $0) }
            if let from, let to {
                let lower = min(from, to)
                let upper = max(from, to)
                return DateOperands(single: from, range: lower...upper)
            }
            if let from {
                return DateOperands(single: from, range: from...from)
            }
            return DateOperands(single: nil, range: nil)
        case .number, .bool, .null:
            return DateOperands(single: nil, range: nil)
        }
    }

    private func dateOperands(fromRelativeToken token: String, today: LocalDate) -> DateOperands? {
        switch token.lowercased() {
        case "today":
            return DateOperands(single: today, range: today...today)
        case "yesterday":
            guard let date = adding(days: -1, to: today) else { return nil }
            return DateOperands(single: date, range: date...date)
        case "tomorrow":
            guard let date = adding(days: 1, to: today) else { return nil }
            return DateOperands(single: date, range: date...date)
        default:
            return nil
        }
    }

    private func dateOperands(fromRelativeObject object: [String: JSONValue], today: LocalDate) -> DateOperands? {
        guard let op = object["op"]?.stringValue?.lowercased() else { return nil }
        switch op {
        case "today":
            return DateOperands(single: today, range: today...today)
        case "yesterday":
            guard let date = adding(days: -1, to: today) else { return nil }
            return DateOperands(single: date, range: date...date)
        case "tomorrow":
            guard let date = adding(days: 1, to: today) else { return nil }
            return DateOperands(single: date, range: date...date)
        case "in_next":
            guard let value = coerceInt(object["value"]),
                  let unit = object["unit"]?.stringValue else { return nil }
            guard let end = adding(componentUnit: unit, value: value, to: today) else { return nil }
            let lower = min(today, end)
            let upper = max(today, end)
            return DateOperands(single: today, range: lower...upper)
        case "in_past":
            guard let value = coerceInt(object["value"]),
                  let unit = object["unit"]?.stringValue else { return nil }
            guard let start = adding(componentUnit: unit, value: -value, to: today) else { return nil }
            let lower = min(today, start)
            let upper = max(today, start)
            return DateOperands(single: today, range: lower...upper)
        default:
            return nil
        }
    }

    private func adding(days: Int, to date: LocalDate) -> LocalDate? {
        adding(componentUnit: "days", value: days, to: date)
    }

    private func adding(componentUnit unit: String, value: Int, to date: LocalDate) -> LocalDate? {
        var components = DateComponents()
        components.year = date.year
        components.month = date.month
        components.day = date.day
        guard let baseDate = Calendar.current.date(from: components) else { return nil }

        let component: Calendar.Component
        switch unit.lowercased() {
        case "day", "days":
            component = .day
        case "week", "weeks":
            component = .weekOfYear
        case "month", "months":
            component = .month
        default:
            return nil
        }

        guard let shifted = Calendar.current.date(byAdding: component, value: value, to: baseDate) else { return nil }
        let shiftedComponents = Calendar.current.dateComponents([.year, .month, .day], from: shifted)
        guard let year = shiftedComponents.year,
              let month = shiftedComponents.month,
              let day = shiftedComponents.day else {
            return nil
        }
        return try? LocalDate(year: year, month: month, day: day)
    }
}
