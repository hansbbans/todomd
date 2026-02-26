import Foundation

public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case todo
    case inProgress = "in-progress"
    case done
    case cancelled
    case someday
}

public enum TaskPriority: String, Codable, CaseIterable, Sendable {
    case none
    case low
    case medium
    case high
}

public struct LocalDate: Codable, Hashable, Sendable, Comparable {
    public let year: Int
    public let month: Int
    public let day: Int

    private init(uncheckedYear: Int, month: Int, day: Int) {
        self.year = uncheckedYear
        self.month = month
        self.day = day
    }

    public static let epoch = LocalDate(uncheckedYear: 1970, month: 1, day: 1)

    public static func today(in calendar: Calendar = .current) -> LocalDate {
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        return (try? LocalDate(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1))
            ?? .epoch
    }

    public init(year: Int, month: Int, day: Int) throws {
        guard (1...12).contains(month) else { throw LocalDateError.invalidMonth(month) }
        guard (1...31).contains(day) else { throw LocalDateError.invalidDay(day) }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.calendar = Calendar(identifier: .gregorian)

        guard components.date != nil else {
            throw LocalDateError.invalidCombination(year: year, month: month, day: day)
        }

        self.year = year
        self.month = month
        self.day = day
    }

    public init(isoDate: String) throws {
        let pieces = isoDate.split(separator: "-")
        guard pieces.count == 3,
              let year = Int(pieces[0]),
              let month = Int(pieces[1]),
              let day = Int(pieces[2]) else {
            throw LocalDateError.invalidFormat(isoDate)
        }

        try self.init(year: year, month: month, day: day)
    }

    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }
}

public enum LocalDateError: Error, Equatable, Sendable {
    case invalidFormat(String)
    case invalidMonth(Int)
    case invalidDay(Int)
    case invalidCombination(year: Int, month: Int, day: Int)
}

public struct DateCoding {
    private static func makeFractionalFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    private static func makeNonFractionalFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    public static func encode(_ date: Date) -> String {
        makeFractionalFormatter().string(from: date)
    }

    public static func decode(_ raw: String) -> Date? {
        makeFractionalFormatter().date(from: raw) ?? makeNonFractionalFormatter().date(from: raw)
    }
}
