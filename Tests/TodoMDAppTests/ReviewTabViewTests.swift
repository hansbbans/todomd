import Foundation
import Testing
@testable import TodoMDApp

struct ReviewTabViewTests {
    @Test("Descriptor keeps review list identity and review row presentation")
    func descriptorKeepsReviewTabStructure() {
        let overdueRecord = makeRecord(title: "Overdue", path: "/tmp/overdue.md")
        let descriptor = ReviewTabDescriptor.make(sections: [
            WeeklyReviewSection(kind: .overdue, records: [overdueRecord]),
            WeeklyReviewSection(
                kind: .projectsWithoutNextAction,
                projects: [
                    WeeklyReviewProjectSummary(
                        project: "Roadmap",
                        taskCount: 2,
                        blockedCount: 1,
                        delegatedCount: 0,
                        deferredCount: 0,
                        somedayCount: 0
                    )
                ]
            )
        ])

        #expect(descriptor.listID == BuiltInView.review.rawValue)
        #expect(!descriptor.showsClearState)
        #expect(descriptor.sections.count == 2)
        #expect(descriptor.sections[0].title == "Overdue")
        #expect(descriptor.sections[0].count == 1)
        #expect(descriptor.sections[0].taskRecordPaths == ["/tmp/overdue.md"])
        #expect(descriptor.sections[0].projectRows.isEmpty)
        #expect(descriptor.sections[1].title == "Projects With No Next Action")
        #expect(descriptor.sections[1].count == 1)
        #expect(descriptor.sections[1].taskRecordPaths.isEmpty)
        #expect(
            descriptor.sections[1].projectRows == [
                ReviewProjectRowDescriptor(
                    project: "Roadmap",
                    summaryText: "2 open  ·  1 blocked  ·  no current next action"
                )
            ]
        )
    }

    @Test("Descriptor shows clear-state copy when review is empty")
    func descriptorShowsClearStateForEmptyReview() {
        let descriptor = ReviewTabDescriptor.make(sections: [])

        #expect(descriptor.listID == BuiltInView.review.rawValue)
        #expect(descriptor.showsClearState)
        #expect(
            descriptor.clearState == ReviewTabClearState(
                title: "Review Is Clear",
                systemImage: "checkmark.circle",
                description: "Nothing is stale, overdue, deferred into someday, or missing a next action."
            )
        )
        #expect(descriptor.sections.isEmpty)
    }

    @Test("Project summary text includes only non-zero counters")
    func projectSummaryTextIncludesOnlyNonZeroCounters() {
        let summary = WeeklyReviewProjectSummary(
            project: "Roadmap",
            taskCount: 4,
            blockedCount: 1,
            delegatedCount: 0,
            deferredCount: 2,
            somedayCount: 0
        )

        #expect(
            ReviewProjectSummaryFormatter.makeText(summary) ==
            "4 open  ·  1 blocked  ·  2 deferred  ·  no current next action"
        )
    }

    private func makeRecord(title: String, path: String) -> TaskRecord {
        let frontmatter = TaskFrontmatterV1(
            title: title,
            status: .todo,
            priority: .none,
            flagged: false,
            created: Date(timeIntervalSince1970: 1_700_000_000),
            modified: Date(timeIntervalSince1970: 1_700_000_000),
            source: "test"
        )

        return TaskRecord(
            identity: TaskFileIdentity(path: path),
            document: TaskDocument(frontmatter: frontmatter, body: "")
        )
    }
}
