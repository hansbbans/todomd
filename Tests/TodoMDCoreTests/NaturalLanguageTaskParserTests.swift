import XCTest
@testable import TodoMDCore

final class NaturalLanguageTaskParserTests: XCTestCase {
    func testParsesByTomorrowAndTrailingTags() throws {
        let parser = NaturalLanguageTaskParser(calendar: Calendar(identifier: .gregorian))
        let reference = ISO8601DateFormatter().date(from: "2025-03-01T12:00:00Z")!

        let result = parser.parse("pay rent by tomorrow #finance #home", relativeTo: reference)
        XCTAssertEqual(result?.title, "pay rent")
        XCTAssertEqual(result?.due?.isoString, "2025-03-02")
        XCTAssertNil(result?.dueTime)
        XCTAssertEqual(result?.tags, ["finance", "home"])
    }

    func testParsesTrailingDatePhraseWithoutByKeyword() throws {
        let parser = NaturalLanguageTaskParser(calendar: Calendar(identifier: .gregorian))
        let reference = ISO8601DateFormatter().date(from: "2025-03-01T12:00:00Z")!

        let result = parser.parse("call daycare next wed", relativeTo: reference)
        XCTAssertEqual(result?.title, "call daycare")
        XCTAssertEqual(result?.due?.isoString, "2025-03-05")
        XCTAssertNil(result?.dueTime)
        XCTAssertEqual(result?.tags, [])
    }

    func testKeepsTitleWhenNoDatePhraseIsPresent() throws {
        let parser = NaturalLanguageTaskParser(calendar: Calendar(identifier: .gregorian))

        let result = parser.parse("read docs #work")
        XCTAssertEqual(result?.title, "read docs")
        XCTAssertNil(result?.due)
        XCTAssertNil(result?.dueTime)
        XCTAssertEqual(result?.tags, ["work"])
    }

    func testPreservesSentenceWhenOnlyDatePhraseIsEntered() throws {
        let parser = NaturalLanguageTaskParser(calendar: Calendar(identifier: .gregorian))
        let reference = ISO8601DateFormatter().date(from: "2025-03-01T12:00:00Z")!

        let result = parser.parse("tomorrow", relativeTo: reference)
        XCTAssertEqual(result?.title, "tomorrow")
        XCTAssertEqual(result?.due?.isoString, "2025-03-02")
        XCTAssertNil(result?.dueTime)
    }

    func testParsesDateAndTimeSuffix() throws {
        let parser = NaturalLanguageTaskParser(calendar: Calendar(identifier: .gregorian))
        let reference = ISO8601DateFormatter().date(from: "2025-03-01T12:00:00Z")!

        let result = parser.parse("join standup tomorrow at 3:15pm", relativeTo: reference)
        XCTAssertEqual(result?.title, "join standup")
        XCTAssertEqual(result?.due?.isoString, "2025-03-02")
        XCTAssertEqual(result?.dueTime?.isoString, "15:15")
    }

    func testParsesDueWeekdayPhrase() throws {
        let parser = NaturalLanguageTaskParser(calendar: Calendar(identifier: .gregorian))
        let reference = ISO8601DateFormatter().date(from: "2025-03-07T12:00:00Z")!

        let result = parser.parse("buy cookies due sunday", relativeTo: reference)
        XCTAssertEqual(result?.title, "buy cookies")
        XCTAssertEqual(result?.due?.isoString, "2025-03-09")
        XCTAssertNil(result?.dueTime)
        XCTAssertEqual(result?.recognizedDatePhrase, "due sunday")
    }

    func testParsesOrdinalMonthDayPhraseAndStripsItFromTitle() throws {
        let parser = NaturalLanguageTaskParser(calendar: Calendar(identifier: .gregorian))
        let reference = ISO8601DateFormatter().date(from: "2026-03-19T12:00:00Z")!

        let result = parser.parse("summer plans due april 1st", relativeTo: reference)
        XCTAssertEqual(result?.title, "summer plans")
        XCTAssertEqual(result?.due?.isoString, "2026-04-01")
        XCTAssertNil(result?.dueTime)
        XCTAssertEqual(result?.recognizedDatePhrase, "due april 1st")
    }

    func testParsesKnownProjectAndDueDate() throws {
        let parser = NaturalLanguageTaskParser(
            calendar: Calendar(identifier: .gregorian),
            availableProjects: ["Launch Plan", "Errands"]
        )
        let reference = ISO8601DateFormatter().date(from: "2025-03-01T12:00:00Z")!

        let result = parser.parse("submit brief in Launch Plan tomorrow", relativeTo: reference)
        XCTAssertEqual(result?.title, "submit brief")
        XCTAssertEqual(result?.project, "Launch Plan")
        XCTAssertEqual(result?.due?.isoString, "2025-03-02")
    }

    func testParsesTrailingProjectMention() throws {
        let parser = NaturalLanguageTaskParser(
            calendar: Calendar(identifier: .gregorian),
            availableProjects: ["Launch Plan", "Errands"]
        )

        let result = parser.parse("submit brief @Launch Plan")
        XCTAssertEqual(result?.title, "submit brief")
        XCTAssertEqual(result?.project, "Launch Plan")
        XCTAssertNil(result?.due)
    }
}
