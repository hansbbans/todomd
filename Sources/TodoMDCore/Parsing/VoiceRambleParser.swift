import Foundation

public struct VoiceRambleSegment: Equatable, Sendable {
    public var text: String
    public var startTime: TimeInterval
    public var duration: TimeInterval

    public init(text: String, startTime: TimeInterval, duration: TimeInterval) {
        self.text = text
        self.startTime = startTime
        self.duration = duration
    }
}

public struct VoiceRambleTaskDraft: Equatable, Sendable, Identifiable {
    public let id: UUID
    public var title: String
    public var due: LocalDate?
    public var dueTime: LocalTime?
    public var priority: TaskPriority?
    public var project: String?
    public var tags: [String]
    public var estimatedMinutes: Int?
    public var confidence: Double
    public var warning: String?
    public var sourceText: String

    public init(
        id: UUID = UUID(),
        title: String,
        due: LocalDate? = nil,
        dueTime: LocalTime? = nil,
        priority: TaskPriority? = nil,
        project: String? = nil,
        tags: [String] = [],
        estimatedMinutes: Int? = nil,
        confidence: Double = 1,
        warning: String? = nil,
        sourceText: String = ""
    ) {
        self.id = id
        self.title = title
        self.due = due
        self.dueTime = dueTime
        self.priority = priority
        self.project = project
        self.tags = tags
        self.estimatedMinutes = estimatedMinutes
        self.confidence = confidence
        self.warning = warning
        self.sourceText = sourceText
    }
}

public struct VoiceRambleParser {
    public var calendar: Calendar
    public var availableProjects: [String]
    private let taskParser: NaturalLanguageTaskParser

    public init(calendar: Calendar = .current, availableProjects: [String] = []) {
        self.calendar = calendar
        self.availableProjects = availableProjects
        self.taskParser = NaturalLanguageTaskParser(calendar: calendar, availableProjects: availableProjects)
    }

    public func parse(
        _ transcript: String,
        segments: [VoiceRambleSegment] = [],
        relativeTo referenceDate: Date = Date()
    ) -> [VoiceRambleTaskDraft] {
        let clauses = splitClauses(from: transcript, segments: segments)
        guard !clauses.isEmpty else { return [] }

        var drafts: [VoiceRambleTaskDraft] = []
        for clause in clauses {
            if let command = editCommand(from: clause.text) {
                apply(command, to: &drafts, relativeTo: referenceDate)
                continue
            }

            let previousDraft = drafts.last
            if let parsed = parseTaskClause(clause, previousDraft: previousDraft, relativeTo: referenceDate) {
                drafts.append(parsed)
            }
        }

        return drafts
    }

    private func splitClauses(from transcript: String, segments: [VoiceRambleSegment]) -> [ClauseCandidate] {
        let normalizedTranscript = normalizeWhitespace(
            transcript
                .replacingOccurrences(of: "\n", with: ". ")
                .replacingOccurrences(of: "…", with: ". ")
        )

        let explicitClauses = splitOnExplicitSeparators(from: normalizedTranscript)
        if explicitClauses.count > 1 {
            return explicitClauses.map { ClauseCandidate(text: $0, origin: .explicitSeparator) }
        }

        let pauseClauses = splitOnPauses(from: segments)
        if pauseClauses.count > 1 {
            return pauseClauses.map { ClauseCandidate(text: $0, origin: .pauseSeparator) }
        }

        if let onlyClause = explicitClauses.first {
            return [ClauseCandidate(text: onlyClause, origin: .singleClause)]
        }

        return []
    }

    private func splitOnExplicitSeparators(from transcript: String) -> [String] {
        guard !transcript.isEmpty else { return [] }

        let pattern = #"\s*(?:[.!?;]+|,\s+(?:and then|then|also)\s+|\b(?:and then|then|also)\b)\s*"#
        let parts = transcript.components(separatedBy: try! NSRegularExpression(pattern: pattern))
        return parts
            .map(normalizeWhitespace)
            .filter { !$0.isEmpty }
    }

    private func splitOnPauses(from segments: [VoiceRambleSegment]) -> [String] {
        let cleaned = segments.compactMap { segment -> VoiceRambleSegment? in
            let text = normalizeWhitespace(segment.text)
            guard !text.isEmpty else { return nil }
            return VoiceRambleSegment(text: text, startTime: segment.startTime, duration: segment.duration)
        }

        guard !cleaned.isEmpty else { return [] }

        var groups: [[VoiceRambleSegment]] = [[cleaned[0]]]
        for index in 1..<cleaned.count {
            let segment = cleaned[index]
            let previous = cleaned[index - 1]
            let gap = segment.startTime - (previous.startTime + previous.duration)
            if gap >= 0.85 {
                groups.append([segment])
            } else {
                groups[groups.count - 1].append(segment)
            }
        }

        return groups
            .map { group in
                normalizeWhitespace(group.map(\.text).joined(separator: " "))
            }
            .filter { !$0.isEmpty }
    }

    private func apply(_ command: EditCommand, to drafts: inout [VoiceRambleTaskDraft], relativeTo referenceDate: Date) {
        switch command {
        case .delete(let target):
            guard let index = resolve(target, in: drafts) else { return }
            drafts.remove(at: index)

        case .replace(let target, let payload):
            let normalizedPayload = normalizeWhitespace(payload)
            guard !normalizedPayload.isEmpty else { return }

            if let targetIndex = resolve(target, in: drafts) {
                let existing = drafts[targetIndex]
                let contextDraft = targetIndex > 0 ? drafts[targetIndex - 1] : nil
                guard var parsed = parseTaskClause(
                    ClauseCandidate(text: normalizedPayload, origin: .explicitSeparator),
                    previousDraft: contextDraft,
                    relativeTo: referenceDate
                ) else {
                    return
                }

                parsed = VoiceRambleTaskDraft(
                    id: existing.id,
                    title: parsed.title,
                    due: parsed.due ?? existing.due,
                    dueTime: parsed.due != nil ? (parsed.dueTime ?? existing.dueTime) : (parsed.dueTime ?? existing.dueTime),
                    priority: parsed.priority ?? existing.priority,
                    project: parsed.project ?? existing.project,
                    tags: parsed.tags.isEmpty ? existing.tags : uniqueTags(existing.tags + parsed.tags),
                    estimatedMinutes: parsed.estimatedMinutes ?? existing.estimatedMinutes,
                    confidence: parsed.confidence,
                    warning: parsed.warning,
                    sourceText: normalizedPayload
                )
                drafts[targetIndex] = parsed
                return
            }

            if let parsed = parseTaskClause(
                ClauseCandidate(text: normalizedPayload, origin: .explicitSeparator),
                previousDraft: drafts.last,
                relativeTo: referenceDate
            ) {
                drafts.append(parsed)
            }

        case .reviseMetadata(let target, let payload):
            let normalizedPayload = normalizeWhitespace(payload)
            guard !normalizedPayload.isEmpty,
                  let targetIndex = resolve(target, in: drafts) else {
                return
            }

            let contextDraft = targetIndex > 0 ? drafts[targetIndex - 1] : nil
            guard let updated = applyMetadataRevision(
                normalizedPayload,
                to: drafts[targetIndex],
                previousDraft: contextDraft,
                relativeTo: referenceDate
            ) else {
                return
            }

            drafts[targetIndex] = updated
        }
    }

    private func parseTaskClause(
        _ clause: ClauseCandidate,
        previousDraft: VoiceRambleTaskDraft?,
        relativeTo referenceDate: Date
    ) -> VoiceRambleTaskDraft? {
        var working = normalizeWhitespace(clause.text)
        guard !working.isEmpty else { return nil }

        working = stripLeadingFiller(from: working)
        guard !working.isEmpty else { return nil }

        let sourceText = working
        let project = extractProject(from: &working, previousDraft: previousDraft)
        let priority = extractPriority(from: &working)
        let estimatedMinutes = extractEstimatedMinutes(from: &working)
        let tags = extractTags(from: &working)

        let parsed = taskParser.parse(working, relativeTo: referenceDate)
        let title = parsed?.title ?? normalizeWhitespace(working)
        guard !title.isEmpty else { return nil }

        let confidence = confidenceForClause(
            sourceText: sourceText,
            origin: clause.origin,
            resolvedTitle: title
        )

        return VoiceRambleTaskDraft(
            title: title,
            due: parsed?.due,
            dueTime: parsed?.dueTime,
            priority: priority,
            project: project ?? parsed?.project,
            tags: uniqueTags((parsed?.tags ?? []) + tags),
            estimatedMinutes: estimatedMinutes,
            confidence: confidence.score,
            warning: confidence.warning,
            sourceText: sourceText
        )
    }

    private func applyMetadataRevision(
        _ payload: String,
        to existing: VoiceRambleTaskDraft,
        previousDraft: VoiceRambleTaskDraft?,
        relativeTo referenceDate: Date
    ) -> VoiceRambleTaskDraft? {
        var working = normalizeWhitespace(payload)
        guard !working.isEmpty else { return nil }

        let sourceProjectDraft = previousDraft ?? existing
        let project = extractProject(from: &working, previousDraft: sourceProjectDraft)
        let priority = extractPriority(from: &working)
        let estimatedMinutes = extractEstimatedMinutes(from: &working)
        let tags = extractTags(from: &working)
        let parsed = taskParser.parse(working, relativeTo: referenceDate)

        let dueWasUpdated = parsed?.recognizedDatePhrase != nil || parsed?.due != nil || parsed?.dueTime != nil
        let projectWasUpdated = project != nil
        let priorityWasUpdated = priority != nil
        let estimateWasUpdated = estimatedMinutes != nil
        let tagsWereUpdated = !tags.isEmpty

        guard dueWasUpdated || projectWasUpdated || priorityWasUpdated || estimateWasUpdated || tagsWereUpdated else {
            return nil
        }

        return VoiceRambleTaskDraft(
            id: existing.id,
            title: existing.title,
            due: dueWasUpdated ? parsed?.due : existing.due,
            dueTime: dueWasUpdated ? parsed?.dueTime : existing.dueTime,
            priority: priority ?? existing.priority,
            project: project ?? existing.project,
            tags: tagsWereUpdated ? uniqueTags(existing.tags + tags) : existing.tags,
            estimatedMinutes: estimatedMinutes ?? existing.estimatedMinutes,
            confidence: max(existing.confidence, 0.9),
            warning: nil,
            sourceText: normalizeWhitespace("\(existing.sourceText.isEmpty ? existing.title : existing.sourceText) \(payload)")
        )
    }

    private func confidenceForClause(
        sourceText: String,
        origin: ClauseOrigin,
        resolvedTitle: String
    ) -> (score: Double, warning: String?) {
        var score: Double
        switch origin {
        case .explicitSeparator:
            score = 0.95
        case .pauseSeparator:
            score = 0.86
        case .singleClause:
            score = 0.78
        }

        let normalizedSource = normalizeWhitespace(sourceText)
        let words = normalizedSource.split(whereSeparator: { $0.isWhitespace })
        if words.count >= 10 {
            score -= 0.08
        }

        if isLikelyAmbiguous(normalizedSource, resolvedTitle: resolvedTitle) {
            return (max(0.45, score - 0.2), "This may contain more than one task. Review before saving.")
        }

        return (min(1, max(0.45, score)), nil)
    }

    private func isLikelyAmbiguous(_ sourceText: String, resolvedTitle: String) -> Bool {
        let lowercased = sourceText.lowercased()
        let words = lowercased.split(whereSeparator: { $0.isWhitespace })
        guard words.count >= 4 else { return false }

        let verbs: Set<String> = [
            "buy", "call", "email", "send", "review", "plan", "draft", "schedule", "book",
            "pick", "drop", "finish", "submit", "check", "pay", "write", "clean", "order"
        ]

        var verbMatches = 0
        for word in words {
            if verbs.contains(String(word)) {
                verbMatches += 1
            }
        }

        if verbMatches >= 2 {
            return true
        }

        let normalizedTitle = normalizeWhitespace(resolvedTitle).lowercased()
        return lowercased.contains(" and ") && normalizedTitle == lowercased
    }

    private func extractProject(from value: inout String, previousDraft: VoiceRambleTaskDraft?) -> String? {
        if let reused = extractSameProjectMarker(from: &value, previousDraft: previousDraft) {
            return reused
        }

        let candidates = availableProjects
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }

        for project in candidates {
            let escaped = NSRegularExpression.escapedPattern(for: project)
            let pattern = #"(?:^|\s)(?:in|under|project|for)\s+\#(escaped)(?=$|\s|[,.!?;])"#
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

    private func extractSameProjectMarker(from value: inout String, previousDraft: VoiceRambleTaskDraft?) -> String? {
        guard let previousProject = previousDraft?.project else { return nil }

        let patterns = [
            #"\b(?:same|the same)\s+project(?:\s+as\s+(?:the\s+)?(?:last|previous)\s+(?:one|task))?\b"#,
            #"\blike\s+the\s+last\s+project\b"#
        ]

        for pattern in patterns {
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
            return previousProject
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
            (#"\bno\s+priority\b"#, .none),
            (#"\burgent\b"#, .high),
            (#"\basap\b"#, .high),
            (#"\bimportant\b"#, .high),
            (#"\bnormal\s+priority\b"#, .medium)
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
        let specialCases: [(String, Int)] = [
            (#"\bhalf\s+(?:an\s+)?hour\b"#, 30),
            (#"\bquarter\s+(?:of\s+an\s+)?hour\b"#, 15),
            (#"\b(?:an|one)\s+hour\b"#, 60)
        ]

        for (pattern, minutes) in specialCases {
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
            return minutes
        }

        let pattern = #"\b(?:takes?|for|about|around|estimate(?:d)?(?:\s+time)?(?:\s+is)?|duration(?:\s+is)?)?\s*(\d+)\s*(minutes?|mins?|min|m|hours?|hrs?|hr|h)\b"#
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
        let minutes = unit.hasPrefix("hour") || unit == "hr" || unit == "hrs" || unit == "h" ? amount * 60 : amount
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
        let pattern = #"^(?:please\s+|add\s+|create\s+|new\s+task\s+|task\s+|remember\s+to\s+|i\s+need\s+to\s+|could\s+you\s+)+"#
        return value.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func editCommand(from clause: String) -> EditCommand? {
        let normalized = normalizeWhitespace(clause)
        let lowered = normalized.lowercased()

        let simpleRemovalCommands = [
            "remove that",
            "delete that",
            "scratch that",
            "never mind",
            "cancel that"
        ]
        if simpleRemovalCommands.contains(lowered) {
            return .delete(.last)
        }

        if let targetedDelete = targetedDeleteCommand(from: normalized) {
            return targetedDelete
        }

        if let targetedReplacement = targetedReplacementCommand(from: normalized) {
            return targetedReplacement
        }

        let softened = lowered.replacingOccurrences(
            of: #"^(?:no|nope|wait|hold\s+on)\s*,?\s*"#,
            with: "",
            options: [.regularExpression]
        )
        let replacementPrefixes = [
            "actually ",
            "instead ",
            "change that to ",
            "set that to ",
            "update that to "
        ]
        for prefix in replacementPrefixes {
            guard softened.hasPrefix(prefix) else { continue }
            let payload = normalizeWhitespace(String(normalized.dropFirst(normalized.count - softened.count + prefix.count)))
            return payload.isEmpty ? nil : .replace(.last, payload)
        }

        let revisionPrefixes = [
            "make that ",
            "make it ",
            "set that ",
            "update that "
        ]
        for prefix in revisionPrefixes {
            guard softened.hasPrefix(prefix) else { continue }
            let payload = normalizeWhitespace(String(normalized.dropFirst(normalized.count - softened.count + prefix.count)))
            return payload.isEmpty ? nil : .reviseMetadata(.last, payload)
        }

        if lowered != softened, !softened.isEmpty {
            return .replace(.last, normalizeWhitespace(softened))
        }

        return nil
    }

    private func targetedDeleteCommand(from clause: String) -> EditCommand? {
        let pattern = #"^(?:remove|delete|drop|scratch)\s+(?:the\s+)?(first|second|third|last)(?:\s+(?:one|task))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let nsRange = NSRange(clause.startIndex..<clause.endIndex, in: clause)
        guard let match = regex.firstMatch(in: clause, options: [], range: nsRange),
              let targetRange = Range(match.range(at: 1), in: clause),
              let target = target(from: String(clause[targetRange])) else {
            return nil
        }

        return .delete(target)
    }

    private func targetedReplacementCommand(from clause: String) -> EditCommand? {
        let patterns = [
            #"^(?:change|set|update)\s+(?:the\s+)?(first|second|third|last)(?:\s+(?:one|task))?\s+to\s+(.+)$"#,
            #"^(?:actually|instead)\s+(?:the\s+)?(first|second|third|last)(?:\s+(?:one|task))?\s+(.+)$"#,
            #"^(?:make|set|update)\s+(?:the\s+)?(first|second|third|last)(?:\s+(?:one|task))?\s+(.+)$"#
        ]

        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let nsRange = NSRange(clause.startIndex..<clause.endIndex, in: clause)
            guard let match = regex.firstMatch(in: clause, options: [], range: nsRange),
                  let targetRange = Range(match.range(at: 1), in: clause),
                  let payloadRange = Range(match.range(at: 2), in: clause),
                  let target = target(from: String(clause[targetRange])) else {
                continue
            }

            let payload = normalizeWhitespace(String(clause[payloadRange]))
            guard !payload.isEmpty else { continue }
            if index < 2 {
                return .replace(target, payload)
            }
            return .reviseMetadata(target, payload)
        }

        return nil
    }

    private func target(from rawValue: String) -> DraftTarget? {
        switch rawValue.lowercased() {
        case "first":
            return .first
        case "second":
            return .index(1)
        case "third":
            return .index(2)
        case "last":
            return .last
        default:
            return nil
        }
    }

    private func resolve(_ target: DraftTarget, in drafts: [VoiceRambleTaskDraft]) -> Int? {
        guard !drafts.isEmpty else { return nil }
        switch target {
        case .first:
            return 0
        case .last:
            return drafts.count - 1
        case .index(let index):
            return drafts.indices.contains(index) ? index : nil
        }
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

private struct ClauseCandidate {
    let text: String
    let origin: ClauseOrigin
}

private enum ClauseOrigin {
    case explicitSeparator
    case pauseSeparator
    case singleClause
}

private enum DraftTarget {
    case first
    case last
    case index(Int)
}

private enum EditCommand {
    case delete(DraftTarget)
    case replace(DraftTarget, String)
    case reviseMetadata(DraftTarget, String)
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
