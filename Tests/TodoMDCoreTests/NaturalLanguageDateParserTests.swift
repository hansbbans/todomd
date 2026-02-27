import XCTest
@testable import TodoMDCore

final class NaturalLanguageDateParserTests: XCTestCase {
    func testTomorrowParsing() throws {
        let parser = NaturalLanguageDateParser(calendar: Calendar(identifier: .gregorian))
        let reference = ISO8601DateFormatter().date(from: "2025-03-01T12:00:00Z")!
        XCTAssertEqual(parser.parse("tomorrow", relativeTo: reference)?.isoString, "2025-03-02")
    }

    func testNextFridayParsing() throws {
        let parser = NaturalLanguageDateParser(calendar: Calendar(identifier: .gregorian))
        let reference = ISO8601DateFormatter().date(from: "2025-03-01T12:00:00Z")! // Saturday
        XCTAssertEqual(parser.parse("next friday", relativeTo: reference)?.isoString, "2025-03-07")
    }

    func testBareWeekdayParsing() throws {
        let parser = NaturalLanguageDateParser(calendar: Calendar(identifier: .gregorian))
        let reference = ISO8601DateFormatter().date(from: "2025-03-01T12:00:00Z")! // Saturday
        XCTAssertEqual(parser.parse("friday", relativeTo: reference)?.isoString, "2025-03-07")
    }

    func testThisWeekdayParsing() throws {
        let parser = NaturalLanguageDateParser(calendar: Calendar(identifier: .gregorian))
        let reference = ISO8601DateFormatter().date(from: "2025-03-03T12:00:00Z")! // Monday
        XCTAssertEqual(parser.parse("this friday", relativeTo: reference)?.isoString, "2025-03-07")
    }

    func testBareWeekdayCanResolveToToday() throws {
        let parser = NaturalLanguageDateParser(calendar: Calendar(identifier: .gregorian))
        let reference = ISO8601DateFormatter().date(from: "2025-03-07T12:00:00Z")! // Friday
        XCTAssertEqual(parser.parse("friday", relativeTo: reference)?.isoString, "2025-03-07")
    }

    func testInThreeDaysParsing() throws {
        let parser = NaturalLanguageDateParser(calendar: Calendar(identifier: .gregorian))
        let reference = ISO8601DateFormatter().date(from: "2025-03-01T12:00:00Z")!
        XCTAssertEqual(parser.parse("in 3 days", relativeTo: reference)?.isoString, "2025-03-04")
    }

    func testAbsoluteDateParsing() throws {
        let parser = NaturalLanguageDateParser(calendar: Calendar(identifier: .gregorian))
        let reference = ISO8601DateFormatter().date(from: "2025-02-01T12:00:00Z")!
        XCTAssertEqual(parser.parse("march 1", relativeTo: reference)?.isoString, "2025-03-01")
    }
}
