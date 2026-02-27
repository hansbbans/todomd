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
}
