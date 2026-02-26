import Foundation

public struct TaskFilenameGenerator {
    public var nowProvider: @Sendable () -> Date

    public init(nowProvider: @escaping @Sendable () -> Date = Date.init) {
        self.nowProvider = nowProvider
    }

    public func generate(title: String, existingFilenames: Set<String>) -> String {
        let timestamp = utcTimestampString(from: nowProvider())
        let slug = slugify(title: title)
        let base = "\(timestamp)-\(slug)"

        if !existingFilenames.contains("\(base).md") {
            return "\(base).md"
        }

        var suffix = 2
        while existingFilenames.contains("\(base)-\(suffix).md") {
            suffix += 1
        }
        return "\(base)-\(suffix).md"
    }

    public func slugify(title: String) -> String {
        let lowered = title.lowercased()
        let replaced = lowered.replacingOccurrences(
            of: "[^a-z0-9]+",
            with: "-",
            options: .regularExpression
        )
        let trimmed = replaced.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let compact = trimmed.replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
        let fallback = compact.isEmpty ? "task" : compact
        return String(fallback.prefix(60))
    }

    private func utcTimestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: date)
    }
}
