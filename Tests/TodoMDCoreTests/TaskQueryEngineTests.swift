import XCTest
@testable import TodoMDCore

final class TaskQueryEngineTests: XCTestCase {
    private let engine = TaskQueryEngine()

    func testInboxMembership() throws {
        let record = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/a.md"),
            document: TaskDocument(frontmatter: TestSupport.sampleFrontmatter(), body: "")
        )
        let today = try LocalDate(isoDate: "2025-03-01")
        XCTAssertTrue(engine.matches(record, view: .builtIn(.inbox), today: today))
    }

    func testTodayOverdueMembership() throws {
        let due = try LocalDate(isoDate: "2025-02-28")
        let frontmatter = TestSupport.sampleFrontmatter(due: due)
        let record = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/b.md"),
            document: TaskDocument(frontmatter: frontmatter, body: "")
        )
        let today = try LocalDate(isoDate: "2025-03-01")
        XCTAssertTrue(engine.matches(record, view: .builtIn(.today), today: today))
        XCTAssertEqual(engine.todayGroup(for: record, today: today), .overdue)
    }

    func testAnytimeExcludesDeferredFuture() throws {
        let deferDate = try LocalDate(isoDate: "2025-03-10")
        let frontmatter = TestSupport.sampleFrontmatter(deferDate: deferDate)
        let record = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/c.md"),
            document: TaskDocument(frontmatter: frontmatter, body: "")
        )
        let today = try LocalDate(isoDate: "2025-03-01")
        XCTAssertFalse(engine.matches(record, view: .builtIn(.anytime), today: today))
    }

    func testFlaggedView() throws {
        var frontmatter = TestSupport.sampleFrontmatter()
        frontmatter.flagged = true
        let record = TaskRecord(identity: TaskFileIdentity(path: "/tmp/d.md"), document: .init(frontmatter: frontmatter, body: ""))
        let today = try LocalDate(isoDate: "2025-03-01")
        XCTAssertTrue(engine.matches(record, view: .builtIn(.flagged), today: today))
    }
}
