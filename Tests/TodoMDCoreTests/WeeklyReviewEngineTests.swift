import XCTest
@testable import TodoMDCore

final class WeeklyReviewEngineTests: XCTestCase {
    private var calendar: Calendar!
    private var engine: WeeklyReviewEngine!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        engine = WeeklyReviewEngine(calendar: calendar, staleAfterDays: 14)
    }

    func testSectionsIncludeOverdueStaleSomedayAndProjectsWithoutNextAction() throws {
        let today = try LocalDate(isoDate: "2026-03-06")
        let now = ISO8601DateFormatter().date(from: "2026-03-06T12:00:00Z")!

        let overdue = makeRecord(
            path: "/tmp/overdue.md",
            title: "Overdue",
            configure: { frontmatter in
                frontmatter.due = try? LocalDate(isoDate: "2026-03-04")
                frontmatter.project = "Launch"
            }
        )
        let stale = makeRecord(
            path: "/tmp/stale.md",
            title: "Stale",
            configure: { frontmatter in
                frontmatter.modified = ISO8601DateFormatter().date(from: "2026-02-10T12:00:00Z")
            }
        )
        let someday = makeRecord(
            path: "/tmp/someday.md",
            title: "Someday",
            status: .someday
        )
        let noNextActionProject = makeRecord(
            path: "/tmp/project.md",
            title: "Blocked project task",
            configure: { frontmatter in
                frontmatter.project = "Backlog Cleanup"
                frontmatter.blockedBy = .manual
            }
        )

        let sections = engine.sections(
            for: [overdue, stale, someday, noNextActionProject],
            today: today,
            now: now
        )

        XCTAssertEqual(sections.map(\.kind), [.overdue, .stale, .someday, .projectsWithoutNextAction])
        XCTAssertEqual(sections.first(where: { $0.kind == .overdue })?.records.map(\.document.frontmatter.title), ["Overdue"])
        XCTAssertEqual(sections.first(where: { $0.kind == .stale })?.records.map(\.document.frontmatter.title), ["Blocked project task", "Stale"])
        XCTAssertEqual(sections.first(where: { $0.kind == .someday })?.records.map(\.document.frontmatter.title), ["Someday"])
        XCTAssertEqual(sections.first(where: { $0.kind == .projectsWithoutNextAction })?.projects.map(\.project), ["Backlog Cleanup"])
    }

    func testStaleDetectionUsesLastModifiedOrCreatedDate() throws {
        let today = try LocalDate(isoDate: "2026-03-06")
        let now = ISO8601DateFormatter().date(from: "2026-03-06T12:00:00Z")!

        let stale = makeRecord(
            path: "/tmp/stale-check.md",
            title: "Old task",
            configure: { frontmatter in
                frontmatter.modified = ISO8601DateFormatter().date(from: "2026-02-15T12:00:00Z")
            }
        )
        let fresh = makeRecord(
            path: "/tmp/fresh-check.md",
            title: "Fresh task",
            configure: { frontmatter in
                frontmatter.modified = ISO8601DateFormatter().date(from: "2026-03-01T12:00:00Z")
            }
        )

        XCTAssertTrue(engine.isStale(stale, today: today, now: now))
        XCTAssertFalse(engine.isStale(fresh, today: today, now: now))
    }

    func testProjectWithAvailableUserTaskIsNotFlaggedAsMissingNextAction() throws {
        let today = try LocalDate(isoDate: "2026-03-06")
        let actionable = makeRecord(
            path: "/tmp/actionable.md",
            title: "Next action",
            configure: { frontmatter in
                frontmatter.project = "Roadmap"
            }
        )
        let blocked = makeRecord(
            path: "/tmp/blocked.md",
            title: "Blocked follow-up",
            configure: { frontmatter in
                frontmatter.project = "Roadmap"
                frontmatter.blockedBy = .manual
            }
        )

        let summaries = engine.projectSummariesWithoutNextAction(records: [actionable, blocked], today: today)
        XCTAssertTrue(summaries.isEmpty)
    }

    func testDelegatedDeferredAndSomedayProjectCountsAreTracked() throws {
        let today = try LocalDate(isoDate: "2026-03-06")
        let delegated = makeRecord(
            path: "/tmp/delegated.md",
            title: "Waiting on Alex",
            configure: { frontmatter in
                frontmatter.project = "Website"
                frontmatter.assignee = "alex"
            }
        )
        let deferred = makeRecord(
            path: "/tmp/deferred.md",
            title: "Start later",
            configure: { frontmatter in
                frontmatter.project = "Website"
                frontmatter.defer = try? LocalDate(isoDate: "2026-03-10")
            }
        )
        let someday = makeRecord(
            path: "/tmp/someday-project.md",
            title: "Maybe redesign",
            status: .someday,
            configure: { frontmatter in
                frontmatter.project = "Website"
            }
        )

        let summaries = engine.projectSummariesWithoutNextAction(records: [delegated, deferred, someday], today: today)
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries[0], WeeklyReviewProjectSummary(
            project: "Website",
            taskCount: 3,
            blockedCount: 0,
            delegatedCount: 1,
            deferredCount: 1,
            somedayCount: 1
        ))
    }

    private func makeRecord(
        path: String,
        title: String,
        status: TaskStatus = .todo,
        configure: ((inout TaskFrontmatterV1) -> Void)? = nil
    ) -> TaskRecord {
        var frontmatter = TestSupport.sampleFrontmatter(title: title, status: status)
        configure?(&frontmatter)
        return TaskRecord(
            identity: TaskFileIdentity(path: path),
            document: TaskDocument(frontmatter: frontmatter, body: "")
        )
    }
}
