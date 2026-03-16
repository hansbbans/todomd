import Foundation
import Testing
@testable import TodoMDCore

struct NaturalLanguageDateCase: Sendable {
    let phrase: String
    let referenceISO8601: String
    let expectedISODate: String
}

struct NaturalLanguageTaskCase: Sendable {
    let input: String
    let referenceISO8601: String
    let availableProjects: [String]
    let expectedTitle: String
    let expectedDueISODate: String?
    let expectedDueTimeISO: String?
    let expectedProject: String?
    let expectedTags: [String]
    let expectedRecognizedDatePhrase: String?
}

struct PerspectiveRuleExpectation: Sendable {
    let field: PerspectiveField
    let `operator`: PerspectiveOperator
    let stringValue: String?

    init(
        field: PerspectiveField,
        operator: PerspectiveOperator,
        stringValue: String? = nil
    ) {
        self.field = field
        self.operator = `operator`
        self.stringValue = stringValue
    }
}

struct NaturalLanguagePerspectiveCase: Sendable {
    let query: String
    let referenceISO8601: String
    let expectedTopLevelOperator: PerspectiveLogicalOperator
    let expectedRules: [PerspectiveRuleExpectation]
    let expectedNestedOperators: [PerspectiveLogicalOperator]
    let expectedConfidence: Double
    let expectedCloudFallback: Bool
}

private let hardeningDateCases: [NaturalLanguageDateCase] = [
    .init(phrase: "today", referenceISO8601: "2026-03-03T12:00:00Z", expectedISODate: "2026-03-03"),
    .init(phrase: "tomorrow", referenceISO8601: "2026-03-03T12:00:00Z", expectedISODate: "2026-03-04"),
    .init(phrase: "yesterday", referenceISO8601: "2026-03-03T12:00:00Z", expectedISODate: "2026-03-02"),
    .init(phrase: "next friday", referenceISO8601: "2026-02-28T12:00:00Z", expectedISODate: "2026-03-06"),
    .init(phrase: "upcoming wed", referenceISO8601: "2026-02-28T12:00:00Z", expectedISODate: "2026-03-04"),
    .init(phrase: "this friday", referenceISO8601: "2026-03-02T12:00:00Z", expectedISODate: "2026-03-06"),
    .init(phrase: "this upcoming friday", referenceISO8601: "2026-02-28T12:00:00Z", expectedISODate: "2026-03-06"),
    .init(phrase: "in 10 days", referenceISO8601: "2026-03-03T12:00:00Z", expectedISODate: "2026-03-13"),
    .init(phrase: "march 14", referenceISO8601: "2026-03-01T12:00:00Z", expectedISODate: "2026-03-14")
]

private let hardeningTaskCases: [NaturalLanguageTaskCase] = [
    .init(
        input: "pay rent by tomorrow #finance #home",
        referenceISO8601: "2026-03-03T12:00:00Z",
        availableProjects: [],
        expectedTitle: "pay rent",
        expectedDueISODate: "2026-03-04",
        expectedDueTimeISO: nil,
        expectedProject: nil,
        expectedTags: ["finance", "home"],
        expectedRecognizedDatePhrase: "by tomorrow"
    ),
    .init(
        input: "call daycare next wed",
        referenceISO8601: "2026-02-28T12:00:00Z",
        availableProjects: [],
        expectedTitle: "call daycare",
        expectedDueISODate: "2026-03-04",
        expectedDueTimeISO: nil,
        expectedProject: nil,
        expectedTags: [],
        expectedRecognizedDatePhrase: "next wed"
    ),
    .init(
        input: "join standup tomorrow at 3:15pm",
        referenceISO8601: "2026-03-03T12:00:00Z",
        availableProjects: [],
        expectedTitle: "join standup",
        expectedDueISODate: "2026-03-04",
        expectedDueTimeISO: "15:15",
        expectedProject: nil,
        expectedTags: [],
        expectedRecognizedDatePhrase: "tomorrow at 3:15pm"
    ),
    .init(
        input: "finish draft due by upcoming friday",
        referenceISO8601: "2026-02-28T12:00:00Z",
        availableProjects: [],
        expectedTitle: "finish draft",
        expectedDueISODate: "2026-03-06",
        expectedDueTimeISO: nil,
        expectedProject: nil,
        expectedTags: [],
        expectedRecognizedDatePhrase: "due by upcoming friday"
    ),
    .init(
        input: "review plan due on march 4",
        referenceISO8601: "2026-03-01T12:00:00Z",
        availableProjects: [],
        expectedTitle: "review plan",
        expectedDueISODate: "2026-03-04",
        expectedDueTimeISO: nil,
        expectedProject: nil,
        expectedTags: [],
        expectedRecognizedDatePhrase: "due on march 4"
    ),
    .init(
        input: "deploy release due on friday at 15:30",
        referenceISO8601: "2026-03-02T12:00:00Z",
        availableProjects: [],
        expectedTitle: "deploy release",
        expectedDueISODate: "2026-03-06",
        expectedDueTimeISO: "15:30",
        expectedProject: nil,
        expectedTags: [],
        expectedRecognizedDatePhrase: "due on friday at 15:30"
    ),
    .init(
        input: "submit brief in Launch Plan tomorrow",
        referenceISO8601: "2026-03-03T12:00:00Z",
        availableProjects: ["Launch Plan", "Errands"],
        expectedTitle: "submit brief",
        expectedDueISODate: "2026-03-04",
        expectedDueTimeISO: nil,
        expectedProject: "Launch Plan",
        expectedTags: [],
        expectedRecognizedDatePhrase: "tomorrow"
    ),
    .init(
        input: "prep slides project Launch Plan next friday #work",
        referenceISO8601: "2026-02-28T12:00:00Z",
        availableProjects: ["Launch Plan", "Errands"],
        expectedTitle: "prep slides",
        expectedDueISODate: "2026-03-06",
        expectedDueTimeISO: nil,
        expectedProject: "Launch Plan",
        expectedTags: ["work"],
        expectedRecognizedDatePhrase: "next friday"
    ),
    .init(
        input: "grocery run under Errands march 4",
        referenceISO8601: "2026-03-01T12:00:00Z",
        availableProjects: ["Launch Plan", "Errands"],
        expectedTitle: "grocery run",
        expectedDueISODate: "2026-03-04",
        expectedDueTimeISO: nil,
        expectedProject: "Errands",
        expectedTags: [],
        expectedRecognizedDatePhrase: "march 4"
    ),
    .init(
        input: "call mom at noon tomorrow",
        referenceISO8601: "2026-03-03T12:00:00Z",
        availableProjects: [],
        expectedTitle: "call mom",
        expectedDueISODate: "2026-03-04",
        expectedDueTimeISO: "12:00",
        expectedProject: nil,
        expectedTags: [],
        expectedRecognizedDatePhrase: "at noon tomorrow"
    )
]

private let hardeningPerspectiveCases: [NaturalLanguagePerspectiveCase] = [
    .init(
        query: "in project TL due this upcoming Friday",
        referenceISO8601: "2026-02-28T12:00:00Z",
        expectedTopLevelOperator: .and,
        expectedRules: [
            .init(field: .project, operator: .equals, stringValue: "Tl"),
            .init(field: .due, operator: .on, stringValue: "2026-03-06")
        ],
        expectedNestedOperators: [],
        expectedConfidence: 1,
        expectedCloudFallback: false
    ),
    .init(
        query: "in project TL due by upcoming Friday",
        referenceISO8601: "2026-02-28T12:00:00Z",
        expectedTopLevelOperator: .and,
        expectedRules: [
            .init(field: .project, operator: .equals, stringValue: "Tl"),
            .init(field: .due, operator: .onOrBefore, stringValue: "2026-03-06")
        ],
        expectedNestedOperators: [],
        expectedConfidence: 1,
        expectedCloudFallback: false
    ),
    .init(
        query: "anything in project TL due upcoming Friday or earlier that are not done",
        referenceISO8601: "2026-02-28T12:00:00Z",
        expectedTopLevelOperator: .and,
        expectedRules: [
            .init(field: .project, operator: .equals, stringValue: "Tl"),
            .init(field: .due, operator: .onOrBefore, stringValue: "2026-03-06"),
            .init(field: .status, operator: .notEquals, stringValue: TaskStatus.done.rawValue)
        ],
        expectedNestedOperators: [],
        expectedConfidence: 1,
        expectedCloudFallback: false
    ),
    .init(
        query: "high priority work tasks due this week",
        referenceISO8601: "2026-02-28T12:00:00Z",
        expectedTopLevelOperator: .and,
        expectedRules: [
            .init(field: .priority, operator: .equals, stringValue: "high"),
            .init(field: .area, operator: .equals, stringValue: "Work"),
            .init(field: .due, operator: .inNext)
        ],
        expectedNestedOperators: [],
        expectedConfidence: 1,
        expectedCloudFallback: false
    ),
    .init(
        query: "blocked tasks",
        referenceISO8601: "2026-02-28T12:00:00Z",
        expectedTopLevelOperator: .and,
        expectedRules: [
            .init(field: .blockedBy, operator: .isNotNil)
        ],
        expectedNestedOperators: [],
        expectedConfidence: 1,
        expectedCloudFallback: false
    ),
    .init(
        query: "available tasks assigned to me",
        referenceISO8601: "2026-02-28T12:00:00Z",
        expectedTopLevelOperator: .and,
        expectedRules: [
            .init(field: .blockedBy, operator: .isNil),
            .init(field: .defer, operator: .onOrBefore),
            .init(field: .status, operator: .in, stringValue: "todo,in-progress"),
            .init(field: .assignee, operator: .isNil),
            .init(field: .assignee, operator: .equals, stringValue: "user")
        ],
        expectedNestedOperators: [.or],
        expectedConfidence: 1,
        expectedCloudFallback: false
    ),
    .init(
        query: "completed this week from voice-ramble",
        referenceISO8601: "2026-02-28T12:00:00Z",
        expectedTopLevelOperator: .and,
        expectedRules: [
            .init(field: .status, operator: .equals, stringValue: TaskStatus.done.rawValue),
            .init(field: .completed, operator: .inPast),
            .init(field: .source, operator: .equals, stringValue: "voice-ramble")
        ],
        expectedNestedOperators: [],
        expectedConfidence: 1,
        expectedCloudFallback: false
    ),
    .init(
        query: "tagged calls under 15 minutes",
        referenceISO8601: "2026-02-28T12:00:00Z",
        expectedTopLevelOperator: .and,
        expectedRules: [
            .init(field: .tags, operator: .contains, stringValue: "calls"),
            .init(field: .estimatedMinutes, operator: .lessThan, stringValue: "15")
        ],
        expectedNestedOperators: [],
        expectedConfidence: 1,
        expectedCloudFallback: false
    ),
    .init(
        query: "delegated flagged tasks",
        referenceISO8601: "2026-02-28T12:00:00Z",
        expectedTopLevelOperator: .and,
        expectedRules: [
            .init(field: .flagged, operator: .isTrue),
            .init(field: .assignee, operator: .isNotNil),
            .init(field: .assignee, operator: .notEquals, stringValue: "user")
        ],
        expectedNestedOperators: [],
        expectedConfidence: 1,
        expectedCloudFallback: false
    ),
    .init(
        query: "in projects Home and Work",
        referenceISO8601: "2026-02-28T12:00:00Z",
        expectedTopLevelOperator: .and,
        expectedRules: [
            .init(field: .project, operator: .equals, stringValue: "Home"),
            .init(field: .project, operator: .equals, stringValue: "Work")
        ],
        expectedNestedOperators: [.or],
        expectedConfidence: 1,
        expectedCloudFallback: false
    )
]

private func hardeningCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar
}

private func referenceDate(_ iso8601: String) -> Date? {
    ISO8601DateFormatter().date(from: iso8601)
}

private func flattenedRules(_ group: PerspectiveRuleGroup) -> [PerspectiveRule] {
    group.conditions.flatMap { condition -> [PerspectiveRule] in
        switch condition {
        case .rule(let rule):
            return [rule]
        case .group(let subgroup):
            return flattenedRules(subgroup)
        }
    }
}

private func containsGroup(_ group: PerspectiveRuleGroup, op: PerspectiveLogicalOperator) -> Bool {
    group.conditions.contains { condition in
        guard case .group(let subgroup) = condition else { return false }
        return subgroup.operator == op || containsGroup(subgroup, op: op)
    }
}

private func matches(_ rule: PerspectiveRule, expected: PerspectiveRuleExpectation) -> Bool {
    guard rule.field == expected.field, rule.operator == expected.operator else { return false }
    guard let stringValue = expected.stringValue else { return true }
    return rule.stringValue == stringValue
}

struct NaturalLanguageParserHardeningTests {
    @Test("Date parser handles a broad matrix of common phrases", arguments: hardeningDateCases)
    func dateParserMatrix(testCase: NaturalLanguageDateCase) throws {
        let parser = NaturalLanguageDateParser(calendar: hardeningCalendar())
        let reference = try #require(referenceDate(testCase.referenceISO8601))

        #expect(parser.parse(testCase.phrase, relativeTo: reference)?.isoString == testCase.expectedISODate)
    }

    @Test("Task parser handles a broad matrix of quick-entry inputs", arguments: hardeningTaskCases)
    func taskParserMatrix(testCase: NaturalLanguageTaskCase) throws {
        let parser = NaturalLanguageTaskParser(
            calendar: hardeningCalendar(),
            availableProjects: testCase.availableProjects
        )
        let reference = try #require(referenceDate(testCase.referenceISO8601))
        let result = try #require(parser.parse(testCase.input, relativeTo: reference))

        #expect(result.title == testCase.expectedTitle)
        #expect(result.due?.isoString == testCase.expectedDueISODate)
        #expect(result.dueTime?.isoString == testCase.expectedDueTimeISO)
        #expect(result.project == testCase.expectedProject)
        #expect(result.tags == testCase.expectedTags)
        #expect(result.recognizedDatePhrase == testCase.expectedRecognizedDatePhrase)
    }

    @Test("Perspective parser handles a broad matrix of natural-language queries", arguments: hardeningPerspectiveCases)
    func perspectiveParserMatrix(testCase: NaturalLanguagePerspectiveCase) throws {
        let parser = NaturalLanguagePerspectiveParser(calendar: hardeningCalendar())
        let reference = try #require(referenceDate(testCase.referenceISO8601))
        let result = parser.parse(testCase.query, relativeTo: reference)
        let rules = flattenedRules(result.rules)

        #expect(result.rules.operator == testCase.expectedTopLevelOperator)
        #expect(result.confidence == testCase.expectedConfidence)
        #expect(result.requiresCloudFallback == testCase.expectedCloudFallback)

        for expectedRule in testCase.expectedRules {
            #expect(rules.contains(where: { matches($0, expected: expectedRule) }))
        }

        for nestedOperator in testCase.expectedNestedOperators {
            #expect(containsGroup(result.rules, op: nestedOperator))
        }
    }
}
