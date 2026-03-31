import XCTest
@testable import TodoMDCore

final class NaturalLanguagePerspectiveParserTests: XCTestCase {
    private let parser = NaturalLanguagePerspectiveParser(calendar: Calendar(identifier: .gregorian))
    private let referenceDate = ISO8601DateFormatter().date(from: "2026-02-28T12:00:00Z")!

    func testDueTodayParsesToDueOnTodayRule() {
        let result = parser.parse("due today", relativeTo: referenceDate)
        let rules = flattenedRules(result.rules)

        XCTAssertTrue(rules.contains { $0.field == .due && $0.operator == .onToday })
        XCTAssertEqual(result.confidence, 1)
        XCTAssertFalse(result.requiresCloudFallback)
    }

    func testOverdueParsesToDueBeforeToday() {
        let result = parser.parse("overdue items", relativeTo: referenceDate)
        let rules = flattenedRules(result.rules)

        XCTAssertTrue(rules.contains { $0.field == .due && $0.operator == .before && $0.stringValue == "today" })
    }

    func testDueTodayOrOverdueBuildsOrGroup() {
        let result = parser.parse("all items due today or overdue", relativeTo: referenceDate)
        XCTAssertEqual(result.rules.operator, .or)
        XCTAssertEqual(result.rules.conditions.count, 2)
    }

    func testProjectListParsesAsOrRules() {
        let result = parser.parse("in projects B and C", relativeTo: referenceDate)
        let orGroups = result.rules.conditions.compactMap { condition -> PerspectiveRuleGroup? in
            if case .group(let group) = condition, group.operator == .or {
                return group
            }
            return nil
        }

        XCTAssertEqual(orGroups.count, 1)
        let projectRules = flattenedRules(orGroups[0]).filter { $0.field == .project && $0.operator == .equals }
        XCTAssertEqual(Set(projectRules.map(\.stringValue)), Set(["B", "C"]))
    }

    func testExceptCreatesNotGroup() {
        let result = parser.parse("work tasks except completed", relativeTo: referenceDate)
        let hasNot = containsGroup(result.rules, op: .not)
        XCTAssertTrue(hasNot)
    }

    func testImplicitAndRecognizesMultipleQualifiers() {
        let result = parser.parse("high priority work tasks due this week", relativeTo: referenceDate)
        let rules = flattenedRules(result.rules)

        XCTAssertTrue(rules.contains { $0.field == .priority && $0.operator == .equals && $0.stringValue == "high" })
        XCTAssertTrue(rules.contains { $0.field == .area && $0.operator == .equals && $0.stringValue == "Work" })
        XCTAssertTrue(rules.contains { $0.field == .due && $0.operator == .inNext })
    }

    func testBlockedAndAvailableRulesParse() {
        let blocked = parser.parse("blocked tasks", relativeTo: referenceDate)
        XCTAssertTrue(flattenedRules(blocked.rules).contains { $0.field == .blockedBy && $0.operator == .isNotNil })

        let available = parser.parse("available tasks", relativeTo: referenceDate)
        let availableRules = flattenedRules(available.rules)
        XCTAssertTrue(availableRules.contains { $0.field == .blockedBy && $0.operator == .isNil })
        XCTAssertTrue(availableRules.contains { $0.field == .status && $0.operator == .in })
    }

    func testUnknownQueryRequestsFallback() {
        let result = parser.parse("asdfghjkl", relativeTo: referenceDate)
        XCTAssertLessThan(result.confidence, 0.5)
        XCTAssertTrue(result.requiresCloudFallback)
    }

    func testEverythingYieldsEmptyRules() {
        let result = parser.parse("everything", relativeTo: referenceDate)
        XCTAssertTrue(result.rules.conditions.isEmpty)
        XCTAssertEqual(result.summary, "Showing all tasks.")
        XCTAssertFalse(result.requiresCloudFallback)
    }

    func testDueUpcomingFridayOrEarlierStaysSingleConjunction() {
        let result = parser.parse(
            "anything in project TL due upcoming Friday or earlier that are not done",
            relativeTo: referenceDate
        )
        let rules = flattenedRules(result.rules)
        let dueRule = rules.first { $0.field == .due && $0.operator == .onOrBefore }

        XCTAssertEqual(result.rules.operator, .and)
        XCTAssertTrue(rules.contains { $0.field == .project && $0.operator == .equals && $0.stringValue == "Tl" })
        XCTAssertEqual(
            dueRule?.value,
            .object([
                "op": .string("date_phrase"),
                "phrase": .string("upcoming friday")
            ])
        )
        XCTAssertTrue(rules.contains { $0.field == .status && $0.operator == .notEquals && $0.stringValue == TaskStatus.done.rawValue })
        XCTAssertEqual(result.confidence, 1)
        XCTAssertFalse(result.requiresCloudFallback)
    }

    func testDueThisUpcomingFridayParsesToConcreteDueRule() {
        let result = parser.parse(
            "in project TL due this upcoming Friday",
            relativeTo: referenceDate
        )
        let rules = flattenedRules(result.rules)
        let dueRule = rules.first { $0.field == .due && $0.operator == .on }

        XCTAssertEqual(result.rules.operator, .and)
        XCTAssertTrue(rules.contains { $0.field == .project && $0.operator == .equals && $0.stringValue == "Tl" })
        XCTAssertEqual(
            dueRule?.value,
            .object([
                "op": .string("date_phrase"),
                "phrase": .string("this upcoming friday")
            ])
        )
        XCTAssertEqual(result.confidence, 1)
        XCTAssertFalse(result.requiresCloudFallback)
    }

    func testIncompleteItemsInAlternateProjectOrderIncludeOverdueByUpcomingFriday() {
        let result = parser.parse(
            "incomplete items in TL project due this upcoming Friday",
            relativeTo: referenceDate
        )
        let rules = flattenedRules(result.rules)
        let dueRule = rules.first { $0.field == .due && $0.operator == .onOrBefore }
        let statusRule = rules.first { $0.field == .status && $0.operator == .in }

        XCTAssertEqual(result.rules.operator, .and)
        XCTAssertTrue(rules.contains { $0.field == .project && $0.operator == .equals && $0.stringValue == "Tl" })
        XCTAssertEqual(
            dueRule?.value,
            .object([
                "op": .string("date_phrase"),
                "phrase": .string("this upcoming friday")
            ])
        )
        XCTAssertEqual(
            statusRule?.value,
            .array([
                .string(TaskStatus.todo.rawValue),
                .string(TaskStatus.inProgress.rawValue),
                .string(TaskStatus.someday.rawValue)
            ])
        )
        XCTAssertEqual(result.confidence, 1)
        XCTAssertFalse(result.requiresCloudFallback)
    }

    func testShowMeAllIncompleteItemsLeadPhraseStillTriggersIncompleteBehavior() {
        let result = parser.parse(
            "show me all incomplete items in TL project due this upcoming Friday",
            relativeTo: referenceDate
        )
        let rules = flattenedRules(result.rules)
        let dueRule = rules.first { $0.field == .due && $0.operator == .onOrBefore }
        let statusRule = rules.first { $0.field == .status && $0.operator == .in }

        XCTAssertTrue(rules.contains { $0.field == .project && $0.operator == .equals && $0.stringValue == "Tl" })
        XCTAssertEqual(
            dueRule?.value,
            .object([
                "op": .string("date_phrase"),
                "phrase": .string("this upcoming friday")
            ])
        )
        XCTAssertEqual(
            statusRule?.value,
            .array([
                .string(TaskStatus.todo.rawValue),
                .string(TaskStatus.inProgress.rawValue),
                .string(TaskStatus.someday.rawValue)
            ])
        )
    }

    func testExactDateWithNotDoneStaysExact() {
        let result = parser.parse(
            "anything in project TL due March 6 not done",
            relativeTo: referenceDate
        )
        let rules = flattenedRules(result.rules)
        let dueRule = rules.first { $0.field == .due }

        XCTAssertTrue(rules.contains { $0.field == .project && $0.operator == .equals && $0.stringValue == "Tl" })
        XCTAssertEqual(dueRule?.operator, .on)
        XCTAssertEqual(dueRule?.stringValue, "2026-03-06")
        XCTAssertTrue(rules.contains { $0.field == .status && $0.operator == .notEquals && $0.stringValue == TaskStatus.done.rawValue })
    }

    func testProjectNamedIncompleteDoesNotTriggerIncompleteKeywordBehavior() {
        let result = parser.parse(
            "in project Incomplete Migration due March 6",
            relativeTo: referenceDate
        )
        let rules = flattenedRules(result.rules)
        let dueRule = rules.first { $0.field == .due }

        XCTAssertEqual(result.rules.operator, .and)
        XCTAssertTrue(rules.contains { $0.field == .project && $0.operator == .equals && $0.stringValue == "Incomplete Migration" })
        XCTAssertEqual(dueRule?.operator, .on)
        XCTAssertEqual(dueRule?.stringValue, "2026-03-06")
        XCTAssertFalse(rules.contains { $0.field == .status && $0.operator == .in })
        XCTAssertFalse(rules.contains { $0.field == .status && $0.operator == .notEquals })
        XCTAssertEqual(result.confidence, 1)
        XCTAssertFalse(result.requiresCloudFallback)
    }

    func testProjectNamedIncompleteAloneDoesNotTriggerIncompleteKeywordBehavior() {
        let result = parser.parse(
            "in project Incomplete due March 6",
            relativeTo: referenceDate
        )
        let rules = flattenedRules(result.rules)
        let dueRule = rules.first { $0.field == .due }

        XCTAssertEqual(result.rules.operator, .and)
        XCTAssertTrue(rules.contains { $0.field == .project && $0.operator == .equals && $0.stringValue == "Incomplete" })
        XCTAssertEqual(dueRule?.operator, .on)
        XCTAssertEqual(dueRule?.stringValue, "2026-03-06")
        XCTAssertFalse(rules.contains { $0.field == .status && $0.operator == .in })
        XCTAssertFalse(rules.contains { $0.field == .status && $0.operator == .notEquals })
    }

    func testProjectNamedEndingWithIncompleteDoesNotTriggerIncompleteKeywordBehavior() {
        let result = parser.parse(
            "in project Migration Incomplete due March 6",
            relativeTo: referenceDate
        )
        let rules = flattenedRules(result.rules)
        let dueRule = rules.first { $0.field == .due }

        XCTAssertEqual(result.rules.operator, .and)
        XCTAssertTrue(rules.contains { $0.field == .project && $0.operator == .equals && $0.stringValue == "Migration Incomplete" })
        XCTAssertEqual(dueRule?.operator, .on)
        XCTAssertEqual(dueRule?.stringValue, "2026-03-06")
        XCTAssertFalse(rules.contains { $0.field == .status && $0.operator == .in })
        XCTAssertFalse(rules.contains { $0.field == .status && $0.operator == .notEquals })
    }

    func testTaggedIncompleteDoesNotTriggerIncompleteKeywordBehavior() {
        let result = parser.parse(
            "tagged incomplete due March 6",
            relativeTo: referenceDate
        )
        let rules = flattenedRules(result.rules)
        let dueRule = rules.first { $0.field == .due }

        XCTAssertTrue(rules.contains { $0.field == .tags && $0.operator == .contains && $0.stringValue == "incomplete" })
        XCTAssertEqual(dueRule?.operator, .on)
        XCTAssertEqual(dueRule?.stringValue, "2026-03-06")
        XCTAssertFalse(rules.contains { $0.field == .status && $0.operator == .in })
    }

    func testAssignedToIncompleteDoesNotTriggerIncompleteKeywordBehavior() {
        let result = parser.parse(
            "assigned to incomplete due March 6",
            relativeTo: referenceDate
        )
        let rules = flattenedRules(result.rules)
        let dueRule = rules.first { $0.field == .due }

        XCTAssertTrue(rules.contains { $0.field == .assignee && $0.operator == .equals && $0.stringValue == "incomplete" })
        XCTAssertEqual(dueRule?.operator, .on)
        XCTAssertEqual(dueRule?.stringValue, "2026-03-06")
        XCTAssertFalse(rules.contains { $0.field == .status && $0.operator == .in })
    }

    func testProjectListContainingIncompleteDoesNotTriggerIncompleteKeywordBehavior() {
        let result = parser.parse(
            "in projects Home and Incomplete due March 6",
            relativeTo: referenceDate
        )
        let rules = flattenedRules(result.rules)
        let dueRule = rules.first { $0.field == .due }
        let projectRules = rules.filter { $0.field == .project && $0.operator == .equals }

        XCTAssertEqual(Set(projectRules.map(\.stringValue)), Set(["Home", "Incomplete"]))
        XCTAssertEqual(dueRule?.operator, .on)
        XCTAssertEqual(dueRule?.stringValue, "2026-03-06")
        XCTAssertFalse(rules.contains { $0.field == .status && $0.operator == .in })
    }

    func testAlternateOrderProjectStopsBeforeCompletedByProjectBotClause() {
        let result = parser.parse(
            "in TL project completed by project-bot due March 6",
            relativeTo: referenceDate
        )
        let rules = flattenedRules(result.rules)
        let dueRule = rules.first { $0.field == .due }

        XCTAssertTrue(rules.contains { $0.field == .project && $0.operator == .equals && $0.stringValue == "Tl" })
        XCTAssertTrue(rules.contains { $0.field == .completedBy && $0.operator == .equals && $0.stringValue == "project-bot" })
        XCTAssertEqual(dueRule?.operator, .on)
        XCTAssertEqual(dueRule?.stringValue, "2026-03-06")
    }

    func testDueByUpcomingFridayParsesToOnOrBeforeRule() {
        let result = parser.parse(
            "in project TL due by upcoming Friday",
            relativeTo: referenceDate
        )
        let rules = flattenedRules(result.rules)
        let dueRule = rules.first { $0.field == .due && $0.operator == .onOrBefore }

        XCTAssertEqual(result.rules.operator, .and)
        XCTAssertTrue(rules.contains { $0.field == .project && $0.operator == .equals && $0.stringValue == "Tl" })
        XCTAssertEqual(
            dueRule?.value,
            .object([
                "op": .string("date_phrase"),
                "phrase": .string("upcoming friday")
            ])
        )
        XCTAssertEqual(result.confidence, 1)
        XCTAssertFalse(result.requiresCloudFallback)
        XCTAssertEqual(result.summary, "Showing tasks where in project Tl and due on or before upcoming friday.")
    }

    func testUpcomingWeekdayParsesInDateParser() {
        let dateParser = NaturalLanguageDateParser(calendar: Calendar(identifier: .gregorian))
        let parsed = dateParser.parse("upcoming friday", relativeTo: referenceDate)

        XCTAssertEqual(parsed?.isoString, "2026-03-06")
    }

    func testThisUpcomingWeekdayParsesInDateParser() {
        let dateParser = NaturalLanguageDateParser(calendar: Calendar(identifier: .gregorian))
        let parsed = dateParser.parse("this upcoming friday", relativeTo: referenceDate)

        XCTAssertEqual(parsed?.isoString, "2026-03-06")
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
        for condition in group.conditions {
            if case .group(let nested) = condition {
                if nested.operator == op || containsGroup(nested, op: op) {
                    return true
                }
            }
        }
        return false
    }
}
