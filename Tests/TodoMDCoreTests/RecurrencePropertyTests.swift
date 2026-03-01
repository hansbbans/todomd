import XCTest
@testable import TodoMDCore

// MARK: - Property-based test harness (local copy, mirrors CodecPropertyTests)

private func checkProperty(
    _ description: String,
    count: Int = 100,
    body: (inout any RandomNumberGenerator) throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) rethrows {
    var rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
    for iteration in 0..<count {
        do {
            try body(&rng)
        } catch {
            XCTFail(
                "Property '\(description)' failed on iteration \(iteration): \(error)",
                file: file,
                line: line
            )
            throw error
        }
    }
}

// MARK: - Generators

/// Generates a random valid `LocalDate` in 2000-01-01 … 2099-12-28.
/// Day is capped at 28 to avoid calendar-specific month-end issues.
private func arbitraryLocalDate(rng: inout any RandomNumberGenerator) -> LocalDate {
    let year = Int.random(in: 2000...2099, using: &rng)
    let month = Int.random(in: 1...12, using: &rng)
    let day = Int.random(in: 1...28, using: &rng)
    return (try? LocalDate(year: year, month: month, day: day)) ?? LocalDate.epoch
}

/// Valid BYDAY tokens understood by the recurrence engine.
private let weekdayTokens = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

/// Returns a random non-empty subset of `weekdayTokens`.
private func arbitraryByDay(rng: inout any RandomNumberGenerator) -> [String] {
    let count = Int.random(in: 1...weekdayTokens.count, using: &rng)
    var shuffled = weekdayTokens
    // Fisher-Yates using our rng
    for i in stride(from: shuffled.count - 1, through: 1, by: -1) {
        let j = Int.random(in: 0...i, using: &rng)
        shuffled.swapAt(i, j)
    }
    return Array(shuffled.prefix(count)).sorted()
}

/// Generates a random RRULE string for a given frequency.
private func arbitraryRRule(
    frequency: RecurrenceRule.Frequency,
    rng: inout any RandomNumberGenerator
) -> String {
    let interval = Int.random(in: 1...4, using: &rng)
    switch frequency {
    case .daily:
        return "FREQ=DAILY;INTERVAL=\(interval)"
    case .weekly:
        if Bool.random(using: &rng) {
            // With BYDAY
            let days = arbitraryByDay(rng: &rng).joined(separator: ",")
            return "FREQ=WEEKLY;INTERVAL=\(interval);BYDAY=\(days)"
        } else {
            return "FREQ=WEEKLY;INTERVAL=\(interval)"
        }
    case .monthly:
        return "FREQ=MONTHLY;INTERVAL=\(interval)"
    case .yearly:
        return "FREQ=YEARLY;INTERVAL=\(interval)"
    }
}

// MARK: - Tests

final class RecurrencePropertyTests: XCTestCase {

    private let service = RecurrenceService()

    // MARK: nextOccurrence is strictly after input

    /// For FREQ=DAILY, next occurrence must be strictly after the input date.
    func testDailyNextOccurrenceIsStrictlyAfterInput() throws {
        try checkProperty("DAILY: next > input") { rng in
            let start = arbitraryLocalDate(rng: &rng)
            let rule = arbitraryRRule(frequency: .daily, rng: &rng)
            let next = try self.service.nextOccurrence(after: start, rule: rule)
            XCTAssertGreaterThan(next, start, "DAILY next must be > input for rule: \(rule)")
        }
    }

    /// For FREQ=DAILY with interval=1, next occurrence is exactly +1 day.
    func testDailyIntervalOneIsExactlyOneDayAhead() throws {
        try checkProperty("DAILY interval=1 is +1 day", count: 50) { rng in
            let start = arbitraryLocalDate(rng: &rng)
            let next = try self.service.nextOccurrence(after: start, rule: "FREQ=DAILY")

            // Verify the difference is exactly 1 day by converting both to
            // a comparable numeric form (year * 10000 + month * 100 + day).
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(secondsFromGMT: 0)!
            guard
                let startDate = cal.date(from: DateComponents(
                    calendar: cal, timeZone: cal.timeZone, year: start.year, month: start.month, day: start.day
                )),
                let nextDate = cal.date(from: DateComponents(
                    calendar: cal, timeZone: cal.timeZone, year: next.year, month: next.month, day: next.day
                ))
            else {
                return
            }
            let diff = cal.dateComponents([.day], from: startDate, to: nextDate).day ?? 0
            XCTAssertEqual(diff, 1, "DAILY interval=1 must advance by exactly 1 day")
        }
    }

    /// For FREQ=WEEKLY (no BYDAY), next occurrence must be at least +7 days ahead.
    func testWeeklyNextOccurrenceIsAtLeastSevenDaysAhead() throws {
        try checkProperty("WEEKLY: next >= input + 7 days") { rng in
            let start = arbitraryLocalDate(rng: &rng)
            let rule = "FREQ=WEEKLY"
            let next = try self.service.nextOccurrence(after: start, rule: rule)

            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(secondsFromGMT: 0)!
            guard
                let startDate = cal.date(from: DateComponents(
                    calendar: cal, timeZone: cal.timeZone, year: start.year, month: start.month, day: start.day
                )),
                let nextDate = cal.date(from: DateComponents(
                    calendar: cal, timeZone: cal.timeZone, year: next.year, month: next.month, day: next.day
                ))
            else {
                return
            }
            let diff = cal.dateComponents([.day], from: startDate, to: nextDate).day ?? 0
            XCTAssertGreaterThanOrEqual(diff, 7, "WEEKLY next must be >= 7 days after input")
        }
    }

    /// For FREQ=WEEKLY with arbitrary BYDAY and interval, next is still after input.
    func testWeeklyWithByDayNextOccurrenceIsStrictlyAfterInput() throws {
        try checkProperty("WEEKLY+BYDAY: next > input") { rng in
            let start = arbitraryLocalDate(rng: &rng)
            let rule = arbitraryRRule(frequency: .weekly, rng: &rng)
            let next = try self.service.nextOccurrence(after: start, rule: rule)
            XCTAssertGreaterThan(next, start, "WEEKLY next must be > input for rule: \(rule)")
        }
    }

    /// For FREQ=MONTHLY, next occurrence must be in a strictly later month (or year).
    func testMonthlyNextOccurrenceIsInFutureMonth() throws {
        try checkProperty("MONTHLY: next month > start month") { rng in
            let start = arbitraryLocalDate(rng: &rng)
            let rule = arbitraryRRule(frequency: .monthly, rng: &rng)
            let next = try self.service.nextOccurrence(after: start, rule: rule)

            XCTAssertGreaterThan(next, start, "MONTHLY next must be > input for rule: \(rule)")

            // Verify that the next date's (year, month) is strictly later.
            let startMonthIndex = start.year * 12 + start.month
            let nextMonthIndex = next.year * 12 + next.month
            XCTAssertGreaterThan(
                nextMonthIndex,
                startMonthIndex,
                "MONTHLY next must be in a future month for rule: \(rule)"
            )
        }
    }

    /// For FREQ=YEARLY, next occurrence must be in a strictly later year.
    func testYearlyNextOccurrenceIsInFutureYear() throws {
        try checkProperty("YEARLY: next year > start year") { rng in
            let start = arbitraryLocalDate(rng: &rng)
            let rule = arbitraryRRule(frequency: .yearly, rng: &rng)
            let next = try self.service.nextOccurrence(after: start, rule: rule)
            XCTAssertGreaterThan(next, start, "YEARLY next must be > input for rule: \(rule)")
            XCTAssertGreaterThan(next.year, start.year, "YEARLY next must be in a future year for rule: \(rule)")
        }
    }

    // MARK: Parse round-trip

    /// Parsing a valid RRULE string, extracting its fields, serializing a new
    /// RRULE string from those fields, then parsing again must yield the same
    /// `RecurrenceRule` value.
    func testRuleParseRoundTrip() throws {
        let frequencies: [RecurrenceRule.Frequency] = [.daily, .weekly, .monthly, .yearly]

        try checkProperty("RecurrenceRule parse round-trip", count: 80) { rng in
            let freq = frequencies[Int.random(in: 0..<frequencies.count, using: &rng)]
            var rng2 = rng
            let originalRule = arbitraryRRule(frequency: freq, rng: &rng2)
            rng = rng2

            let parsed1 = try RecurrenceRule.parse(originalRule)

            // Re-serialise from the parsed fields.
            var rebuilt = "FREQ=\(parsed1.frequency.rawValue)"
            if parsed1.interval != 1 {
                rebuilt += ";INTERVAL=\(parsed1.interval)"
            }
            if !parsed1.byDay.isEmpty {
                rebuilt += ";BYDAY=\(parsed1.byDay.joined(separator: ","))"
            }

            let parsed2 = try RecurrenceRule.parse(rebuilt)

            XCTAssertEqual(parsed1.frequency, parsed2.frequency, "frequency must round-trip")
            XCTAssertEqual(parsed1.interval, parsed2.interval, "interval must round-trip")
            XCTAssertEqual(
                Set(parsed1.byDay),
                Set(parsed2.byDay),
                "BYDAY must round-trip (order-independent)"
            )
        }
    }

    // MARK: Monotonicity

    /// Applying `nextOccurrence` repeatedly must produce a strictly monotone sequence.
    func testNextOccurrenceIsMonotone() throws {
        let freqs: [RecurrenceRule.Frequency] = [.daily, .weekly, .monthly]

        try checkProperty("nextOccurrence is monotone", count: 50) { rng in
            let freqs2 = freqs
            let freq = freqs2[Int.random(in: 0..<freqs2.count, using: &rng)]
            let rule = "FREQ=\(freq.rawValue)"
            var current = arbitraryLocalDate(rng: &rng)

            for _ in 0..<5 {
                let next = try self.service.nextOccurrence(after: current, rule: rule)
                XCTAssertGreaterThan(
                    next,
                    current,
                    "Each successive nextOccurrence must be strictly greater than the previous for rule: \(rule)"
                )
                current = next
            }
        }
    }

    // MARK: Invalid RRULE rejection

    /// Strings that are not valid RRULEs must always throw at parse time.
    /// Only entries with a missing or unsupported FREQ value are tested here;
    /// cases where FREQ is valid but other tokens are bad are handled separately.
    func testInvalidRRuleAlwaysThrows() {
        // These should all fail at parse time (missing / unknown FREQ)
        let parseFailures = ["", "FREQ=HOURLY", "BYDAY=MO", "FREQ=", "INTERVAL=2", "FOO=BAR"]
        for raw in parseFailures {
            XCTAssertThrowsError(
                try RecurrenceRule.parse(raw),
                "Expected parse error for invalid RRULE: '\(raw)'"
            )
        }
    }
}
