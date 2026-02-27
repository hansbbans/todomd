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

public struct LocalTime: Codable, Hashable, Sendable, Comparable {
    public let hour: Int
    public let minute: Int

    private init(uncheckedHour: Int, minute: Int) {
        self.hour = uncheckedHour
        self.minute = minute
    }

    public static let midnight = LocalTime(uncheckedHour: 0, minute: 0)

    public init(hour: Int, minute: Int) throws {
        guard (0...23).contains(hour) else { throw LocalTimeError.invalidHour(hour) }
        guard (0...59).contains(minute) else { throw LocalTimeError.invalidMinute(minute) }
        self.hour = hour
        self.minute = minute
    }

    public init(isoTime: String) throws {
        let pieces = isoTime.split(separator: ":")
        guard pieces.count == 2,
              let hour = Int(pieces[0]),
              let minute = Int(pieces[1]) else {
            throw LocalTimeError.invalidFormat(isoTime)
        }
        try self.init(hour: hour, minute: minute)
    }

    public var isoString: String {
        String(format: "%02d:%02d", hour, minute)
    }

    public static func < (lhs: LocalTime, rhs: LocalTime) -> Bool {
        if lhs.hour != rhs.hour {
            return lhs.hour < rhs.hour
        }
        return lhs.minute < rhs.minute
    }
}

public enum LocalTimeError: Error, Equatable, Sendable {
    case invalidFormat(String)
    case invalidHour(Int)
    case invalidMinute(Int)
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
