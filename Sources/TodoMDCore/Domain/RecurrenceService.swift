import Foundation

public struct RecurrenceRule: Equatable, Sendable {
    public enum Frequency: String, Equatable, Sendable {
        case daily = "DAILY"
        case weekly = "WEEKLY"
        case monthly = "MONTHLY"
        case yearly = "YEARLY"
    }

    public let frequency: Frequency
    public let interval: Int
    public let byDay: [String]

    public init(frequency: Frequency, interval: Int = 1, byDay: [String] = []) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.byDay = byDay
    }

    public static func parse(_ raw: String) throws -> RecurrenceRule {
        var fields: [String: String] = [:]
        for item in raw.split(separator: ";") {
            let parts = item.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            fields[String(parts[0]).uppercased()] = String(parts[1]).uppercased()
        }

        guard let freqRaw = fields["FREQ"], let frequency = Frequency(rawValue: freqRaw) else {
            throw TaskError.recurrenceFailure("RRULE is missing supported FREQ")
        }

        let interval = Int(fields["INTERVAL"] ?? "1") ?? 1
        let byDay = fields["BYDAY"]?.split(separator: ",").map(String.init) ?? []

        return RecurrenceRule(frequency: frequency, interval: interval, byDay: byDay)
    }
}

public struct RecurrenceService {
    public var calendar: Calendar

    public init(calendar: Calendar = Calendar(identifier: .gregorian)) {
        var configured = calendar
        configured.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        self.calendar = configured
    }

    public func nextOccurrence(after current: LocalDate, rule: String) throws -> LocalDate {
        let parsedRule = try RecurrenceRule.parse(rule)

        switch parsedRule.frequency {
        case .daily:
            return try addDays(parsedRule.interval, to: current)
        case .weekly:
            if parsedRule.byDay.isEmpty {
                return try addDays(7 * parsedRule.interval, to: current)
            }
            return try nextWeeklyByDay(after: current, interval: parsedRule.interval, byDay: parsedRule.byDay)
        case .monthly:
            return try addMonths(parsedRule.interval, to: current)
        case .yearly:
            return try addYears(parsedRule.interval, to: current)
        }
    }

    private func nextWeeklyByDay(after date: LocalDate, interval: Int, byDay: [String]) throws -> LocalDate {
        let targetWeekdays = Set(byDay.compactMap(weekdayNumber(from:)))
        guard !targetWeekdays.isEmpty else {
            throw TaskError.recurrenceFailure("BYDAY values are invalid")
        }

        guard
            let startDate = toDate(date),
            let anchorWeekStart = calendar.dateInterval(of: .weekOfYear, for: startDate)?.start
        else {
            throw TaskError.recurrenceFailure("Cannot convert LocalDate")
        }

        let normalizedInterval = max(interval, 1)
        let maxOffset = (7 * normalizedInterval) + 7
        for offset in 1...maxOffset {
            guard let candidateDate = calendar.date(byAdding: .day, value: offset, to: startDate) else { continue }
            let weekday = calendar.component(.weekday, from: candidateDate)
            guard targetWeekdays.contains(weekday) else { continue }

            guard let candidateWeekStart = calendar.dateInterval(of: .weekOfYear, for: candidateDate)?.start else { continue }
            let dayDelta = calendar.dateComponents([.day], from: anchorWeekStart, to: candidateWeekStart).day ?? 0
            guard dayDelta >= 0, dayDelta % 7 == 0 else { continue }

            let weeksSinceAnchor = dayDelta / 7
            guard weeksSinceAnchor % normalizedInterval == 0 else { continue }

            if let local = toLocalDate(candidateDate) {
                return local
            }
        }

        throw TaskError.recurrenceFailure("Failed to compute next weekly occurrence")
    }

    private func weekdayNumber(from token: String) -> Int? {
        switch token {
        case "SU": return 1
        case "MO": return 2
        case "TU": return 3
        case "WE": return 4
        case "TH": return 5
        case "FR": return 6
        case "SA": return 7
        default: return nil
        }
    }

    private func addDays(_ value: Int, to localDate: LocalDate) throws -> LocalDate {
        guard let start = toDate(localDate), let result = calendar.date(byAdding: .day, value: value, to: start), let local = toLocalDate(result) else {
            throw TaskError.recurrenceFailure("Failed to add days")
        }
        return local
    }

    private func addMonths(_ value: Int, to localDate: LocalDate) throws -> LocalDate {
        guard let start = toDate(localDate), let result = calendar.date(byAdding: .month, value: value, to: start), let local = toLocalDate(result) else {
            throw TaskError.recurrenceFailure("Failed to add months")
        }
        return local
    }

    private func addYears(_ value: Int, to localDate: LocalDate) throws -> LocalDate {
        guard let start = toDate(localDate), let result = calendar.date(byAdding: .year, value: value, to: start), let local = toLocalDate(result) else {
            throw TaskError.recurrenceFailure("Failed to add years")
        }
        return local
    }

    private func toDate(_ localDate: LocalDate) -> Date? {
        var components = DateComponents()
        components.year = localDate.year
        components.month = localDate.month
        components.day = localDate.day
        components.calendar = calendar
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return components.date
    }

    private func toLocalDate(_ date: Date) -> LocalDate? {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        return try? LocalDate(year: year, month: month, day: day)
    }

    public static func humanReadableDescription(for rule: String) -> String? {
        guard let parsed = try? RecurrenceRule.parse(rule) else { return nil }
        let interval = parsed.interval

        switch parsed.frequency {
        case .daily:
            return interval == 1 ? "Every day" : "Every \(interval) days"
        case .weekly:
            if parsed.byDay.isEmpty {
                return interval == 1 ? "Every week" : "Every \(interval) weeks"
            }
            let dayMap: [String: String] = [
                "MO": "Mon", "TU": "Tue", "WE": "Wed", "TH": "Thu",
                "FR": "Fri", "SA": "Sat", "SU": "Sun"
            ]
            let orderedDays = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
            let dayNames = orderedDays
                .filter { parsed.byDay.contains($0) }
                .compactMap { dayMap[$0] }
                .joined(separator: ", ")
            let weekPart = interval == 1 ? "week" : "\(interval) weeks"
            return "Every \(weekPart) on \(dayNames)"
        case .monthly:
            return interval == 1 ? "Every month" : "Every \(interval) months"
        case .yearly:
            return interval == 1 ? "Every year" : "Every \(interval) years"
        }
    }
}
