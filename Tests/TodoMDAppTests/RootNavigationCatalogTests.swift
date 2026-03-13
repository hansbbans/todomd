import Testing
@testable import TodoMDApp

struct RootNavigationCatalogTests {
    @Test("Browse discovery sections list Perspectives before Workflows")
    func browseDiscoverySectionsPlacePerspectivesBeforeWorkflows() {
        #expect(RootNavigationCatalog.browseDiscoverySectionOrder == [
            .perspectives,
            .workflows
        ])
    }

    @Test("Workflow entries include Review and Inbox Triage")
    func workflowEntriesIncludeReviewAndInboxTriage() {
        let workflows = RootWorkflowEntry.allCases

        #expect(workflows == [.inboxTriage, .review])
        #expect(workflows.map(\.accessibilityIdentifier) == [
            "root.workflow.inboxTriage",
            "root.workflow.review"
        ])
    }

    @Test("Review is excluded from generic browse entries")
    func browseEntriesExcludeReview() {
        let views = RootNavigationCatalog
            .browseBuiltInEntries(pomodoroEnabled: true)
            .map(\.view)

        #expect(views.contains(.builtIn(.myTasks)))
        #expect(views.contains(.builtIn(.flagged)))
        #expect(views.contains(.builtIn(.pomodoro)))
        #expect(!views.contains(.builtIn(.review)))
    }

    @Test("Review stays in workflow search, not generic section search")
    func searchEntriesKeepReviewOutOfGenericSections() {
        let views = RootNavigationCatalog
            .searchableBuiltInEntries(pomodoroEnabled: true)
            .map(\.view)

        #expect(views.contains(.browse))
        #expect(views.contains(.builtIn(.inbox)))
        #expect(views.contains(.builtIn(.pomodoro)))
        #expect(!views.contains(.builtIn(.review)))
        #expect(RootWorkflowEntry.review.destinationView == .builtIn(.review))
    }
}
