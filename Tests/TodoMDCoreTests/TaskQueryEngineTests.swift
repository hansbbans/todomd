import XCTest
@testable import TodoMDCore

final class TaskQueryEngineTests: XCTestCase {
    private let engine = TaskQueryEngine()
    private let defaultEveningStart = try! LocalTime(isoTime: "18:00")

    func testInboxMembership() throws {
        let record = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/a.md"),
            document: TaskDocument(frontmatter: TestSupport.sampleFrontmatter(), body: "")
        )
        let today = try LocalDate(isoDate: "2025-03-01")
        XCTAssertTrue(engine.matches(record, view: .builtIn(.inbox), today: today, eveningStart: defaultEveningStart))
    }

    func testTodayOverdueMembership() throws {
        let due = try LocalDate(isoDate: "2025-02-28")
        let frontmatter = TestSupport.sampleFrontmatter(due: due)
        let record = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/b.md"),
            document: TaskDocument(frontmatter: frontmatter, body: "")
        )
        let today = try LocalDate(isoDate: "2025-03-01")
        XCTAssertTrue(engine.matches(record, view: .builtIn(.today), today: today, eveningStart: defaultEveningStart))
        XCTAssertEqual(engine.todayGroup(for: record, today: today, eveningStart: defaultEveningStart), .overdue)
    }

    func testAnytimeExcludesDeferredFuture() throws {
        let deferDate = try LocalDate(isoDate: "2025-03-10")
        let frontmatter = TestSupport.sampleFrontmatter(deferDate: deferDate)
        let record = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/c.md"),
            document: TaskDocument(frontmatter: frontmatter, body: "")
        )
        let today = try LocalDate(isoDate: "2025-03-01")
        XCTAssertFalse(engine.matches(record, view: .builtIn(.anytime), today: today, eveningStart: defaultEveningStart))
    }

    func testFlaggedView() throws {
        var frontmatter = TestSupport.sampleFrontmatter()
        frontmatter.flagged = true
        let record = TaskRecord(identity: TaskFileIdentity(path: "/tmp/d.md"), document: .init(frontmatter: frontmatter, body: ""))
        let today = try LocalDate(isoDate: "2025-03-01")
        XCTAssertTrue(engine.matches(record, view: .builtIn(.flagged), today: today, eveningStart: defaultEveningStart))
    }

    func testBlockedTaskExcludedFromAnytime() throws {
        var frontmatter = TestSupport.sampleFrontmatter()
        frontmatter.blockedBy = .manual
        let record = TaskRecord(identity: TaskFileIdentity(path: "/tmp/e.md"), document: .init(frontmatter: frontmatter, body: ""))
        let today = try LocalDate(isoDate: "2025-03-01")

        XCTAssertFalse(engine.matches(record, view: .builtIn(.anytime), today: today, eveningStart: defaultEveningStart))
    }

    func testDelegatedAndMyTasksViews() throws {
        var delegated = TestSupport.sampleFrontmatter(title: "Delegated")
        delegated.assignee = "codex"
        let delegatedRecord = TaskRecord(identity: TaskFileIdentity(path: "/tmp/f.md"), document: .init(frontmatter: delegated, body: ""))

        let myRecord = TaskRecord(identity: TaskFileIdentity(path: "/tmp/g.md"), document: .init(frontmatter: TestSupport.sampleFrontmatter(title: "Mine"), body: ""))

        let today = try LocalDate(isoDate: "2025-03-01")
        XCTAssertTrue(engine.matches(myRecord, view: .builtIn(.myTasks), today: today, eveningStart: defaultEveningStart))
        XCTAssertFalse(engine.matches(myRecord, view: .builtIn(.delegated), today: today, eveningStart: defaultEveningStart))
        XCTAssertTrue(engine.matches(delegatedRecord, view: .builtIn(.delegated), today: today, eveningStart: defaultEveningStart))
        XCTAssertFalse(engine.matches(delegatedRecord, view: .builtIn(.myTasks), today: today, eveningStart: defaultEveningStart))
    }

    func testProjectViewExcludesDoneAndCancelledTasks() throws {
        var active = TestSupport.sampleFrontmatter()
        active.project = "MyProject"
        let activeRecord = TaskRecord(identity: TaskFileIdentity(path: "/tmp/proj-a.md"), document: .init(frontmatter: active, body: ""))

        var done = TestSupport.sampleFrontmatter(status: .done)
        done.project = "MyProject"
        let doneRecord = TaskRecord(identity: TaskFileIdentity(path: "/tmp/proj-b.md"), document: .init(frontmatter: done, body: ""))

        var cancelled = TestSupport.sampleFrontmatter(status: .cancelled)
        cancelled.project = "MyProject"
        let cancelledRecord = TaskRecord(identity: TaskFileIdentity(path: "/tmp/proj-c.md"), document: .init(frontmatter: cancelled, body: ""))

        let today = try LocalDate(isoDate: "2025-03-01")
        XCTAssertTrue(engine.matches(activeRecord, view: .project("MyProject"), today: today, eveningStart: defaultEveningStart))
        XCTAssertFalse(engine.matches(doneRecord, view: .project("MyProject"), today: today, eveningStart: defaultEveningStart))
        XCTAssertFalse(engine.matches(cancelledRecord, view: .project("MyProject"), today: today, eveningStart: defaultEveningStart))
    }

    func testLogbookMatchesDoneAndCancelledTasks() throws {
        let done = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/logbook-done.md"),
            document: TaskDocument(frontmatter: TestSupport.sampleFrontmatter(status: .done), body: "")
        )
        let cancelled = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/logbook-cancelled.md"),
            document: TaskDocument(frontmatter: TestSupport.sampleFrontmatter(status: .cancelled), body: "")
        )
        let active = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/logbook-active.md"),
            document: TaskDocument(frontmatter: TestSupport.sampleFrontmatter(), body: "")
        )

        let today = try LocalDate(isoDate: "2025-03-01")
        XCTAssertTrue(engine.matches(done, view: .builtIn(.logbook), today: today, eveningStart: defaultEveningStart))
        XCTAssertTrue(engine.matches(cancelled, view: .builtIn(.logbook), today: today, eveningStart: defaultEveningStart))
        XCTAssertFalse(engine.matches(active, view: .builtIn(.logbook), today: today, eveningStart: defaultEveningStart))
    }

    func testAreaAndTagViewsExcludeDoneTasks() throws {
        var active = TestSupport.sampleFrontmatter()
        active.area = "Work"
        active.tags = ["focus"]
        let activeRecord = TaskRecord(identity: TaskFileIdentity(path: "/tmp/area-tag-active.md"), document: .init(frontmatter: active, body: ""))

        var done = TestSupport.sampleFrontmatter(status: .done)
        done.area = "Work"
        done.tags = ["focus"]
        let doneRecord = TaskRecord(identity: TaskFileIdentity(path: "/tmp/area-tag-done.md"), document: .init(frontmatter: done, body: ""))

        let today = try LocalDate(isoDate: "2025-03-01")
        XCTAssertTrue(engine.matches(activeRecord, view: .area("Work"), today: today, eveningStart: defaultEveningStart))
        XCTAssertFalse(engine.matches(doneRecord, view: .area("Work"), today: today, eveningStart: defaultEveningStart))
        XCTAssertTrue(engine.matches(activeRecord, view: .tag("focus"), today: today, eveningStart: defaultEveningStart))
        XCTAssertFalse(engine.matches(doneRecord, view: .tag("focus"), today: today, eveningStart: defaultEveningStart))
    }

    func testTodayGroup_scheduledEvening_atEveningStart() throws {
        let today = try LocalDate(isoDate: "2026-03-17")
        let eveningStart = try LocalTime(isoTime: "18:00")
        var fm = TestSupport.sampleFrontmatter()
        fm.scheduled = today
        fm.scheduledTime = try LocalTime(isoTime: "18:00")
        let record = TaskRecord(identity: .init(path: "/tmp/ev1.md"),
                                document: .init(frontmatter: fm, body: ""))
        XCTAssertEqual(engine.todayGroup(for: record, today: today, eveningStart: eveningStart), .scheduledEvening)
    }

    func testTodayGroup_scheduledEvening_afterEveningStart() throws {
        let today = try LocalDate(isoDate: "2026-03-17")
        let eveningStart = try LocalTime(isoTime: "18:00")
        var fm = TestSupport.sampleFrontmatter()
        fm.scheduled = today
        fm.scheduledTime = try LocalTime(isoTime: "21:00")
        let record = TaskRecord(identity: .init(path: "/tmp/ev2.md"),
                                document: .init(frontmatter: fm, body: ""))
        XCTAssertEqual(engine.todayGroup(for: record, today: today, eveningStart: eveningStart), .scheduledEvening)
    }

    func testTodayGroup_scheduledDay_beforeEveningStart() throws {
        let today = try LocalDate(isoDate: "2026-03-17")
        let eveningStart = try LocalTime(isoTime: "18:00")
        var fm = TestSupport.sampleFrontmatter()
        fm.scheduled = today
        fm.scheduledTime = try LocalTime(isoTime: "10:00")
        let record = TaskRecord(identity: .init(path: "/tmp/ev3.md"),
                                document: .init(frontmatter: fm, body: ""))
        XCTAssertEqual(engine.todayGroup(for: record, today: today, eveningStart: eveningStart), .scheduled)
    }

    func testTodayGroup_scheduledDay_noTime() throws {
        let today = try LocalDate(isoDate: "2026-03-17")
        let eveningStart = try LocalTime(isoTime: "18:00")
        var fm = TestSupport.sampleFrontmatter()
        fm.scheduled = today
        fm.scheduledTime = nil
        let record = TaskRecord(identity: .init(path: "/tmp/ev4.md"),
                                document: .init(frontmatter: fm, body: ""))
        XCTAssertEqual(engine.todayGroup(for: record, today: today, eveningStart: eveningStart), .scheduled)
    }

    func testTodayGroup_eveningFuture_notInToday() throws {
        let today = try LocalDate(isoDate: "2026-03-17")
        let tomorrow = try LocalDate(isoDate: "2026-03-18")
        let eveningStart = try LocalTime(isoTime: "18:00")
        var fm = TestSupport.sampleFrontmatter()
        fm.scheduled = tomorrow
        fm.scheduledTime = try LocalTime(isoTime: "20:00")
        let record = TaskRecord(identity: .init(path: "/tmp/ev5.md"),
                                document: .init(frontmatter: fm, body: ""))
        XCTAssertNil(engine.todayGroup(for: record, today: today, eveningStart: eveningStart))
    }

    func testTodayGroup_overdue_takesPrecedence() throws {
        let today = try LocalDate(isoDate: "2026-03-17")
        let yesterday = try LocalDate(isoDate: "2026-03-16")
        let eveningStart = try LocalTime(isoTime: "18:00")
        var fm = TestSupport.sampleFrontmatter()
        fm.due = yesterday
        fm.scheduled = today
        fm.scheduledTime = try LocalTime(isoTime: "20:00")
        let record = TaskRecord(identity: .init(path: "/tmp/ev6.md"),
                                document: .init(frontmatter: fm, body: ""))
        XCTAssertEqual(engine.todayGroup(for: record, today: today, eveningStart: eveningStart), .overdue)
    }

    func testIsToday_includesScheduledEveningTasks() throws {
        let today = try LocalDate(isoDate: "2026-03-17")
        let eveningStart = try LocalTime(isoTime: "18:00")
        var fm = TestSupport.sampleFrontmatter()
        fm.scheduled = today
        fm.scheduledTime = try LocalTime(isoTime: "20:00")
        let record = TaskRecord(identity: .init(path: "/tmp/ev7.md"),
                                document: .init(frontmatter: fm, body: ""))
        XCTAssertTrue(engine.isToday(record, today: today, eveningStart: eveningStart))
    }
}
