import XCTest
@testable import TodoMDCore

final class LogbookSearchEngineTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testFreeTextSearchMatchesTitleAndBody() {
        let engine = LogbookSearchEngine(calendar: calendar)
        let record = makeRecord(
            title: "Archive receipts",
            body: "Paper trail for the quarterly close."
        )

        XCTAssertEqual(engine.filter(records: [record], query: "quarterly").count, 1)
        XCTAssertEqual(engine.filter(records: [record], query: "receipts").count, 1)
        XCTAssertTrue(engine.filter(records: [record], query: "missing").isEmpty)
    }

    func testProjectAndTagFiltersSupportQuotedValues() {
        let engine = LogbookSearchEngine(calendar: calendar)
        let record = makeRecord(
            title: "Ship launch checklist",
            project: "Client Launch",
            tags: ["Release"]
        )

        XCTAssertEqual(engine.filter(records: [record], query: "project:\"Client Launch\"").count, 1)
        XCTAssertEqual(engine.filter(records: [record], query: "tag:release").count, 1)
        XCTAssertTrue(engine.filter(records: [record], query: "project:\"Other Project\"").isEmpty)
    }

    func testStatusSourceAndCompletedByFiltersMatchMetadata() {
        let engine = LogbookSearchEngine(calendar: calendar)
        let record = makeRecord(
            title: "Close duplicate bug",
            status: .cancelled,
            source: "codex-agent",
            completedBy: "automation-bot"
        )

        XCTAssertEqual(engine.filter(records: [record], query: "status:cancelled").count, 1)
        XCTAssertEqual(engine.filter(records: [record], query: "source:codex").count, 1)
        XCTAssertEqual(engine.filter(records: [record], query: "completed-by:automation").count, 1)
        XCTAssertTrue(engine.filter(records: [record], query: "status:done").isEmpty)
    }

    func testDateFiltersUseEffectiveLogbookDate() throws {
        let engine = LogbookSearchEngine(calendar: calendar)
        let marchFourth = try makeDate("2025-03-04T12:00:00Z")
        let marchFifth = try makeDate("2025-03-05T12:00:00Z")

        let completedRecord = makeRecord(
            title: "Completed task",
            completed: marchFifth
        )
        let cancelledRecord = makeRecord(
            title: "Cancelled task",
            status: .cancelled,
            completed: nil,
            modified: marchFourth
        )

        XCTAssertEqual(engine.filter(records: [completedRecord], query: "on:2025-03-05").count, 1)
        XCTAssertEqual(engine.filter(records: [cancelledRecord], query: "before:2025-03-05").count, 1)
        XCTAssertEqual(engine.filter(records: [completedRecord], query: "after:2025-03-04").count, 1)
    }

    func testFlaggedAndAssigneeFiltersWorkTogether() {
        let engine = LogbookSearchEngine(calendar: calendar)
        let matching = makeRecord(
            title: "Flagged handoff",
            assignee: "Alex",
            flagged: true
        )
        let nonMatching = makeRecord(
            title: "Regular handoff",
            assignee: "Alex",
            flagged: false
        )

        let results = engine.filter(records: [matching, nonMatching], query: "flagged:true assignee:alex")
        XCTAssertEqual(results.map { $0.document.frontmatter.title }, ["Flagged handoff"])
    }

    private func makeRecord(
        title: String,
        body: String = "",
        status: TaskStatus = .done,
        project: String? = nil,
        tags: [String] = [],
        source: String = "user",
        assignee: String? = nil,
        completedBy: String? = nil,
        completed: Date? = nil,
        modified: Date? = nil,
        flagged: Bool = false
    ) -> TaskRecord {
        var frontmatter = TestSupport.sampleFrontmatter(title: title, status: status, source: source)
        frontmatter.project = project
        frontmatter.tags = tags
        frontmatter.assignee = assignee
        frontmatter.completedBy = completedBy
        frontmatter.completed = completed ?? frontmatter.created
        frontmatter.modified = modified ?? frontmatter.modified
        frontmatter.flagged = flagged
        return TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/\(UUID().uuidString).md"),
            document: TaskDocument(frontmatter: frontmatter, body: body)
        )
    }

    private func makeDate(_ iso8601: String) throws -> Date {
        guard let date = ISO8601DateFormatter().date(from: iso8601) else {
            throw NSError(domain: "LogbookSearchEngineTests", code: 1)
        }
        return date
    }
}
