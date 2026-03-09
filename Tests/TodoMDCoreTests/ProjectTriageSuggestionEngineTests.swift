import XCTest
@testable import TodoMDCore

final class ProjectTriageSuggestionEngineTests: XCTestCase {
    func testSuggestReturnsProjectAndMatchedKeywordsFromPersistedRules() {
        let engine = ProjectTriageSuggestionEngine()
        let record = makeRecord(
            path: "/tmp/inbox.md",
            title: "Prepare payroll for March",
            body: "Need payroll export and tax summary"
        )
        let rules = TriageRulesDocument(keywordProjectWeights: [
            "payroll": ["Finance": 4],
            "tax": ["Finance": 2],
            "summary": ["Reporting": 3]
        ])

        let suggestion = engine.suggest(
            for: record,
            availableProjects: ["Finance", "Reporting"],
            rules: rules
        )

        XCTAssertEqual(suggestion?.project, "Finance")
        XCTAssertEqual(suggestion?.matchedKeywords.map(\.keyword), ["payroll", "tax"])
    }

    func testSuggestBootstrapsFromExistingProjectTasksWhenRulesAreEmpty() {
        let engine = ProjectTriageSuggestionEngine()
        let bootstrap = [
            makeRecord(path: "/tmp/1.md", title: "Review sprint backlog", project: "Planning"),
            makeRecord(path: "/tmp/2.md", title: "Plan sprint goals", project: "Planning")
        ]
        let record = makeRecord(path: "/tmp/inbox.md", title: "Sprint backlog cleanup")

        let suggestion = engine.suggest(
            for: record,
            availableProjects: ["Planning"],
            rules: TriageRulesDocument(),
            bootstrapRecords: bootstrap
        )

        XCTAssertEqual(suggestion?.project, "Planning")
        XCTAssertNotNil(suggestion)
    }

    func testLearnAddsKeywordWeightsForAssignedProject() {
        let engine = ProjectTriageSuggestionEngine()
        var rules = TriageRulesDocument()
        let record = makeRecord(path: "/tmp/inbox.md", title: "Finalize launch checklist")

        engine.learn(rules: &rules, from: record, assignedProject: "Launch")

        XCTAssertEqual(rules.keywordProjectWeights["finalize"]?["Launch"], 1)
        XCTAssertEqual(rules.keywordProjectWeights["launch"]?["Launch"], 1)
        XCTAssertEqual(rules.keywordProjectWeights["checklist"]?["Launch"], 1)
    }

    private func makeRecord(
        path: String,
        title: String,
        body: String = "",
        project: String? = nil
    ) -> TaskRecord {
        var frontmatter = TestSupport.sampleFrontmatter(title: title)
        frontmatter.project = project
        let document = TaskDocument(frontmatter: frontmatter, body: body)
        return TaskRecord(identity: TaskFileIdentity(path: path), document: document)
    }
}
