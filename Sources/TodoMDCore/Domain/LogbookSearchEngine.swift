import Foundation

public struct LogbookSearchEngine {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func filter(records: [TaskRecord], query: String) -> [TaskRecord] {
        let parsed = ParsedLogbookSearchQuery(query: query, calendar: calendar)
        guard parsed.hasConstraints else { return records }
        return records.filter { parsed.matches($0) }
    }
}

private struct ParsedLogbookSearchQuery {
    private let terms: [String]
    private let filters: [LogbookSearchFilter]
    private let calendar: Calendar

    init(query: String, calendar: Calendar) {
        self.calendar = calendar

        var terms: [String] = []
        var filters: [LogbookSearchFilter] = []

        for token in Self.tokenize(query) {
            guard !token.isEmpty else { continue }
            guard let separator = token.firstIndex(of: ":") else {
                terms.append(Self.normalize(token))
                continue
            }

            let rawKey = String(token[..<separator])
            let rawValue = String(token[token.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawValue.isEmpty else {
                terms.append(Self.normalize(token))
                continue
            }

            let key = Self.normalizeKey(rawKey)
            if let filter = Self.filter(for: key, value: rawValue) {
                filters.append(filter)
            } else {
                terms.append(Self.normalize(token))
            }
        }

        self.terms = terms
        self.filters = filters
    }

    var hasConstraints: Bool {
        !terms.isEmpty || !filters.isEmpty
    }

    func matches(_ record: TaskRecord) -> Bool {
        let searchableText = searchableText(for: record)

        for term in terms where !searchableText.contains(term) {
            return false
        }

        for filter in filters where !matches(record, filter: filter) {
            return false
        }

        return true
    }

    private func matches(_ record: TaskRecord, filter: LogbookSearchFilter) -> Bool {
        let frontmatter = record.document.frontmatter

        switch filter {
        case .project(let value):
            return Self.normalize(frontmatter.project) == value
        case .tag(let value):
            return frontmatter.tags.contains { Self.normalize($0) == value }
        case .area(let value):
            return Self.normalize(frontmatter.area) == value
        case .status(let value):
            return Self.normalize(frontmatter.status.rawValue) == value
        case .source(let value):
            return Self.normalize(frontmatter.source).contains(value)
        case .assignee(let value):
            return Self.normalize(frontmatter.assignee).contains(value)
        case .completedBy(let value):
            return Self.normalize(frontmatter.completedBy).contains(value)
        case .ref(let value):
            return Self.normalize(frontmatter.ref) == value
        case .priority(let value):
            return Self.normalize(frontmatter.priority.rawValue) == value
        case .flagged(let value):
            return frontmatter.flagged == value
        case .on(let value):
            return effectiveLogbookDate(for: record) == value
        case .before(let value):
            guard let effectiveDate = effectiveLogbookDate(for: record) else { return false }
            return effectiveDate < value
        case .after(let value):
            guard let effectiveDate = effectiveLogbookDate(for: record) else { return false }
            return effectiveDate > value
        }
    }

    private func searchableText(for record: TaskRecord) -> String {
        let frontmatter = record.document.frontmatter
        let segments: [String?] = [
            frontmatter.title,
            frontmatter.description,
            record.document.body,
            frontmatter.project,
            frontmatter.area,
            frontmatter.tags.joined(separator: " "),
            frontmatter.ref,
            frontmatter.source,
            frontmatter.assignee,
            frontmatter.completedBy,
            frontmatter.status.rawValue,
            frontmatter.priority.rawValue,
            frontmatter.due?.isoString,
            frontmatter.scheduled?.isoString,
            effectiveLogbookDate(for: record)?.isoString,
            record.identity.filename
        ]

        return segments
            .compactMap(Self.normalize)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func effectiveLogbookDate(for record: TaskRecord) -> LocalDate? {
        let frontmatter = record.document.frontmatter
        let date = frontmatter.completed ?? frontmatter.modified ?? frontmatter.created
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return try? LocalDate(
            year: components.year ?? 1970,
            month: components.month ?? 1,
            day: components.day ?? 1
        )
    }

    private static func tokenize(_ query: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var isInsideQuotes = false

        for character in query {
            if character == "\"" {
                isInsideQuotes.toggle()
                continue
            }

            if character.isWhitespace && !isInsideQuotes {
                if !current.isEmpty {
                    tokens.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                continue
            }

            current.append(character)
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }

    private static func filter(for key: String, value: String) -> LogbookSearchFilter? {
        let normalizedValue = normalize(value)

        switch key {
        case "project":
            return normalizedValue.isEmpty ? nil : .project(normalizedValue)
        case "tag", "tags":
            return normalizedValue.isEmpty ? nil : .tag(normalizedValue)
        case "area":
            return normalizedValue.isEmpty ? nil : .area(normalizedValue)
        case "status":
            return normalizedValue.isEmpty ? nil : .status(normalizedValue)
        case "source":
            return normalizedValue.isEmpty ? nil : .source(normalizedValue)
        case "assignee":
            return normalizedValue.isEmpty ? nil : .assignee(normalizedValue)
        case "completed-by", "completedby":
            return normalizedValue.isEmpty ? nil : .completedBy(normalizedValue)
        case "ref":
            return normalizedValue.isEmpty ? nil : .ref(normalizedValue)
        case "priority":
            return normalizedValue.isEmpty ? nil : .priority(normalizedValue)
        case "flagged":
            guard let boolValue = parseBool(normalizedValue) else { return nil }
            return .flagged(boolValue)
        case "on", "date":
            guard let date = try? LocalDate(isoDate: value) else { return nil }
            return .on(date)
        case "before":
            guard let date = try? LocalDate(isoDate: value) else { return nil }
            return .before(date)
        case "after":
            guard let date = try? LocalDate(isoDate: value) else { return nil }
            return .after(date)
        default:
            return nil
        }
    }

    private static func parseBool(_ value: String) -> Bool? {
        switch value {
        case "true", "yes", "y", "1":
            return true
        case "false", "no", "n", "0":
            return false
        default:
            return nil
        }
    }

    private static func normalize(_ value: String?) -> String {
        value?
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func normalizeKey(_ value: String) -> String {
        normalize(value).replacingOccurrences(of: "_", with: "-")
    }
}

private enum LogbookSearchFilter {
    case project(String)
    case tag(String)
    case area(String)
    case status(String)
    case source(String)
    case assignee(String)
    case completedBy(String)
    case ref(String)
    case priority(String)
    case flagged(Bool)
    case on(LocalDate)
    case before(LocalDate)
    case after(LocalDate)
}
