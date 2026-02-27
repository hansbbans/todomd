import XCTest
@testable import TodoMDCore

final class PerspectiveQueryEngineTests: XCTestCase {
    private let engine = PerspectiveQueryEngine()

    func testMatchesAllAnyNoneRules() throws {
        var frontmatter = TestSupport.sampleFrontmatter(
            title: "Call daycare",
            due: try LocalDate(isoDate: "2025-03-01"),
            scheduled: try LocalDate(isoDate: "2025-03-02")
        )
        frontmatter.priority = .high
        frontmatter.flagged = true
        frontmatter.tags = ["family", "calls"]

        let record = TaskRecord(identity: TaskFileIdentity(path: "/tmp/a.md"), document: .init(frontmatter: frontmatter, body: ""))

        let perspective = PerspectiveDefinition(
            name: "Urgent Calls",
            allRules: [
                PerspectiveRule(field: .priority, operator: .equals, value: "high"),
                PerspectiveRule(field: .tags, operator: .contains, value: "call")
            ],
            anyRules: [
                PerspectiveRule(field: .flagged, operator: .isTrue),
                PerspectiveRule(field: .due, operator: .beforeToday)
            ],
            noneRules: [
                PerspectiveRule(field: .status, operator: .equals, value: "done")
            ]
        )

        let today = try LocalDate(isoDate: "2025-03-03")
        XCTAssertTrue(engine.matches(record, perspective: perspective, today: today))
    }

    func testDateRuleEqualsSupportsIsoDateValue() throws {
        let due = try LocalDate(isoDate: "2025-03-10")
        let record = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/b.md"),
            document: .init(frontmatter: TestSupport.sampleFrontmatter(due: due), body: "")
        )

        let rule = PerspectiveRule(field: .due, operator: .equals, value: "2025-03-10")
        XCTAssertTrue(engine.matchesRule(record, rule: rule, today: try LocalDate(isoDate: "2025-03-01")))
    }

    func testNestedGroupRulesEvaluateRecursively() throws {
        var frontmatter = TestSupport.sampleFrontmatter(
            title: "Draft design doc",
            due: try LocalDate(isoDate: "2025-03-06")
        )
        frontmatter.area = "Work"
        frontmatter.priority = .high
        frontmatter.flagged = false

        let record = TaskRecord(identity: TaskFileIdentity(path: "/tmp/nested.md"), document: .init(frontmatter: frontmatter, body: ""))

        let nested = PerspectiveRuleGroup(
            operator: .and,
            conditions: [
                .rule(PerspectiveRule(field: .area, operator: .equals, value: "Work")),
                .group(PerspectiveRuleGroup(
                    operator: .or,
                    conditions: [
                        .rule(PerspectiveRule(field: .priority, operator: .equals, value: "high")),
                        .rule(PerspectiveRule(field: .flagged, operator: .isTrue))
                    ]
                )),
                .group(PerspectiveRuleGroup(
                    operator: .not,
                    conditions: [.rule(PerspectiveRule(field: .status, operator: .in, jsonValue: .array([.string("done"), .string("cancelled")])))]
                ))
            ]
        )
        let perspective = PerspectiveDefinition(name: "Nested", allRules: [], anyRules: [], noneRules: [], rules: nested)

        XCTAssertTrue(engine.matches(record, perspective: perspective, today: try LocalDate(isoDate: "2025-03-03")))
    }

    func testDateRelativeRangeFromJsonObject() throws {
        let due = try LocalDate(isoDate: "2025-03-07")
        let record = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/range.md"),
            document: .init(frontmatter: TestSupport.sampleFrontmatter(due: due), body: "")
        )

        let rule = PerspectiveRule(
            field: .due,
            operator: .between,
            jsonValue: .object([
                "op": .string("in_next"),
                "value": .number(7),
                "unit": .string("days")
            ])
        )

        XCTAssertTrue(engine.matchesRule(record, rule: rule, today: try LocalDate(isoDate: "2025-03-03")))
    }

    func testUnknownRuleFieldIsIgnoredForAndGroup() throws {
        let record = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/unknown.md"),
            document: .init(frontmatter: TestSupport.sampleFrontmatter(), body: "")
        )

        let unknownRule = PerspectiveRule(field: .unknown("custom_field"), operator: .equals, value: "value")
        let perspective = PerspectiveDefinition(
            name: "Unknown Field",
            allRules: [unknownRule],
            anyRules: [],
            noneRules: []
        )

        XCTAssertTrue(engine.matches(record, perspective: perspective, today: try LocalDate(isoDate: "2025-03-03")))
    }
}
