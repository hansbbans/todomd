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

    func testBlockedTaskExcludedFromAnytime() throws {
        var frontmatter = TestSupport.sampleFrontmatter()
        frontmatter.blockedBy = .manual
        let record = TaskRecord(identity: TaskFileIdentity(path: "/tmp/e.md"), document: .init(frontmatter: frontmatter, body: ""))
        let today = try LocalDate(isoDate: "2025-03-01")

        XCTAssertFalse(engine.matches(record, view: .builtIn(.anytime), today: today))
    }

    func testDelegatedAndMyTasksViews() throws {
        var delegated = TestSupport.sampleFrontmatter(title: "Delegated")
        delegated.assignee = "codex"
        let delegatedRecord = TaskRecord(identity: TaskFileIdentity(path: "/tmp/f.md"), document: .init(frontmatter: delegated, body: ""))

        let myRecord = TaskRecord(identity: TaskFileIdentity(path: "/tmp/g.md"), document: .init(frontmatter: TestSupport.sampleFrontmatter(title: "Mine"), body: ""))

        let today = try LocalDate(isoDate: "2025-03-01")
        XCTAssertTrue(engine.matches(myRecord, view: .builtIn(.myTasks), today: today))
        XCTAssertFalse(engine.matches(myRecord, view: .builtIn(.delegated), today: today))
        XCTAssertTrue(engine.matches(delegatedRecord, view: .builtIn(.delegated), today: today))
        XCTAssertFalse(engine.matches(delegatedRecord, view: .builtIn(.myTasks), today: today))
    }
}
