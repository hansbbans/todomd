import XCTest
@testable import TodoMDCore

final class VoiceRambleParserTests: XCTestCase {
    func testParsesMultipleTasksWithMetadata() throws {
        let parser = VoiceRambleParser(
            calendar: Calendar(identifier: .gregorian),
            availableProjects: ["Launch Plan", "Errands"]
        )
        let reference = ISO8601DateFormatter().date(from: "2025-03-01T12:00:00Z")!

        let drafts = parser.parse(
            "Submit launch brief tomorrow at 3pm in Launch Plan priority one labels work and writing then buy milk in Errands",
            relativeTo: reference
        )

        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts[0].title, "Submit launch brief")
        XCTAssertEqual(drafts[0].due?.isoString, "2025-03-02")
        XCTAssertEqual(drafts[0].dueTime?.isoString, "15:00")
        XCTAssertEqual(drafts[0].project, "Launch Plan")
        XCTAssertEqual(drafts[0].priority, .high)
        XCTAssertEqual(drafts[0].tags, ["work", "writing"])
        XCTAssertEqual(drafts[1].title, "buy milk")
        XCTAssertEqual(drafts[1].project, "Errands")
    }

    func testSplitsRunOnTranscriptUsingPauses() throws {
        let parser = VoiceRambleParser(calendar: Calendar(identifier: .gregorian))
        let segments = [
            VoiceRambleSegment(text: "buy", startTime: 0.0, duration: 0.1),
            VoiceRambleSegment(text: "milk", startTime: 0.2, duration: 0.1),
            VoiceRambleSegment(text: "call", startTime: 1.4, duration: 0.1),
            VoiceRambleSegment(text: "mom", startTime: 1.6, duration: 0.1)
        ]

        let drafts = parser.parse("buy milk call mom", segments: segments)

        XCTAssertEqual(drafts.map(\.title), ["buy milk", "call mom"])
        XCTAssertGreaterThan(drafts[0].confidence, 0.8)
    }

    func testActuallyReplacesLastTaskAndRemoveDeletesIt() throws {
        let parser = VoiceRambleParser(calendar: Calendar(identifier: .gregorian))

        let replaced = parser.parse("buy milk. actually buy oat milk")
        XCTAssertEqual(replaced.count, 1)
        XCTAssertEqual(replaced[0].title, "buy oat milk")

        let removed = parser.parse("buy milk. remove that")
        XCTAssertTrue(removed.isEmpty)
    }

    func testTargetedCorrectionsAndMetadataOnlyRevision() throws {
        let parser = VoiceRambleParser(
            calendar: Calendar(identifier: .gregorian),
            availableProjects: ["Launch Plan"]
        )
        let reference = ISO8601DateFormatter().date(from: "2025-03-01T12:00:00Z")!

        let revised = parser.parse(
            "buy milk then review budget in Launch Plan urgent labels work then change the second one to call dad for mom then no, make that tomorrow then delete the first task",
            relativeTo: reference
        )

        XCTAssertEqual(revised.count, 1)
        XCTAssertEqual(revised[0].title, "call dad for mom")
        XCTAssertEqual(revised[0].due?.isoString, "2025-03-02")
        XCTAssertEqual(revised[0].project, "Launch Plan")
        XCTAssertEqual(revised[0].priority, .high)
        XCTAssertEqual(revised[0].tags, ["work"])
    }

    func testBroaderMetadataPhrasesAndSameProjectCarryForward() throws {
        let parser = VoiceRambleParser(
            calendar: Calendar(identifier: .gregorian),
            availableProjects: ["Launch Plan", "Errands"]
        )

        let drafts = parser.parse(
            "review budget for Launch Plan urgent half an hour then send recap same project as the last one"
        )

        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts[0].project, "Launch Plan")
        XCTAssertEqual(drafts[0].priority, .high)
        XCTAssertEqual(drafts[0].estimatedMinutes, 30)
        XCTAssertEqual(drafts[1].project, "Launch Plan")
    }

    func testFlagsAmbiguousSingleClause() throws {
        let parser = VoiceRambleParser(calendar: Calendar(identifier: .gregorian))

        let drafts = parser.parse("buy milk call mom send invoice")

        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].warning, "This may contain more than one task. Review before saving.")
        XCTAssertLessThan(drafts[0].confidence, 0.7)
    }

    func testParsesEstimatedMinutes() throws {
        let parser = VoiceRambleParser(calendar: Calendar(identifier: .gregorian))
        let reference = ISO8601DateFormatter().date(from: "2025-03-01T12:00:00Z")!

        let drafts = parser.parse("review budget tomorrow takes 45 minutes", relativeTo: reference)
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].title, "review budget")
        XCTAssertEqual(drafts[0].due?.isoString, "2025-03-02")
        XCTAssertEqual(drafts[0].estimatedMinutes, 45)
    }
}
