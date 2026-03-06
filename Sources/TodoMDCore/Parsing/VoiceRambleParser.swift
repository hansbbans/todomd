import Foundation

public struct VoiceRambleTaskDraft: Equatable, Sendable, Identifiable {
    public let id: UUID
    public var title: String
    public var due: LocalDate?
    public var dueTime: LocalTime?
    public var priority: TaskPriority?
    public var project: String?
    public var tags: [String]
    public var estimatedMinutes: Int?

    public init(
        id: UUID = UUID(),
        title: String,
        due: LocalDate? = nil,
        dueTime: LocalTime? = nil,
        priority: TaskPriority? = nil,
        project: String? = nil,
        tags: [String] = [],
        estimatedMinutes: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.due = due
        self.dueTime = dueTime
        self.priority = priority
        self.project = project
        self.tags = tags
        self.estimatedMinutes = estimatedMinutes
    }
}

public struct VoiceRambleParser {
    public var calendar: Calendar
    public var availableProjects: [String]
    private let taskParser: NaturalLanguageTaskParser

    public init(calendar: Calendar = .current, availableProjects: [String] = []) {
        self.calendar = calendar
        self.availableProjects = availableProjects
        self.taskParser = NaturalLanguageTaskParser(calendar: calendar)
    }

    public func parse(_ transcript: String, relativeTo referenceDate: Date = Date()) -> [VoiceRambleTaskDraft] {
        let clauses = splitClauses(from: transcript)
        guard !clauses.isEmpty else { return [] }

        var drafts: [VoiceRambleTaskDraft] = []
        for clause in clauses {
            if isRemovalCommand(clause) {
                if !drafts.isEmpty {
                    drafts.removeLast()
                }
                continue
            }

            if let replacement = correctionPayload(from: clause) {
                guard let parsed = parseTaskClause(replacement, relativeTo: referenceDate) else { continue }
                if drafts.isEmpty {
                    drafts.append(parsed)
                } else {
                    drafts[drafts.count - 1] = parsed
                }
                continue
            }

            if let parsed = parseTaskClause(clause, relativeTo: referenceDate) {
                drafts.append(parsed)
            }
        }

        return drafts
    }

    private func splitClauses(from transcript: String) -> [String] {
        let normalized = normalizeWhitespace(
            transcript
                .replacingOccurrences(of: "\n", with: ". ")
                .replacingOccurrences(of: "…", with: ". ")
        )
        guard !normalized.isEmpty else { return [] }

        let pattern = #"\s*(?:[.!?;]+|,\s+(?:and then|then|also)\s+|\b(?:and then|then|also)\b)\s*"#
        let parts = normalized.components(separatedBy: try! NSRegularExpression(pattern: pattern))
        return parts
            .map(normalizeWhitespace)
            .filter { !$0.isEmpty }
    }

    private func parseTaskClause(_ clause: String, relativeTo referenceDate: Date) -> VoiceRambleTaskDraft? {
        var working = normalizeWhitespace(clause)
        guard !working.isEmpty else { return nil }

        working = stripLeadingFiller(from: working)
        guard !working.isEmpty else { return nil }

        let project = extractProject(from: &working)
        let priority = extractPriority(from: &working)
        let estimatedMinutes = extractEstimatedMinutes(from: &working)
        let tags = extractTags(from: &working)

        let parsed = taskParser.parse(working, relativeTo: referenceDate)
        let title = parsed?.title ?? normalizeWhitespace(working)
        guard !title.isEmpty else { return nil }

        return VoiceRambleTaskDraft(
            title: title,
            due: parsed?.due,
            dueTime: parsed?.dueTime,
            priority: priority,
            project: project,
            tags: uniqueTags((parsed?.tags ?? []) + tags),
            estimatedMinutes: estimatedMinutes
        )
    }

    private func extractProject(from value: inout String) -> String? {
        let candidates = availableProjects
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }

        for project in candidates {
            let escaped = NSRegularExpression.escapedPattern(for: project)
            let pattern = #"(?:^|\s)(?:in|under|project)\s+\#(escaped)(?=$|\s|[,.!?;])"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let nsRange = NSRange(value.startIndex..<value.endIndex, in: value)
            guard let match = regex.firstMatch(in: value, options: [], range: nsRange),
                  let matchRange = Range(match.range, in: value) else {
                continue
            }

            value.removeSubrange(matchRange)
            value = normalizeWhitespace(value)
            return project
        }

        return nil
    }

    private func extractPriority(from value: inout String) -> TaskPriority? {
        let patterns: [(String, TaskPriority)] = [
            (#"\bp1\b"#, .high),
            (#"\bp2\b"#, .medium),
            (#"\bp3\b"#, .low),
            (#"\bp4\b"#, .none),
            (#"\bpriority\s+1\b"#, .high),
            (#"\bpriority\s+one\b"#, .high),
            (#"\bpriority\s+2\b"#, .medium),
            (#"\bpriority\s+two\b"#, .medium),
            (#"\bpriority\s+3\b"#, .low),
            (#"\bpriority\s+three\b"#, .low),
            (#"\bpriority\s+4\b"#, .none),
            (#"\bpriority\s+four\b"#, .none),
            (#"\bhigh\s+priority\b"#, .high),
            (#"\bmedium\s+priority\b"#, .medium),
            (#"\blow\s+priority\b"#, .low),
            (#"\bno\s+priority\b"#, .none)
        ]

        for (pattern, priority) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let nsRange = NSRange(value.startIndex..<value.endIndex, in: value)
            guard let match = regex.firstMatch(in: value, options: [], range: nsRange),
                  let matchRange = Range(match.range, in: value) else {
                continue
            }

            value.removeSubrange(matchRange)
            value = normalizeWhitespace(value)
            return priority
        }

        return nil
    }

    private func extractEstimatedMinutes(from value: inout String) -> Int? {
        let pattern = #"\b(?:takes?|for|estimate(?:d)?(?:\s+time)?(?:\s+is)?|duration(?:\s+is)?)\s+(\d+)\s*(minutes?|mins?|hours?|hrs?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let nsRange = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, options: [], range: nsRange),
              let amountRange = Range(match.range(at: 1), in: value),
              let unitRange = Range(match.range(at: 2), in: value),
              let matchRange = Range(match.range, in: value),
              let amount = Int(value[amountRange]) else {
            return nil
        }

        let unit = String(value[unitRange]).lowercased()
        let minutes = unit.hasPrefix("hour") || unit.hasPrefix("hr") ? amount * 60 : amount
        value.removeSubrange(matchRange)
        value = normalizeWhitespace(value)
        return minutes
    }

    private func extractTags(from value: inout String) -> [String] {
        var tags: [String] = []

        let trailingPattern = #"\b(?:labels?|tags?)\s+(.+)$"#
        if let regex = try? NSRegularExpression(pattern: trailingPattern, options: [.caseInsensitive]) {
            let nsRange = NSRange(value.startIndex..<value.endIndex, in: value)
            if let match = regex.firstMatch(in: value, options: [], range: nsRange),
               let payloadRange = Range(match.range(at: 1), in: value),
               let matchRange = Range(match.range, in: value) {
                tags.append(contentsOf: parseTagList(String(value[payloadRange])))
                value.removeSubrange(matchRange)
                value = normalizeWhitespace(value)
            }
        }

        let inlineHashPattern = #"#([A-Za-z0-9_-]+)"#
        if let regex = try? NSRegularExpression(pattern: inlineHashPattern) {
            let nsRange = NSRange(value.startIndex..<value.endIndex, in: value)
            let matches = regex.matches(in: value, options: [], range: nsRange)
            for match in matches {
                guard let range = Range(match.range(at: 1), in: value) else { continue }
                tags.append(String(value[range]))
            }
            if !matches.isEmpty {
                value = regex.stringByReplacingMatches(in: value, options: [], range: nsRange, withTemplate: "")
                value = normalizeWhitespace(value)
            }
        }

        return uniqueTags(tags)
    }

    private func parseTagList(_ raw: String) -> [String] {
        let normalized = raw
            .replacingOccurrences(of: #"\band\b"#, with: ",", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: " ", with: ",")
        return normalized
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { isValidTag($0) }
    }

    private func stripLeadingFiller(from value: String) -> String {
        let pattern = #"^(?:please\s+|add\s+|create\s+|new\s+task\s+|task\s+|remember\s+to\s+|i\s+need\s+to\s+)+"#
        return value.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isRemovalCommand(_ clause: String) -> Bool {
        let normalized = normalizeWhitespace(clause).lowercased()
        let commands = [
            "remove that",
            "delete that",
            "scratch that",
            "never mind",
            "cancel that"
        ]
        return commands.contains(normalized)
    }

    private func correctionPayload(from clause: String) -> String? {
        let prefixes = [
            "actually ",
            "instead ",
            "make that ",
            "change that to "
        ]
        let normalized = normalizeWhitespace(clause)
        let lowered = normalized.lowercased()
        for prefix in prefixes {
            guard lowered.hasPrefix(prefix) else { continue }
            let payload = normalizeWhitespace(String(normalized.dropFirst(prefix.count)))
            return payload.isEmpty ? nil : payload
        }
        return nil
    }

    private func uniqueTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { rawTag in
            let normalized = rawTag
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard isValidTag(normalized), !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return normalized
        }
    }

    private func isValidTag(_ value: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return !value.isEmpty && value.rangeOfCharacter(from: allowed.inverted) == nil
    }

    private func normalizeWhitespace(_ value: String) -> String {
        value
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    func components(separatedBy regex: NSRegularExpression) -> [String] {
        let range = NSRange(startIndex..<endIndex, in: self)
        var output: [String] = []
        var previousLocation = range.location

        for match in regex.matches(in: self, options: [], range: range) {
            let matchRange = match.range
            guard let sliceRange = Range(NSRange(location: previousLocation, length: matchRange.location - previousLocation), in: self) else {
                continue
            }
            output.append(String(self[sliceRange]))
            previousLocation = matchRange.location + matchRange.length
        }

        guard let trailingRange = Range(NSRange(location: previousLocation, length: range.location + range.length - previousLocation), in: self) else {
            return output
        }
        output.append(String(self[trailingRange]))
        return output
    }
}
