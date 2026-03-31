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

    func testSavedRelativeWeekdayPerspectiveAdvancesWhenTodayChanges() throws {
        let parser = NaturalLanguagePerspectiveParser(calendar: Calendar(identifier: .gregorian))
        let creationDate = ISO8601DateFormatter().date(from: "2026-02-28T12:00:00Z")!
        let parsed = parser.parse("in project TL due by upcoming Friday", relativeTo: creationDate)

        var frontmatter = TestSupport.sampleFrontmatter(
            title: "Ship Friday build",
            due: try LocalDate(isoDate: "2026-03-13")
        )
        frontmatter.project = "Tl"
        let record = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/relative-friday.md"),
            document: .init(frontmatter: frontmatter, body: "")
        )

        XCTAssertTrue(
            engine.matches(
                record,
                perspective: PerspectiveDefinition(name: "Relative Friday", rules: parsed.rules),
                today: try LocalDate(isoDate: "2026-03-08")
            )
        )
    }

    func testCandidateSelectionUsesIndexedRelativeWeekdayDueByRule() throws {
        let parser = NaturalLanguagePerspectiveParser(calendar: Calendar(identifier: .gregorian))
        let creationDate = ISO8601DateFormatter().date(from: "2026-02-28T12:00:00Z")!
        let parsed = parser.parse("in project TL due by upcoming Friday", relativeTo: creationDate)

        var matchingFrontmatter = TestSupport.sampleFrontmatter(
            title: "Ship Friday build",
            due: try LocalDate(isoDate: "2026-03-13")
        )
        matchingFrontmatter.project = "Tl"
        let matchingRecord = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/relative-friday-by-match.md"),
            document: .init(frontmatter: matchingFrontmatter, body: "")
        )

        var laterFrontmatter = TestSupport.sampleFrontmatter(
            title: "Ship Saturday follow-up",
            due: try LocalDate(isoDate: "2026-03-14")
        )
        laterFrontmatter.project = "Tl"
        let laterRecord = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/relative-friday-by-later.md"),
            document: .init(frontmatter: laterFrontmatter, body: "")
        )

        let allRecords = [matchingRecord, laterRecord]
        let index = TaskMetadataIndex.build(from: allRecords)
        let perspective = PerspectiveDefinition(name: "Relative Friday", rules: parsed.rules)
        let today = try LocalDate(isoDate: "2026-03-08")

        let candidatePaths = try XCTUnwrap(
            engine.candidatePaths(for: perspective, using: index, today: today)
        )

        XCTAssertEqual(candidatePaths, Set([matchingRecord.identity.path]))

        let recordsByPath = Dictionary(uniqueKeysWithValues: allRecords.map { ($0.identity.path, $0) })
        let filtered = candidatePaths
            .compactMap { recordsByPath[$0] }
            .filter { engine.matches($0, perspective: perspective, today: today) }

        XCTAssertEqual(filtered.map(\.identity.path), [matchingRecord.identity.path])
    }

    func testCandidatePathsIndexesRelativeWeekdayDueOnRule() throws {
        let parser = NaturalLanguagePerspectiveParser(calendar: Calendar(identifier: .gregorian))
        let creationDate = ISO8601DateFormatter().date(from: "2026-02-28T12:00:00Z")!
        let parsed = parser.parse("in project TL due this upcoming Friday", relativeTo: creationDate)

        var matchingFrontmatter = TestSupport.sampleFrontmatter(
            title: "Ship Friday build",
            due: try LocalDate(isoDate: "2026-03-06")
        )
        matchingFrontmatter.project = "Tl"
        let matchingRecord = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/relative-friday-on-match.md"),
            document: .init(frontmatter: matchingFrontmatter, body: "")
        )

        var nonMatchingFrontmatter = TestSupport.sampleFrontmatter(
            title: "Ship Thursday build",
            due: try LocalDate(isoDate: "2026-03-05")
        )
        nonMatchingFrontmatter.project = "Tl"
        let nonMatchingRecord = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/relative-friday-on-nonmatch.md"),
            document: .init(frontmatter: nonMatchingFrontmatter, body: "")
        )

        let index = TaskMetadataIndex.build(from: [matchingRecord, nonMatchingRecord])

        XCTAssertEqual(
            engine.candidatePaths(
                for: PerspectiveDefinition(name: "Relative Friday", rules: parsed.rules),
                using: index,
                today: try LocalDate(isoDate: "2026-03-03")
            ),
            Set([matchingRecord.identity.path])
        )
    }

    func testIncompleteItemsDueThisUpcomingFridayIncludesOverdueRecords() throws {
        let parser = NaturalLanguagePerspectiveParser(calendar: Calendar(identifier: .gregorian))
        let creationDate = ISO8601DateFormatter().date(from: "2026-02-28T12:00:00Z")!
        let parsed = parser.parse("incomplete items in TL project due this upcoming Friday", relativeTo: creationDate)

        var overdueFrontmatter = TestSupport.sampleFrontmatter(
            title: "Overdue follow-up",
            due: try LocalDate(isoDate: "2026-03-05")
        )
        overdueFrontmatter.project = "Tl"
        let overdueRecord = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/relative-friday-overdue-match.md"),
            document: .init(frontmatter: overdueFrontmatter, body: "")
        )

        var fridayFrontmatter = TestSupport.sampleFrontmatter(
            title: "Friday deadline",
            due: try LocalDate(isoDate: "2026-03-06")
        )
        fridayFrontmatter.project = "Tl"
        let fridayRecord = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/relative-friday-on-match.md"),
            document: .init(frontmatter: fridayFrontmatter, body: "")
        )

        var laterFrontmatter = TestSupport.sampleFrontmatter(
            title: "Later follow-up",
            due: try LocalDate(isoDate: "2026-03-07")
        )
        laterFrontmatter.project = "Tl"
        let laterRecord = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/relative-friday-later.md"),
            document: .init(frontmatter: laterFrontmatter, body: "")
        )

        var completedFrontmatter = TestSupport.sampleFrontmatter(
            title: "Completed overdue",
            due: try LocalDate(isoDate: "2026-03-04")
        )
        completedFrontmatter.project = "Tl"
        completedFrontmatter.status = .done
        let completedRecord = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/relative-friday-completed.md"),
            document: .init(frontmatter: completedFrontmatter, body: "")
        )

        var cancelledFrontmatter = TestSupport.sampleFrontmatter(
            title: "Cancelled overdue",
            due: try LocalDate(isoDate: "2026-03-04")
        )
        cancelledFrontmatter.project = "Tl"
        cancelledFrontmatter.status = .cancelled
        let cancelledRecord = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/relative-friday-cancelled.md"),
            document: .init(frontmatter: cancelledFrontmatter, body: "")
        )

        let allRecords = [overdueRecord, fridayRecord, laterRecord, completedRecord, cancelledRecord]
        let index = TaskMetadataIndex.build(from: allRecords)
        let perspective = PerspectiveDefinition(name: "Friday Incomplete", rules: parsed.rules)
        let today = try LocalDate(isoDate: "2026-03-03")

        let candidatePaths = try XCTUnwrap(
            engine.candidatePaths(for: perspective, using: index, today: today)
        )

        XCTAssertEqual(
            candidatePaths,
            Set([overdueRecord.identity.path, fridayRecord.identity.path])
        )

        let recordsByPath = Dictionary(uniqueKeysWithValues: allRecords.map { ($0.identity.path, $0) })
        let filtered = candidatePaths
            .compactMap { recordsByPath[$0] }
            .filter { engine.matches($0, perspective: perspective, today: today) }

        XCTAssertEqual(
            Set(filtered.map(\.identity.path)),
            Set([overdueRecord.identity.path, fridayRecord.identity.path])
        )
    }

    func testShowMeAllIncompleteItemsLeadPhraseIncludesOverdueRecords() throws {
        let parser = NaturalLanguagePerspectiveParser(calendar: Calendar(identifier: .gregorian))
        let creationDate = ISO8601DateFormatter().date(from: "2026-02-28T12:00:00Z")!
        let parsed = parser.parse("show me all incomplete items in TL project due this upcoming Friday", relativeTo: creationDate)

        var overdueFrontmatter = TestSupport.sampleFrontmatter(
            title: "Overdue follow-up",
            due: try LocalDate(isoDate: "2026-03-05")
        )
        overdueFrontmatter.project = "Tl"
        let overdueRecord = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/relative-friday-show-overdue-match.md"),
            document: .init(frontmatter: overdueFrontmatter, body: "")
        )

        var fridayFrontmatter = TestSupport.sampleFrontmatter(
            title: "Friday deadline",
            due: try LocalDate(isoDate: "2026-03-06")
        )
        fridayFrontmatter.project = "Tl"
        let fridayRecord = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/relative-friday-show-on-match.md"),
            document: .init(frontmatter: fridayFrontmatter, body: "")
        )

        var laterFrontmatter = TestSupport.sampleFrontmatter(
            title: "Later follow-up",
            due: try LocalDate(isoDate: "2026-03-07")
        )
        laterFrontmatter.project = "Tl"
        let laterRecord = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/relative-friday-show-later.md"),
            document: .init(frontmatter: laterFrontmatter, body: "")
        )

        let allRecords = [overdueRecord, fridayRecord, laterRecord]
        let index = TaskMetadataIndex.build(from: allRecords)
        let perspective = PerspectiveDefinition(name: "Friday Incomplete Lead", rules: parsed.rules)
        let today = try LocalDate(isoDate: "2026-03-03")

        let candidatePaths = try XCTUnwrap(
            engine.candidatePaths(for: perspective, using: index, today: today)
        )

        XCTAssertEqual(
            candidatePaths,
            Set([overdueRecord.identity.path, fridayRecord.identity.path])
        )
    }

    func testExactDateNotDoneKeepsExactDueMatching() throws {
        let parser = NaturalLanguagePerspectiveParser(calendar: Calendar(identifier: .gregorian))
        let creationDate = ISO8601DateFormatter().date(from: "2026-02-28T12:00:00Z")!
        let parsed = parser.parse("anything in project TL due March 6 not done", relativeTo: creationDate)

        var exactOpenFrontmatter = TestSupport.sampleFrontmatter(
            title: "Open deadline",
            due: try LocalDate(isoDate: "2026-03-06")
        )
        exactOpenFrontmatter.project = "Tl"
        let exactOpenRecord = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/exact-not-done-open.md"),
            document: .init(frontmatter: exactOpenFrontmatter, body: "")
        )

        var exactDoneFrontmatter = TestSupport.sampleFrontmatter(
            title: "Done deadline",
            due: try LocalDate(isoDate: "2026-03-06")
        )
        exactDoneFrontmatter.project = "Tl"
        exactDoneFrontmatter.status = .done
        let exactDoneRecord = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/exact-not-done-done.md"),
            document: .init(frontmatter: exactDoneFrontmatter, body: "")
        )

        var earlierFrontmatter = TestSupport.sampleFrontmatter(
            title: "Earlier open",
            due: try LocalDate(isoDate: "2026-03-05")
        )
        earlierFrontmatter.project = "Tl"
        let earlierRecord = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/exact-not-done-earlier.md"),
            document: .init(frontmatter: earlierFrontmatter, body: "")
        )

        let allRecords = [exactOpenRecord, exactDoneRecord, earlierRecord]
        let index = TaskMetadataIndex.build(from: allRecords)
        let perspective = PerspectiveDefinition(name: "Exact Not Done", rules: parsed.rules)
        let today = try LocalDate(isoDate: "2026-03-03")

        let candidatePaths = try XCTUnwrap(
            engine.candidatePaths(for: perspective, using: index, today: today)
        )

        XCTAssertEqual(candidatePaths, Set([exactOpenRecord.identity.path]))

        let recordsByPath = Dictionary(uniqueKeysWithValues: allRecords.map { ($0.identity.path, $0) })
        let filtered = candidatePaths
            .compactMap { recordsByPath[$0] }
            .filter { engine.matches($0, perspective: perspective, today: today) }

        XCTAssertEqual(filtered.map(\.identity.path), [exactOpenRecord.identity.path])
    }

    func testProjectNamedIncompleteKeepsExactDueDateMatching() throws {
        let parser = NaturalLanguagePerspectiveParser(calendar: Calendar(identifier: .gregorian))
        let creationDate = ISO8601DateFormatter().date(from: "2026-02-28T12:00:00Z")!
        let parsed = parser.parse("in project Incomplete Migration due March 6", relativeTo: creationDate)

        var exactDoneFrontmatter = TestSupport.sampleFrontmatter(
            title: "Ship migration",
            due: try LocalDate(isoDate: "2026-03-06")
        )
        exactDoneFrontmatter.project = "Incomplete Migration"
        exactDoneFrontmatter.status = .done
        let exactDoneRecord = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/incomplete-migration-exact-done.md"),
            document: .init(frontmatter: exactDoneFrontmatter, body: "")
        )

        var exactOpenFrontmatter = TestSupport.sampleFrontmatter(
            title: "Open migration follow-up",
            due: try LocalDate(isoDate: "2026-03-06")
        )
        exactOpenFrontmatter.project = "Incomplete Migration"
        let exactOpenRecord = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/incomplete-migration-exact-open.md"),
            document: .init(frontmatter: exactOpenFrontmatter, body: "")
        )

        var earlierFrontmatter = TestSupport.sampleFrontmatter(
            title: "Earlier prep",
            due: try LocalDate(isoDate: "2026-03-05")
        )
        earlierFrontmatter.project = "Incomplete Migration"
        let earlierRecord = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/incomplete-migration-earlier.md"),
            document: .init(frontmatter: earlierFrontmatter, body: "")
        )

        let allRecords = [exactDoneRecord, exactOpenRecord, earlierRecord]
        let index = TaskMetadataIndex.build(from: allRecords)
        let perspective = PerspectiveDefinition(name: "Incomplete Migration March 6", rules: parsed.rules)
        let today = try LocalDate(isoDate: "2026-03-03")

        let candidatePaths = try XCTUnwrap(
            engine.candidatePaths(for: perspective, using: index, today: today)
        )

        XCTAssertEqual(
            candidatePaths,
            Set([exactDoneRecord.identity.path, exactOpenRecord.identity.path])
        )

        let recordsByPath = Dictionary(uniqueKeysWithValues: allRecords.map { ($0.identity.path, $0) })
        let filtered = candidatePaths
            .compactMap { recordsByPath[$0] }
            .filter { engine.matches($0, perspective: perspective, today: today) }

        XCTAssertEqual(
            Set(filtered.map(\.identity.path)),
            Set([exactDoneRecord.identity.path, exactOpenRecord.identity.path])
        )
    }

    func testProjectNamesContainingOrEndingWithIncompleteKeepExactDueDateMatching() throws {
        let parser = NaturalLanguagePerspectiveParser(calendar: Calendar(identifier: .gregorian))
        let creationDate = ISO8601DateFormatter().date(from: "2026-02-28T12:00:00Z")!
        let cases: [(query: String, project: String, prefix: String)] = [
            ("in project Incomplete due March 6", "Incomplete", "project-incomplete"),
            ("in project Migration Incomplete due March 6", "Migration Incomplete", "migration-incomplete")
        ]

        for testCase in cases {
            let parsed = parser.parse(testCase.query, relativeTo: creationDate)

            var exactDoneFrontmatter = TestSupport.sampleFrontmatter(
                title: "Exact done \(testCase.prefix)",
                due: try LocalDate(isoDate: "2026-03-06")
            )
            exactDoneFrontmatter.project = testCase.project
            exactDoneFrontmatter.status = .done
            let exactDoneRecord = TaskRecord(
                identity: TaskFileIdentity(path: "/tmp/\(testCase.prefix)-exact-done.md"),
                document: .init(frontmatter: exactDoneFrontmatter, body: "")
            )

            var exactOpenFrontmatter = TestSupport.sampleFrontmatter(
                title: "Exact open \(testCase.prefix)",
                due: try LocalDate(isoDate: "2026-03-06")
            )
            exactOpenFrontmatter.project = testCase.project
            let exactOpenRecord = TaskRecord(
                identity: TaskFileIdentity(path: "/tmp/\(testCase.prefix)-exact-open.md"),
                document: .init(frontmatter: exactOpenFrontmatter, body: "")
            )

            var earlierFrontmatter = TestSupport.sampleFrontmatter(
                title: "Earlier \(testCase.prefix)",
                due: try LocalDate(isoDate: "2026-03-05")
            )
            earlierFrontmatter.project = testCase.project
            let earlierRecord = TaskRecord(
                identity: TaskFileIdentity(path: "/tmp/\(testCase.prefix)-earlier.md"),
                document: .init(frontmatter: earlierFrontmatter, body: "")
            )

            let allRecords = [exactDoneRecord, exactOpenRecord, earlierRecord]
            let index = TaskMetadataIndex.build(from: allRecords)
            let perspective = PerspectiveDefinition(name: testCase.project, rules: parsed.rules)
            let today = try LocalDate(isoDate: "2026-03-03")

            let candidatePaths = try XCTUnwrap(
                engine.candidatePaths(for: perspective, using: index, today: today)
            )

            XCTAssertEqual(
                candidatePaths,
                Set([exactDoneRecord.identity.path, exactOpenRecord.identity.path]),
                testCase.query
            )

            let recordsByPath = Dictionary(uniqueKeysWithValues: allRecords.map { ($0.identity.path, $0) })
            let filtered = candidatePaths
                .compactMap { recordsByPath[$0] }
                .filter { engine.matches($0, perspective: perspective, today: today) }

            XCTAssertEqual(
                Set(filtered.map(\.identity.path)),
                Set([exactDoneRecord.identity.path, exactOpenRecord.identity.path]),
                testCase.query
            )
        }
    }

    func testMetadataValuesNamedIncompleteKeepExactDueDateMatching() throws {
        let parser = NaturalLanguagePerspectiveParser(calendar: Calendar(identifier: .gregorian))
        let creationDate = ISO8601DateFormatter().date(from: "2026-02-28T12:00:00Z")!

        let metadataCases: [(query: String, configure: (inout TaskFrontmatterV1) -> Void, prefix: String)] = [
            (
                "tagged incomplete due March 6",
                { $0.tags = ["incomplete"] },
                "tagged-incomplete"
            ),
            (
                "assigned to incomplete due March 6",
                { $0.assignee = "incomplete" },
                "assigned-incomplete"
            ),
            (
                "in projects Home and Incomplete due March 6",
                { $0.project = "Incomplete" },
                "projects-incomplete"
            )
        ]

        for testCase in metadataCases {
            let parsed = parser.parse(testCase.query, relativeTo: creationDate)

            var exactDoneFrontmatter = TestSupport.sampleFrontmatter(
                title: "Exact done \(testCase.prefix)",
                due: try LocalDate(isoDate: "2026-03-06")
            )
            testCase.configure(&exactDoneFrontmatter)
            exactDoneFrontmatter.status = .done
            let exactDoneRecord = TaskRecord(
                identity: TaskFileIdentity(path: "/tmp/\(testCase.prefix)-exact-done.md"),
                document: .init(frontmatter: exactDoneFrontmatter, body: "")
            )

            var exactOpenFrontmatter = TestSupport.sampleFrontmatter(
                title: "Exact open \(testCase.prefix)",
                due: try LocalDate(isoDate: "2026-03-06")
            )
            testCase.configure(&exactOpenFrontmatter)
            let exactOpenRecord = TaskRecord(
                identity: TaskFileIdentity(path: "/tmp/\(testCase.prefix)-exact-open.md"),
                document: .init(frontmatter: exactOpenFrontmatter, body: "")
            )

            var earlierFrontmatter = TestSupport.sampleFrontmatter(
                title: "Earlier \(testCase.prefix)",
                due: try LocalDate(isoDate: "2026-03-05")
            )
            testCase.configure(&earlierFrontmatter)
            let earlierRecord = TaskRecord(
                identity: TaskFileIdentity(path: "/tmp/\(testCase.prefix)-earlier.md"),
                document: .init(frontmatter: earlierFrontmatter, body: "")
            )

            let allRecords = [exactDoneRecord, exactOpenRecord, earlierRecord]
            let index = TaskMetadataIndex.build(from: allRecords)
            let perspective = PerspectiveDefinition(name: testCase.prefix, rules: parsed.rules)
            let today = try LocalDate(isoDate: "2026-03-03")

            let candidatePaths = try XCTUnwrap(
                engine.candidatePaths(for: perspective, using: index, today: today)
            )

            XCTAssertEqual(
                candidatePaths,
                Set([exactDoneRecord.identity.path, exactOpenRecord.identity.path]),
                testCase.query
            )

            let recordsByPath = Dictionary(uniqueKeysWithValues: allRecords.map { ($0.identity.path, $0) })
            let filtered = candidatePaths
                .compactMap { recordsByPath[$0] }
                .filter { engine.matches($0, perspective: perspective, today: today) }

            XCTAssertEqual(
                Set(filtered.map(\.identity.path)),
                Set([exactDoneRecord.identity.path, exactOpenRecord.identity.path]),
                testCase.query
            )
        }
    }

    func testAlternateOrderProjectStopsBeforeCompletedByProjectBotClause() throws {
        let parser = NaturalLanguagePerspectiveParser(calendar: Calendar(identifier: .gregorian))
        let creationDate = ISO8601DateFormatter().date(from: "2026-02-28T12:00:00Z")!
        let parsed = parser.parse("in TL project completed by project-bot due March 6", relativeTo: creationDate)

        var matchingFrontmatter = TestSupport.sampleFrontmatter(
            title: "Completed by project bot",
            due: try LocalDate(isoDate: "2026-03-06")
        )
        matchingFrontmatter.project = "Tl"
        matchingFrontmatter.status = .done
        matchingFrontmatter.completedBy = "project-bot"
        let matchingRecord = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/project-bot-match.md"),
            document: .init(frontmatter: matchingFrontmatter, body: "")
        )

        var wrongProjectFrontmatter = TestSupport.sampleFrontmatter(
            title: "Wrong project",
            due: try LocalDate(isoDate: "2026-03-06")
        )
        wrongProjectFrontmatter.project = "Tl Project Completed By"
        wrongProjectFrontmatter.status = .done
        wrongProjectFrontmatter.completedBy = "project-bot"
        let wrongProjectRecord = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/project-bot-wrong-project.md"),
            document: .init(frontmatter: wrongProjectFrontmatter, body: "")
        )

        let allRecords = [matchingRecord, wrongProjectRecord]
        let index = TaskMetadataIndex.build(from: allRecords)
        let perspective = PerspectiveDefinition(name: "Project Bot Completion", rules: parsed.rules)
        let today = try LocalDate(isoDate: "2026-03-03")

        let candidatePaths = try XCTUnwrap(
            engine.candidatePaths(for: perspective, using: index, today: today)
        )

        XCTAssertEqual(candidatePaths, Set([matchingRecord.identity.path]))

        let recordsByPath = Dictionary(uniqueKeysWithValues: allRecords.map { ($0.identity.path, $0) })
        let filtered = candidatePaths
            .compactMap { recordsByPath[$0] }
            .filter { engine.matches($0, perspective: perspective, today: today) }

        XCTAssertEqual(filtered.map(\.identity.path), [matchingRecord.identity.path])
    }

    func testCandidateSelectionUsesIndexedNegatedRelativeWeekdayRule() throws {
        let perspective = PerspectiveDefinition(
            name: "Not Due By Upcoming Friday",
            rules: PerspectiveRuleGroup(
                operator: .not,
                conditions: [
                    .rule(PerspectiveRule(
                        field: .due,
                        operator: .onOrBefore,
                        jsonValue: .object([
                            "op": .string("date_phrase"),
                            "phrase": .string("upcoming friday")
                        ])
                    ))
                ]
            )
        )

        let excludedRecord = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/relative-friday-not-excluded.md"),
            document: .init(frontmatter: TestSupport.sampleFrontmatter(due: try LocalDate(isoDate: "2026-03-13")), body: "")
        )

        let includedRecord = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/relative-friday-not-included.md"),
            document: .init(frontmatter: TestSupport.sampleFrontmatter(due: try LocalDate(isoDate: "2026-03-14")), body: "")
        )

        let allRecords = [excludedRecord, includedRecord]
        let index = TaskMetadataIndex.build(from: allRecords)
        let today = try LocalDate(isoDate: "2026-03-08")

        let candidatePaths = try XCTUnwrap(
            engine.candidatePaths(for: perspective, using: index, today: today)
        )

        XCTAssertEqual(candidatePaths, Set([includedRecord.identity.path]))

        let recordsByPath = Dictionary(uniqueKeysWithValues: allRecords.map { ($0.identity.path, $0) })
        let filtered = candidatePaths
            .compactMap { recordsByPath[$0] }
            .filter { engine.matches($0, perspective: perspective, today: today) }

        XCTAssertEqual(filtered.map(\.identity.path), [includedRecord.identity.path])
    }

    func testRelativeWeekdayRuleStaysLiveAfterStringValueRoundTrip() throws {
        var rule = PerspectiveRule(
            field: .due,
            operator: .onOrBefore,
            jsonValue: .object([
                "op": .string("date_phrase"),
                "phrase": .string("upcoming friday")
            ])
        )

        XCTAssertEqual(rule.stringValue, "upcoming friday")
        rule.stringValue = rule.stringValue
        XCTAssertEqual(
            rule.value,
            .object([
                "op": .string("date_phrase"),
                "phrase": .string("upcoming friday")
            ])
        )

        let record = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/relative-friday-roundtrip.md"),
            document: .init(frontmatter: TestSupport.sampleFrontmatter(due: try LocalDate(isoDate: "2026-03-13")), body: "")
        )

        XCTAssertTrue(engine.matchesRule(record, rule: rule, today: try LocalDate(isoDate: "2026-03-08")))
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

    func testAssigneeCompletedByAndBlockedByFields() throws {
        var frontmatter = TestSupport.sampleFrontmatter(title: "Task")
        frontmatter.assignee = "codex"
        frontmatter.completedBy = "codex"
        frontmatter.blockedBy = .refs(["t-1234"])
        frontmatter.ref = "t-abcd"
        let record = TaskRecord(identity: TaskFileIdentity(path: "/tmp/fields.md"), document: .init(frontmatter: frontmatter, body: ""))

        let perspective = PerspectiveDefinition(
            name: "Fields",
            rules: PerspectiveRuleGroup(
                operator: .and,
                conditions: [
                    .rule(PerspectiveRule(field: .assignee, operator: .equals, value: "codex")),
                    .rule(PerspectiveRule(field: .completedBy, operator: .equals, value: "codex")),
                    .rule(PerspectiveRule(field: .blockedBy, operator: .contains, value: "t-1234")),
                    .rule(PerspectiveRule(field: .ref, operator: .equals, value: "t-abcd"))
                ]
            )
        )

        XCTAssertTrue(engine.matches(record, perspective: perspective, today: try LocalDate(isoDate: "2025-03-03")))
    }

    func testIsolatedProjectNameReturnsSingleProjectFromEqualsRule() {
        let perspective = PerspectiveDefinition(
            name: "Home",
            rules: PerspectiveRuleGroup(
                operator: .and,
                conditions: [
                    .rule(PerspectiveRule(field: .project, operator: .equals, value: "Home")),
                    .rule(PerspectiveRule(field: .status, operator: .equals, value: TaskStatus.todo.rawValue))
                ]
            )
        )

        XCTAssertEqual(perspective.isolatedProjectName, "Home")
    }

    func testIsolatedProjectNameCollapsesIntersectionToSingleProject() {
        let perspective = PerspectiveDefinition(
            name: "Home Only",
            rules: PerspectiveRuleGroup(
                operator: .and,
                conditions: [
                    .rule(PerspectiveRule(field: .project, operator: .in, jsonValue: .array([.string("Home"), .string("Work")]))),
                    .rule(PerspectiveRule(field: .project, operator: .equals, value: "Home"))
                ]
            )
        )

        XCTAssertEqual(perspective.isolatedProjectName, "Home")
    }

    func testIsolatedProjectNameReturnsNilForMultiProjectPerspective() {
        let perspective = PerspectiveDefinition(
            name: "Multiple Projects",
            rules: PerspectiveRuleGroup(
                operator: .or,
                conditions: [
                    .rule(PerspectiveRule(field: .project, operator: .equals, value: "Home")),
                    .rule(PerspectiveRule(field: .project, operator: .equals, value: "Work"))
                ]
            )
        )

        XCTAssertNil(perspective.isolatedProjectName)
    }
}
