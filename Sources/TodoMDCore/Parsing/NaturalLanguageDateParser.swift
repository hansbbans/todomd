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

        if let nextWeekday = parseNextWeekday(lowered, relativeTo: referenceDate) {
            return localDate(from: nextWeekday)
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

    private func parseNextWeekday(_ lowered: String, relativeTo date: Date) -> Date? {
        let weekdays: [String: Int] = [
            "sunday": 1,
            "monday": 2,
            "tuesday": 3,
            "wednesday": 4,
            "thursday": 5,
            "friday": 6,
            "saturday": 7
        ]

        guard lowered.hasPrefix("next ") else { return nil }
        let dayName = lowered.replacingOccurrences(of: "next ", with: "")
        guard let targetWeekday = weekdays[dayName] else { return nil }

        var components = DateComponents()
        components.weekday = targetWeekday
        return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTimePreservingSmallerComponents)
    }

    private func parseAbsoluteDate(_ lowered: String, referenceDate: Date) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar

        // month day (e.g., march 1)
        formatter.dateFormat = "MMMM d"
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
