import Foundation

public struct NaturalLanguageDateParser {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func parse(_ phrase: String, relativeTo referenceDate: Date = Date()) -> LocalDate? {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()

        if lowered == "today" {
            return localDate(from: referenceDate)
        }

        if lowered == "tomorrow", let date = calendar.date(byAdding: .day, value: 1, to: referenceDate) {
            return localDate(from: date)
        }

        if lowered == "yesterday", let date = calendar.date(byAdding: .day, value: -1, to: referenceDate) {
            return localDate(from: date)
        }

        if let inDays = parseInDays(lowered), let date = calendar.date(byAdding: .day, value: inDays, to: referenceDate) {
            return localDate(from: date)
        }

        if let weekday = parseWeekdayPhrase(lowered, relativeTo: referenceDate) {
            return localDate(from: weekday)
        }

        if let absolute = parseAbsoluteDate(lowered, referenceDate: referenceDate) {
            return localDate(from: absolute)
        }

        return nil
    }

    private func parseInDays(_ lowered: String) -> Int? {
        let pattern = #"^in\s+(\d+)\s+days?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: lowered.utf16.count)
        guard let match = regex.firstMatch(in: lowered, options: [], range: range),
              let numberRange = Range(match.range(at: 1), in: lowered) else {
            return nil
        }
        return Int(lowered[numberRange])
    }

    private func parseWeekdayPhrase(_ lowered: String, relativeTo date: Date) -> Date? {
        let weekdays: [String: Int] = [
            "sun": 1,
            "sunday": 1,
            "mon": 2,
            "monday": 2,
            "tue": 3,
            "tues": 3,
            "tuesday": 3,
            "wed": 4,
            "weds": 4,
            "wednesday": 4,
            "thu": 5,
            "thur": 5,
            "thurs": 5,
            "thursday": 5,
            "fri": 6,
            "friday": 6,
            "sat": 7,
            "saturday": 7
        ]

        let tokens = lowered.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return nil }

        let targetWeekday: Int
        let strictFuture: Bool
        if tokens.count == 1, let bare = weekdays[tokens[0]] {
            targetWeekday = bare
            strictFuture = false
        } else if tokens.count == 2, let weekday = weekdays[tokens[1]] {
            switch tokens[0] {
            case "next":
                targetWeekday = weekday
                strictFuture = true
            case "this":
                targetWeekday = weekday
                strictFuture = false
            default:
                return nil
            }
        } else {
            return nil
        }

        let currentWeekday = calendar.component(.weekday, from: date)
        var dayOffset = (targetWeekday - currentWeekday + 7) % 7
        if strictFuture, dayOffset == 0 {
            dayOffset = 7
        }

        return calendar.date(byAdding: .day, value: dayOffset, to: date)
    }

    private func parseAbsoluteDate(_ lowered: String, referenceDate: Date) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar

        for format in ["MMMM d", "MMM d"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: lowered) {
                var year = calendar.component(.year, from: referenceDate)
                var components = calendar.dateComponents([.month, .day], from: date)
                components.year = year
                guard let candidate = calendar.date(from: components) else { return nil }
                if candidate < referenceDate {
                    year += 1
                    components.year = year
                    return calendar.date(from: components)
                }
                return candidate
            }
        }

        // yyyy-mm-dd
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: lowered)
    }

    private func localDate(from date: Date) -> LocalDate? {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return nil
        }
        return try? LocalDate(year: year, month: month, day: day)
    }
}
