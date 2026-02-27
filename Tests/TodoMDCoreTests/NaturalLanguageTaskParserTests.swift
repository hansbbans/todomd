import XCTest
@testable import TodoMDCore

final class NaturalLanguageTaskParserTests: XCTestCase {
    func testParsesByTomorrowAndTrailingTags() throws {
        let parser = NaturalLanguageTaskParser(calendar: Calendar(identifier: .gregorian))
        let reference = ISO8601DateFormatter().date(from: "2025-03-01T12:00:00Z")!

        let result = parser.parse("pay rent by tomorrow #finance #home", relativeTo: reference)
        XCTAssertEqual(result?.title, "pay rent")
        XCTAssertEqual(result?.due?.isoString, "2025-03-02")
        XCTAssertEqual(result?.tags, ["finance", "home"])
    }

    func testParsesTrailingDatePhraseWithoutByKeyword() throws {
        let parser = NaturalLanguageTaskParser(calendar: Calendar(identifier: .gregorian))
        let reference = ISO8601DateFormatter().date(from: "2025-03-01T12:00:00Z")!

        let result = parser.parse("call daycare next wed", relativeTo: reference)
        XCTAssertEqual(result?.title, "call daycare")
        XCTAssertEqual(result?.due?.isoString, "2025-03-05")
        XCTAssertEqual(result?.tags, [])
    }

    func testKeepsTitleWhenNoDatePhraseIsPresent() throws {
        let parser = NaturalLanguageTaskParser(calendar: Calendar(identifier: .gregorian))

        let result = parser.parse("read docs #work")
        XCTAssertEqual(result?.title, "read docs")
        XCTAssertNil(result?.due)
        XCTAssertEqual(result?.tags, ["work"])
    }

    func testPreservesSentenceWhenOnlyDatePhraseIsEntered() throws {
        let parser = NaturalLanguageTaskParser(calendar: Calendar(identifier: .gregorian))
        let reference = ISO8601DateFormatter().date(from: "2025-03-01T12:00:00Z")!

        let result = parser.parse("tomorrow", relativeTo: reference)
        XCTAssertEqual(result?.title, "tomorrow")
        XCTAssertEqual(result?.due?.isoString, "2025-03-02")
    }
}
