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

    func testActuallyReplacesLastTaskAndRemoveDeletesIt() throws {
        let parser = VoiceRambleParser(calendar: Calendar(identifier: .gregorian))

        let replaced = parser.parse("buy milk. actually buy oat milk")
        XCTAssertEqual(replaced.count, 1)
        XCTAssertEqual(replaced[0].title, "buy oat milk")

        let removed = parser.parse("buy milk. remove that")
        XCTAssertTrue(removed.isEmpty)
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
