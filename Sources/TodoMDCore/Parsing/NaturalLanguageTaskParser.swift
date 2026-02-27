import Foundation

public struct ParsedQuickEntry: Equatable, Sendable {
    public var title: String
    public var due: LocalDate?
    public var tags: [String]

    public init(title: String, due: LocalDate?, tags: [String]) {
        self.title = title
        self.due = due
        self.tags = tags
    }
}

public struct NaturalLanguageTaskParser {
    public var calendar: Calendar
    private var dateParser: NaturalLanguageDateParser { NaturalLanguageDateParser(calendar: calendar) }

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func parse(_ input: String, relativeTo referenceDate: Date = Date()) -> ParsedQuickEntry? {
        let trimmedInput = normalizeWhitespace(input)
        guard !trimmedInput.isEmpty else { return nil }

        let (withoutTrailingTags, tags) = extractTrailingTags(from: trimmedInput)
        let (candidateTitle, due) = extractDueDate(from: withoutTrailingTags, relativeTo: referenceDate)

        let normalizedTitle = normalizeWhitespace(candidateTitle)
        let fallbackTitle = normalizeWhitespace(withoutTrailingTags)
        let resolvedTitle = normalizedTitle.isEmpty ? fallbackTitle : normalizedTitle
        guard !resolvedTitle.isEmpty else { return nil }

        return ParsedQuickEntry(title: resolvedTitle, due: due, tags: tags)
    }

    private func extractTrailingTags(from input: String) -> (String, [String]) {
        var tokens = input.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var tags: [String] = []

        while let last = tokens.last {
            guard last.hasPrefix("#"), last.count > 1 else { break }
            let value = String(last.dropFirst())
            guard isValidTag(value) else { break }
            tags.insert(value, at: 0)
            tokens.removeLast()
        }

        return (tokens.joined(separator: " "), tags)
    }

    private func extractDueDate(from input: String, relativeTo referenceDate: Date) -> (String, LocalDate?) {
        let tokens = input.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return (input, nil) }

        if let explicit = parseExplicitDatePhrase(tokens: tokens, relativeTo: referenceDate) {
            return explicit
        }

        let maxSuffixLength = min(tokens.count, 5)
        if maxSuffixLength > 0 {
            for length in stride(from: maxSuffixLength, through: 1, by: -1) {
                let phrase = tokens.suffix(length).joined(separator: " ")
                if let due = parseDatePhrase(phrase, relativeTo: referenceDate) {
                    let title = tokens.dropLast(length).joined(separator: " ")
                    return (title, due)
                }
            }
        }

        return (input, nil)
    }

    private func parseExplicitDatePhrase(tokens: [String], relativeTo referenceDate: Date) -> (String, LocalDate?)? {
        let connectors: Set<String> = ["by", "on", "due", "at"]
        for index in stride(from: tokens.count - 2, through: 0, by: -1) {
            let token = normalizedToken(tokens[index])
            guard connectors.contains(token) else { continue }
            let phrase = tokens[(index + 1)...].joined(separator: " ")
            if let due = parseDatePhrase(phrase, relativeTo: referenceDate) {
                let title = tokens[..<index].joined(separator: " ")
                return (title, due)
            }
        }

        return nil
    }

    private func parseDatePhrase(_ phrase: String, relativeTo referenceDate: Date) -> LocalDate? {
        let normalized = normalizeDatePhrase(phrase)
        guard !normalized.isEmpty else { return nil }
        return dateParser.parse(normalized, relativeTo: referenceDate)
    }

    private func normalizeDatePhrase(_ value: String) -> String {
        let lowered = value.lowercased()
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))

        let aliases: [String: String] = [
            "sun": "sunday",
            "sunday": "sunday",
            "mon": "monday",
            "monday": "monday",
            "tue": "tuesday",
            "tues": "tuesday",
            "tuesday": "tuesday",
            "wed": "wednesday",
            "weds": "wednesday",
            "wednesday": "wednesday",
            "thu": "thursday",
            "thur": "thursday",
            "thurs": "thursday",
            "thursday": "thursday",
            "fri": "friday",
            "friday": "friday",
            "sat": "saturday",
            "saturday": "saturday"
        ]

        let tokens = lowered.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return "" }

        if tokens.count == 1, let mapped = aliases[tokens[0]] {
            return mapped
        }

        if tokens.count == 2,
           let mapped = aliases[tokens[1]],
           ["next", "this"].contains(tokens[0]) {
            return "\(tokens[0]) \(mapped)"
        }

        return lowered
    }

    private func normalizedToken(_ token: String) -> String {
        token.lowercased().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func normalizeWhitespace(_ value: String) -> String {
        value
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isValidTag(_ value: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return !value.isEmpty && value.rangeOfCharacter(from: allowed.inverted) == nil
    }
}
