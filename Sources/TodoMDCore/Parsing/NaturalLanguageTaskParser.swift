import Foundation

public struct ParsedQuickEntry: Equatable, Sendable {
    public var title: String
    public var due: LocalDate?
    public var dueTime: LocalTime?
    public var project: String?
    public var tags: [String]
    public var recognizedDatePhrase: String?

    public init(
        title: String,
        due: LocalDate?,
        dueTime: LocalTime? = nil,
        project: String? = nil,
        tags: [String],
        recognizedDatePhrase: String? = nil
    ) {
        self.title = title
        self.due = due
        self.dueTime = dueTime
        self.project = project
        self.tags = tags
        self.recognizedDatePhrase = recognizedDatePhrase
    }
}

public struct NaturalLanguageTaskParser {
    public var calendar: Calendar
    public var availableProjects: [String]
    private var dateParser: NaturalLanguageDateParser { NaturalLanguageDateParser(calendar: calendar) }

    public init(calendar: Calendar = .current, availableProjects: [String] = []) {
        self.calendar = calendar
        self.availableProjects = availableProjects
    }

    public func parse(_ input: String, relativeTo referenceDate: Date = Date()) -> ParsedQuickEntry? {
        let trimmedInput = normalizeWhitespace(input)
        guard !trimmedInput.isEmpty else { return nil }

        let (withoutTrailingTags, tags) = extractTrailingTags(from: trimmedInput)
        var withoutProject = withoutTrailingTags
        let project = extractProject(from: &withoutProject) ?? extractTrailingProjectMention(from: &withoutProject)
        let extraction = extractDueDate(from: withoutProject, relativeTo: referenceDate)
        let candidateTitle = extraction.title

        let normalizedTitle = normalizeWhitespace(candidateTitle)
        let fallbackTitle = normalizeWhitespace(withoutProject)
        let resolvedTitle = normalizedTitle.isEmpty ? fallbackTitle : normalizedTitle
        guard !resolvedTitle.isEmpty else { return nil }

        return ParsedQuickEntry(
            title: resolvedTitle,
            due: extraction.due,
            dueTime: extraction.dueTime,
            project: project,
            tags: tags,
            recognizedDatePhrase: extraction.recognizedDatePhrase
        )
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

    private func extractDueDate(
        from input: String,
        relativeTo referenceDate: Date
    ) -> (title: String, due: LocalDate?, dueTime: LocalTime?, recognizedDatePhrase: String?) {
        let tokens = input.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return (input, nil, nil, nil) }

        if let explicit = parseExplicitDatePhrase(tokens: tokens, relativeTo: referenceDate) {
            return explicit
        }

        let maxSuffixLength = min(tokens.count, 5)
        if maxSuffixLength > 0 {
            for length in stride(from: maxSuffixLength, through: 1, by: -1) {
                let phrase = tokens.suffix(length).joined(separator: " ")
                if let parsed = parseDatePhrase(phrase, relativeTo: referenceDate) {
                    let title = tokens.dropLast(length).joined(separator: " ")
                    return (title, parsed.due, parsed.dueTime, normalizeWhitespace(phrase))
                }
            }
        }

        return (input, nil, nil, nil)
    }

    private func parseExplicitDatePhrase(
        tokens: [String],
        relativeTo referenceDate: Date
    ) -> (title: String, due: LocalDate?, dueTime: LocalTime?, recognizedDatePhrase: String?)? {
        let connectors: Set<String> = ["by", "on", "due", "at"]
        for index in stride(from: tokens.count - 2, through: 0, by: -1) {
            let token = normalizedToken(tokens[index])
            guard connectors.contains(token) else { continue }
            let phrase = tokens[(index + 1)...].joined(separator: " ")
            if let parsed = parseDatePhrase(phrase, relativeTo: referenceDate) {
                let usesDuePrefix = index > 0
                    && normalizedToken(tokens[index - 1]) == "due"
                    && ["by", "on", "at"].contains(token)
                let connectorStartIndex = usesDuePrefix ? index - 1 : index
                let title = tokens[..<connectorStartIndex].joined(separator: " ")
                let recognizedPhrase = normalizeWhitespace(tokens[connectorStartIndex...].joined(separator: " "))
                return (title, parsed.due, parsed.dueTime, recognizedPhrase)
            }
        }

        return nil
    }

    private func parseDatePhrase(_ phrase: String, relativeTo referenceDate: Date) -> (due: LocalDate, dueTime: LocalTime?)? {
        let normalized = normalizeWhitespace(phrase)
        guard !normalized.isEmpty else { return nil }

        let direct = normalizeDatePhrase(normalized)
        if !direct.isEmpty, let due = dateParser.parse(direct, relativeTo: referenceDate) {
            return (due, nil)
        }

        if let split = splitTrailingTimePhrase(from: normalized),
           let due = parseDateOnlyPhrase(split.datePhrase, relativeTo: referenceDate),
           let dueTime = parseTimePhrase(split.timePhrase) {
            return (due, dueTime)
        }

        if let split = splitLeadingTimePhrase(from: normalized),
           let due = parseDateOnlyPhrase(split.datePhrase, relativeTo: referenceDate),
           let dueTime = parseTimePhrase(split.timePhrase) {
            return (due, dueTime)
        }

        return nil
    }

    private func parseDateOnlyPhrase(_ phrase: String, relativeTo referenceDate: Date) -> LocalDate? {
        let normalized = normalizeDatePhrase(phrase)
        guard !normalized.isEmpty else { return nil }
        return dateParser.parse(normalized, relativeTo: referenceDate)
    }

    private func splitTrailingTimePhrase(from phrase: String) -> (datePhrase: String, timePhrase: String)? {
        let pattern = #"\s+(?:at\s+)?((?:\d{1,2}(?::\d{2})?\s*(?:am|pm))|(?:[01]?\d|2[0-3]):\d{2}|noon|midnight)\s*$"#
        guard let range = phrase.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }

        let datePhrase = normalizeWhitespace(String(phrase[..<range.lowerBound]))
        let rawTime = String(phrase[range])
        let timePhrase = rawTime.replacingOccurrences(
            of: #"^\s*(?:at\s+)?"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !datePhrase.isEmpty, !timePhrase.isEmpty else { return nil }
        return (datePhrase, timePhrase)
    }

    private func splitLeadingTimePhrase(from phrase: String) -> (timePhrase: String, datePhrase: String)? {
        let pattern = #"^\s*((?:\d{1,2}(?::\d{2})?\s*(?:am|pm))|(?:[01]?\d|2[0-3]):\d{2}|noon|midnight)\s+(?:on\s+)?(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(phrase.startIndex..<phrase.endIndex, in: phrase)
        guard let match = regex.firstMatch(in: phrase, options: [], range: range),
              let timeRange = Range(match.range(at: 1), in: phrase),
              let dateRange = Range(match.range(at: 2), in: phrase) else {
            return nil
        }

        let timePhrase = normalizeWhitespace(String(phrase[timeRange]))
        let datePhrase = normalizeWhitespace(String(phrase[dateRange]))
        guard !timePhrase.isEmpty, !datePhrase.isEmpty else { return nil }
        return (timePhrase, datePhrase)
    }

    private func parseTimePhrase(_ phrase: String) -> LocalTime? {
        let normalized = phrase
            .lowercased()
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        guard !normalized.isEmpty else { return nil }

        if normalized == "noon" {
            return try? LocalTime(hour: 12, minute: 0)
        }
        if normalized == "midnight" {
            return try? LocalTime(hour: 0, minute: 0)
        }

        let twelveHourPattern = #"^(\d{1,2})(?::(\d{2}))?\s*(am|pm)$"#
        if let regex = try? NSRegularExpression(pattern: twelveHourPattern),
           let match = regex.firstMatch(
               in: normalized,
               options: [],
               range: NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
           ),
           let hourRange = Range(match.range(at: 1), in: normalized),
           let meridiemRange = Range(match.range(at: 3), in: normalized) {
            let rawHour = Int(normalized[hourRange]) ?? 0
            let minute: Int
            if let minuteTokenRange = Range(match.range(at: 2), in: normalized) {
                minute = Int(normalized[minuteTokenRange]) ?? 0
            } else {
                minute = 0
            }
            guard (1...12).contains(rawHour) else { return nil }
            let meridiem = String(normalized[meridiemRange])
            let hour = (rawHour % 12) + (meridiem == "pm" ? 12 : 0)
            return try? LocalTime(hour: hour, minute: minute)
        }

        let twentyFourHourPattern = #"^([01]?\d|2[0-3]):(\d{2})$"#
        if let regex = try? NSRegularExpression(pattern: twentyFourHourPattern),
           let match = regex.firstMatch(
               in: normalized,
               options: [],
               range: NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
           ),
           let hourRange = Range(match.range(at: 1), in: normalized),
           let minuteRange = Range(match.range(at: 2), in: normalized) {
            let hour = Int(normalized[hourRange]) ?? 0
            let minute = Int(normalized[minuteRange]) ?? 0
            return try? LocalTime(hour: hour, minute: minute)
        }

        return nil
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

    private func extractTrailingProjectMention(from value: inout String) -> String? {
        let candidates = availableProjects
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }

        let normalizedValue = normalizeWhitespace(value)
        guard !normalizedValue.isEmpty else { return nil }
        let loweredValue = normalizedValue.lowercased()

        for project in candidates {
            let mention = "@\(normalizeWhitespace(project).lowercased())"
            if loweredValue == mention {
                value = ""
                return project
            }

            let suffix = " \(mention)"
            guard loweredValue.hasSuffix(suffix) else { continue }
            let endIndex = normalizedValue.index(normalizedValue.endIndex, offsetBy: -suffix.count)
            value = normalizeWhitespace(String(normalizedValue[..<endIndex]))
            return project
        }

        return nil
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

public struct ParsedPerspectiveQuery: Equatable, Sendable {
    public var rules: PerspectiveRuleGroup
    public var suggestedName: String
    public var summary: String
    public var confidence: Double
    public var requiresCloudFallback: Bool

    public init(
        rules: PerspectiveRuleGroup,
        suggestedName: String,
        summary: String,
        confidence: Double,
        requiresCloudFallback: Bool
    ) {
        self.rules = rules
        self.suggestedName = suggestedName
        self.summary = summary
        self.confidence = confidence
        self.requiresCloudFallback = requiresCloudFallback
    }
}

public struct NaturalLanguagePerspectiveParser {
    public var calendar: Calendar
    private var dateParser: NaturalLanguageDateParser { NaturalLanguageDateParser(calendar: calendar) }

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func parse(_ query: String, relativeTo referenceDate: Date = Date()) -> ParsedPerspectiveQuery {
        let normalizedQuery = normalize(query)
        let suggester = PerspectiveNameSuggester()

        if normalizedQuery.isEmpty || isShowAllQuery(normalizedQuery) {
            let empty = PerspectiveRuleGroup(operator: .and, conditions: [])
            return ParsedPerspectiveQuery(
                rules: empty,
                suggestedName: suggester.suggest(from: query),
                summary: RulesNaturalizer().naturalize(group: empty),
                confidence: 1,
                requiresCloudFallback: false
            )
        }

        let parsed = parseExpression(normalizedQuery, referenceDate: referenceDate)
        let summary = RulesNaturalizer().naturalize(group: parsed.group)
        return ParsedPerspectiveQuery(
            rules: parsed.group,
            suggestedName: suggester.suggest(from: query),
            summary: summary,
            confidence: parsed.confidence,
            requiresCloudFallback: parsed.confidence < 0.5
        )
    }

    private func parseExpression(_ query: String, referenceDate: Date) -> (group: PerspectiveRuleGroup, confidence: Double) {
        if let (left, right) = splitOnExclusion(query) {
            let lhs = parseExpression(left, referenceDate: referenceDate)
            let rhs = parseExpression(right, referenceDate: referenceDate)

            var conditions: [PerspectiveCondition] = []
            if !lhs.group.conditions.isEmpty {
                conditions.append(.group(lhs.group))
            }
            if !rhs.group.conditions.isEmpty {
                conditions.append(.group(PerspectiveRuleGroup(operator: .not, conditions: [.group(rhs.group)])))
            }

            return (
                PerspectiveRuleGroup(operator: .and, conditions: conditions),
                min(lhs.confidence, rhs.confidence)
            )
        }

        let orParts = splitOnLogicalOr(query)
        if orParts.count > 1 {
            let parsedParts = orParts.map { parseConjunction($0, referenceDate: referenceDate) }
            let groups = parsedParts.map { PerspectiveCondition.group($0.group) }
            let confidence = parsedParts.map(\.confidence).min() ?? 0
            return (PerspectiveRuleGroup(operator: .or, conditions: groups), confidence)
        }

        return parseConjunction(query, referenceDate: referenceDate)
    }

    private func parseConjunction(_ query: String, referenceDate: Date) -> (group: PerspectiveRuleGroup, confidence: Double) {
        var conditions: [PerspectiveCondition] = []
        let excludesDoneStatus = query.contains("not done") || query.contains("not completed")

        if let projects = parseProjectList(query), projects.count > 1 {
            let projectRules = projects.map { PerspectiveCondition.rule(PerspectiveRule(field: .project, operator: .equals, value: $0)) }
            conditions.append(.group(PerspectiveRuleGroup(operator: .or, conditions: projectRules)))
        } else if let project = parseSingleProject(query) {
            conditions.append(.rule(PerspectiveRule(field: .project, operator: .equals, value: project)))
        }

        if let area = parseArea(query) {
            conditions.append(.rule(PerspectiveRule(field: .area, operator: .equals, value: area)))
        }

        if query.contains("due today") {
            conditions.append(.rule(PerspectiveRule(field: .due, operator: .onToday)))
        }

        if query.contains("due tomorrow") {
            conditions.append(.rule(PerspectiveRule(field: .due, operator: .on, value: "tomorrow")))
        }

        if query.contains("due this week") {
            conditions.append(.rule(PerspectiveRule(
                field: .due,
                operator: .inNext,
                jsonValue: .object(["op": .string("in_next"), "value": .number(7), "unit": .string("days")])
            )))
        }

        if let phrase = firstMatch(pattern: #"due ([a-z0-9\-\s]+?) or earlier"#, in: query),
           let dateValue = resolvedDateValue(from: phrase, referenceDate: referenceDate) {
            conditions.append(.rule(PerspectiveRule(field: .due, operator: .onOrBefore, jsonValue: dateValue)))
        }

        if let phrase = firstMatch(pattern: #"due before ([a-z0-9\-\s]+)"#, in: query),
           let dateValue = resolvedDateValue(from: phrase, referenceDate: referenceDate) {
            conditions.append(.rule(PerspectiveRule(field: .due, operator: .before, jsonValue: dateValue)))
        }

        if let phrase = firstMatch(pattern: #"due by ([a-z0-9\-\s]+)"#, in: query),
           let dateValue = resolvedDateValue(from: phrase, referenceDate: referenceDate) {
            conditions.append(.rule(PerspectiveRule(field: .due, operator: .onOrBefore, jsonValue: dateValue)))
        }

        if let phrase = parseConcreteDuePhrase(query),
           let dateValue = resolvedDateValue(from: phrase, referenceDate: referenceDate) {
            conditions.append(.rule(PerspectiveRule(field: .due, operator: .on, jsonValue: dateValue)))
        }

        if query.contains("overdue") {
            conditions.append(.rule(PerspectiveRule(field: .due, operator: .before, value: "today")))
        }

        if query.contains("no due date") {
            conditions.append(.rule(PerspectiveRule(field: .due, operator: .isNil)))
        }

        if let phrase = firstMatch(pattern: #"scheduled(?: for)? ([a-z0-9\-\s]+)"#, in: query),
           let dateValue = resolvedDateValue(from: phrase, referenceDate: referenceDate) {
            conditions.append(.rule(PerspectiveRule(field: .scheduled, operator: .on, jsonValue: dateValue)))
        }

        if query.contains("deferred") {
            conditions.append(.rule(PerspectiveRule(field: .defer, operator: .isNotNil)))
        }

        if let tag = parseTag(query) {
            conditions.append(.rule(PerspectiveRule(field: .tags, operator: .contains, value: tag)))
        }

        if query.contains("untagged") {
            conditions.append(.rule(PerspectiveRule(field: .tags, operator: .isNil)))
        }

        if query.contains("high priority") {
            conditions.append(.rule(PerspectiveRule(field: .priority, operator: .equals, value: "high")))
        } else if query.contains("medium priority") {
            conditions.append(.rule(PerspectiveRule(field: .priority, operator: .equals, value: "medium")))
        } else if query.contains("low priority") {
            conditions.append(.rule(PerspectiveRule(field: .priority, operator: .equals, value: "low")))
        }

        if query.contains("flagged") {
            conditions.append(.rule(PerspectiveRule(field: .flagged, operator: .isTrue)))
        }

        if let minutes = parseMinutes(query) {
            conditions.append(.rule(PerspectiveRule(field: .estimatedMinutes, operator: .lessThan, jsonValue: .number(Double(minutes)))))
        }

        if excludesDoneStatus {
            conditions.append(.rule(PerspectiveRule(field: .status, operator: .notEquals, value: TaskStatus.done.rawValue)))
        } else if query.contains("someday") {
            conditions.append(.rule(PerspectiveRule(field: .status, operator: .equals, value: TaskStatus.someday.rawValue)))
        }

        if query == "inbox" || query.contains("inbox items") {
            conditions.append(.rule(PerspectiveRule(field: .area, operator: .isNil)))
            conditions.append(.rule(PerspectiveRule(field: .project, operator: .isNil)))
        }

        if query.contains("completed this week") && !query.contains("not completed this week") {
            conditions.append(.rule(PerspectiveRule(field: .status, operator: .equals, value: TaskStatus.done.rawValue)))
            conditions.append(.rule(PerspectiveRule(
                field: .completed,
                operator: .inPast,
                jsonValue: .object(["op": .string("in_past"), "value": .number(7), "unit": .string("days")])
            )))
        } else if query.contains("completed") && !excludesDoneStatus {
            conditions.append(.rule(PerspectiveRule(field: .status, operator: .equals, value: TaskStatus.done.rawValue)))
        }

        if let source = firstMatch(pattern: #"(?:created by|tasks from|from) ([a-z0-9\-_]+)"#, in: query) {
            conditions.append(.rule(PerspectiveRule(field: .source, operator: .equals, value: source)))
        }

        if query.contains("repeating") || query.contains("recurring") {
            conditions.append(.rule(PerspectiveRule(field: .recurrence, operator: .isNotNil)))
        }

        if query.contains("my tasks") || query.contains("assigned to me") {
            conditions.append(.group(PerspectiveRuleGroup(
                operator: .or,
                conditions: [
                    .rule(PerspectiveRule(field: .assignee, operator: .isNil)),
                    .rule(PerspectiveRule(field: .assignee, operator: .equals, value: "user"))
                ]
            )))
        } else if let assignee = firstMatch(pattern: #"assigned to ([a-z0-9\-_]+)"#, in: query) {
            conditions.append(.rule(PerspectiveRule(field: .assignee, operator: .equals, value: assignee)))
        }

        if query.contains("delegated") || query.contains("assigned to agents") {
            conditions.append(.rule(PerspectiveRule(field: .assignee, operator: .isNotNil)))
            conditions.append(.rule(PerspectiveRule(field: .assignee, operator: .notEquals, value: "user")))
        }

        if query.contains("unassigned") {
            conditions.append(.rule(PerspectiveRule(field: .assignee, operator: .isNil)))
        }

        if query.contains("completed by me") {
            conditions.append(.rule(PerspectiveRule(field: .completedBy, operator: .equals, value: "user")))
        } else if query.contains("completed by agents") {
            conditions.append(.rule(PerspectiveRule(field: .completedBy, operator: .isNotNil)))
            conditions.append(.rule(PerspectiveRule(field: .completedBy, operator: .notEquals, value: "user")))
        } else if let completedBy = firstMatch(pattern: #"completed by ([a-z0-9\-_]+)"#, in: query) {
            conditions.append(.rule(PerspectiveRule(field: .completedBy, operator: .equals, value: completedBy)))
        }

        if query.contains("available tasks") {
            conditions.append(.rule(PerspectiveRule(field: .blockedBy, operator: .isNil)))
            conditions.append(.rule(PerspectiveRule(field: .defer, operator: .onOrBefore, jsonValue: .object(["op": .string("today")])))
            )
            conditions.append(.rule(PerspectiveRule(
                field: .status,
                operator: .in,
                jsonValue: .array([.string(TaskStatus.todo.rawValue), .string(TaskStatus.inProgress.rawValue)])
            )))
        } else if query.contains("blocked by "), let ref = firstMatch(pattern: #"blocked by (t-[0-9a-f]{4,6})"#, in: query) {
            conditions.append(.rule(PerspectiveRule(field: .blockedBy, operator: .contains, value: ref)))
        } else if query.contains("unblocked") || query.contains("not blocked") {
            conditions.append(.rule(PerspectiveRule(field: .blockedBy, operator: .isNil)))
        } else if query.contains("blocked") {
            conditions.append(.rule(PerspectiveRule(field: .blockedBy, operator: .isNotNil)))
        }

        let deduped = dedupe(conditions)
        let confidence: Double = deduped.isEmpty ? 0.2 : 1.0
        return (PerspectiveRuleGroup(operator: .and, conditions: deduped), confidence)
    }

    private func parseSingleProject(_ query: String) -> String? {
        guard let phrase = scopedPhrase(in: query, after: "in project ") else { return nil }
        return titleCase(phrase)
    }

    private func parseProjectList(_ query: String) -> [String]? {
        guard let phrase = scopedPhrase(in: query, after: "in projects ") else { return nil }
        let names = phrase
            .replacingOccurrences(of: ",", with: " and ")
            .split(separator: " ")
            .map(String.init)

        var grouped: [String] = []
        var current: [String] = []
        for token in names {
            if token == "and" {
                if !current.isEmpty {
                    grouped.append(titleCase(current.joined(separator: " ")))
                    current.removeAll()
                }
            } else {
                current.append(token)
            }
        }
        if !current.isEmpty {
            grouped.append(titleCase(current.joined(separator: " ")))
        }
        return grouped.filter { !$0.isEmpty }
    }

    private func parseArea(_ query: String) -> String? {
        if let explicit = firstMatch(pattern: #"in area ([a-z0-9 _\-]+)"#, in: query) {
            return titleCase(explicit)
        }

        guard let areaToken = firstMatch(pattern: #"([a-z][a-z0-9_\-]*) tasks"#, in: query) else { return nil }
        let excluded: Set<String> = [
            "all", "items", "tasks", "high", "low", "medium", "priority", "flagged",
            "completed", "overdue", "deferred", "quick", "someday", "repeating"
        ]
        if excluded.contains(areaToken) {
            return nil
        }
        return titleCase(areaToken)
    }

    private func parseTag(_ query: String) -> String? {
        if let withAt = firstMatch(pattern: #"tagged @([a-z0-9_\-]+)"#, in: query) {
            return withAt
        }
        return firstMatch(pattern: #"tagged ([a-z0-9_\-]+)"#, in: query)
    }

    private func parseMinutes(_ query: String) -> Int? {
        if let value = firstMatch(pattern: #"under ([0-9]+) min(?:ute)?s?"#, in: query).flatMap(Int.init) {
            return value
        }
        return firstMatch(pattern: #"under ([0-9]+) minutes?"#, in: query).flatMap(Int.init)
    }

    private func parseConcreteDuePhrase(_ query: String) -> String? {
        guard var phrase = scopedPhrase(in: query, after: "due ") else { return nil }
        phrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)

        if phrase == "today" || phrase == "tomorrow" || phrase == "this week" || phrase == "no due date" {
            return nil
        }

        if phrase.hasPrefix("before ") || phrase.hasSuffix(" or earlier") {
            return nil
        }

        if phrase.hasPrefix("on ") {
            phrase.removeFirst(3)
        }

        phrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        return phrase.isEmpty ? nil : phrase
    }

    private func normalize(_ query: String) -> String {
        query
            .lowercased()
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isShowAllQuery(_ normalizedQuery: String) -> Bool {
        ["everything", "all tasks", "all items", "show me everything"].contains(normalizedQuery)
    }

    private func split(_ query: String, by token: String) -> [String] {
        query
            .components(separatedBy: token)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func splitOnExclusion(_ query: String) -> (String, String)? {
        for token in [" except ", " excluding ", " but not "] {
            if let range = query.range(of: token) {
                let left = String(query[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let right = String(query[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return (left, right)
            }
        }

        guard let range = query.range(of: " not ") else { return nil }
        let trailing = String(query[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if ["done", "completed", "blocked", "cancelled", "someday"].contains(where: { trailing.hasPrefix($0) }) {
            return nil
        }

        let left = String(query[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let right = trailing
        return (left, right)
    }

    private func splitOnLogicalOr(_ query: String) -> [String] {
        var parts: [String] = []
        var segmentStart = query.startIndex
        var searchStart = query.startIndex

        while let range = query.range(of: " or ", range: searchStart..<query.endIndex) {
            let trailing = query[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if trailing.hasPrefix("earlier") || trailing.hasPrefix("later") {
                searchStart = range.upperBound
                continue
            }

            let part = String(query[segmentStart..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !part.isEmpty {
                parts.append(part)
            }
            segmentStart = range.upperBound
            searchStart = range.upperBound
        }

        let tail = String(query[segmentStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            parts.append(tail)
        }
        return parts
    }

    private func firstMatch(pattern: String, in value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(location: 0, length: value.utf16.count)
        guard let match = regex.firstMatch(in: value, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return value[captureRange].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolvedDateValue(from phrase: String, referenceDate: Date) -> JSONValue? {
        let normalized = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["today", "tomorrow", "yesterday"].contains(normalized) {
            return .string(normalized)
        }
        if isRelativeWeekdayPhrase(normalized) {
            return .object([
                "op": .string("date_phrase"),
                "phrase": .string(normalized)
            ])
        }
        if let parsed = dateParser.parse(normalized, relativeTo: referenceDate) {
            return .string(parsed.isoString)
        }
        return nil
    }

    private func isRelativeWeekdayPhrase(_ phrase: String) -> Bool {
        let tokens = phrase.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return false }

        let weekdays: Set<String> = [
            "sun", "sunday",
            "mon", "monday",
            "tue", "tues", "tuesday",
            "wed", "weds", "wednesday",
            "thu", "thur", "thurs", "thursday",
            "fri", "friday",
            "sat", "saturday"
        ]

        if tokens.count == 1 {
            return weekdays.contains(tokens[0])
        }
        if tokens.count == 2 {
            return ["next", "this", "upcoming"].contains(tokens[0]) && weekdays.contains(tokens[1])
        }
        if tokens.count == 3 {
            return tokens[0] == "this" && ["next", "upcoming"].contains(tokens[1]) && weekdays.contains(tokens[2])
        }
        return false
    }

    private func scopedPhrase(in query: String, after prefix: String) -> String? {
        guard let range = query.range(of: prefix) else { return nil }
        let remainder = query[range.upperBound...]
        let stopTokens = [
            " due ",
            " scheduled ",
            " tagged ",
            " high priority",
            " medium priority",
            " low priority",
            " flagged",
            " overdue",
            " no due date",
            " completed",
            " not done",
            " not completed",
            " blocked",
            " unblocked",
            " that ",
            " which ",
            " where ",
            " assigned ",
            " repeating",
            " recurring"
        ]

        let endIndex = stopTokens
            .compactMap { token in remainder.range(of: token).map(\.lowerBound) }
            .min() ?? remainder.endIndex

        let phrase = String(remainder[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        return phrase.isEmpty ? nil : phrase
    }

    private func titleCase(_ value: String) -> String {
        value
            .split(separator: " ")
            .map { token in
                let lower = token.lowercased()
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }

    private func dedupe(_ conditions: [PerspectiveCondition]) -> [PerspectiveCondition] {
        var seen = Set<String>()
        var unique: [PerspectiveCondition] = []
        unique.reserveCapacity(conditions.count)

        for condition in conditions {
            let key: String
            switch condition {
            case .rule(let rule):
                key = "\(rule.field.rawValue)|\(rule.operator.rawValue)|\(rule.stringValue)"
            case .group(let group):
                key = "group|\(group.operator.rawValue)|\(group.conditions.count)"
            }
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(condition)
        }

        return unique
    }
}

public struct PerspectiveNameSuggester: Sendable {
    public init() {}

    public func suggest(from query: String) -> String {
        let fillerWords: Set<String> = ["all", "items", "tasks", "things", "show", "me"]
        let tokens = query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !fillerWords.contains($0) }

        let title = tokens
            .map { token in
                token.prefix(1).uppercased() + token.dropFirst()
            }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let fallback = title.isEmpty ? "Custom Perspective" : title
        if fallback.count <= 40 {
            return fallback
        }
        return String(fallback.prefix(37)) + "..."
    }
}

public struct RulesNaturalizer: Sendable {
    public init() {}

    public func naturalize(group: PerspectiveRuleGroup) -> String {
        guard !group.conditions.isEmpty else { return "Showing all tasks." }
        let parts = group.conditions.compactMap(naturalize(condition:))
        if parts.isEmpty { return "Showing all tasks." }
        return "Showing tasks where \(join(parts: parts, with: group.operator))."
    }

    private func naturalize(condition: PerspectiveCondition) -> String? {
        switch condition {
        case .rule(let rule):
            return naturalize(rule: rule)
        case .group(let group):
            let nested = group.conditions.compactMap(naturalize(condition:))
            guard !nested.isEmpty else { return nil }
            return join(parts: nested, with: group.operator)
        }
    }

    private func naturalize(rule: PerspectiveRule) -> String {
        let value = rule.stringValue
        switch (rule.field, rule.operator) {
        case (.due, .onToday):
            return "due today"
        case (.due, .before):
            return value == "today" ? "overdue" : "due before \(value)"
        case (.due, .on):
            return "due on \(value)"
        case (.due, .onOrBefore):
            return "due on or before \(value)"
        case (.due, .isNil):
            return "no due date"
        case (.scheduled, .on):
            return "scheduled on \(value)"
        case (.priority, .equals):
            return "\(value) priority"
        case (.flagged, .isTrue):
            return "flagged"
        case (.area, .equals):
            return "in area \(value)"
        case (.project, .equals):
            return "in project \(value)"
        case (.tags, .contains):
            return "tagged \(value)"
        case (.status, .equals):
            return "status is \(value)"
        case (.status, .notEquals):
            return "status is not \(value)"
        case (.status, .in):
            return "status in \(value)"
        case (.recurrence, .isNotNil):
            return "repeating"
        case (.estimatedMinutes, .lessThan):
            return "under \(value) minutes"
        case (.assignee, .equals):
            return "assigned to \(value)"
        case (.assignee, .isNil):
            return "unassigned"
        case (.blockedBy, .isNotNil):
            return "blocked"
        case (.blockedBy, .isNil):
            return "not blocked"
        case (.blockedBy, .contains):
            return "blocked by \(value)"
        case (.completedBy, .equals):
            return "completed by \(value)"
        default:
            if value.isEmpty {
                return "\(rule.field.rawValue) \(rule.operator.rawValue)"
            }
            return "\(rule.field.rawValue) \(rule.operator.rawValue) \(value)"
        }
    }

    private func join(parts: [String], with op: PerspectiveLogicalOperator) -> String {
        switch op {
        case .and:
            return parts.joined(separator: " and ")
        case .or:
            return parts.joined(separator: " or ")
        case .not:
            return "not (\(parts.joined(separator: " and ")))"
        case .unknown(let raw):
            return parts.joined(separator: " \(raw.lowercased()) ")
        }
    }
}
