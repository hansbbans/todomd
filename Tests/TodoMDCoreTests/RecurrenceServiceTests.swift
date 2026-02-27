import XCTest
@testable import TodoMDCore

final class RecurrenceServiceTests: XCTestCase {
    func testDailyRecurrence() throws {
        let service = RecurrenceService()
        let start = try LocalDate(isoDate: "2025-03-01")
        let next = try service.nextOccurrence(after: start, rule: "FREQ=DAILY")
        XCTAssertEqual(next.isoString, "2025-03-02")
    }

    func testWeeklyByDayRecurrence() throws {
        let service = RecurrenceService()
        let start = try LocalDate(isoDate: "2025-03-01") // Saturday
        let next = try service.nextOccurrence(after: start, rule: "FREQ=WEEKLY;BYDAY=MO")
        XCTAssertEqual(next.isoString, "2025-03-03")
    }

    func testWeeklyByDayRespectsInterval() throws {
        let service = RecurrenceService()
        let start = try LocalDate(isoDate: "2025-03-03") // Monday
        let next = try service.nextOccurrence(after: start, rule: "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO")
        XCTAssertEqual(next.isoString, "2025-03-17")
    }

    func testWeeklyByDayAllowsLaterDaysInSameWeek() throws {
        let service = RecurrenceService()
        let start = try LocalDate(isoDate: "2025-03-03") // Monday
        let next = try service.nextOccurrence(after: start, rule: "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE")
        XCTAssertEqual(next.isoString, "2025-03-05")
    }

    func testMonthlyRecurrenceEndOfMonth() throws {
        let service = RecurrenceService()
        let start = try LocalDate(isoDate: "2025-01-31")
        let next = try service.nextOccurrence(after: start, rule: "FREQ=MONTHLY")
        XCTAssertEqual(next.isoString, "2025-02-28")
    }

    func testYearlyLeapYearEdge() throws {
        let service = RecurrenceService()
        let start = try LocalDate(isoDate: "2024-02-29")
        let next = try service.nextOccurrence(after: start, rule: "FREQ=YEARLY")
        XCTAssertEqual(next.isoString, "2025-02-28")
    }
}
