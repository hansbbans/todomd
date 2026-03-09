import Foundation

public struct ProjectTriageKeywordMatch: Equatable, Sendable {
    public var keyword: String
    public var weight: Int

    public init(keyword: String, weight: Int) {
        self.keyword = keyword
        self.weight = weight
    }
}

public struct ProjectTriageSuggestion: Equatable, Sendable {
    public var project: String
    public var score: Int
    public var matchedKeywords: [ProjectTriageKeywordMatch]

    public init(project: String, score: Int, matchedKeywords: [ProjectTriageKeywordMatch]) {
        self.project = project
        self.score = score
        self.matchedKeywords = matchedKeywords
    }
}

public struct ProjectTriageSuggestionEngine {
    public init() {}

    public func suggest(
        for record: TaskRecord,
        availableProjects: [String],
        rules: TriageRulesDocument,
        bootstrapRecords: [TaskRecord] = []
    ) -> ProjectTriageSuggestion? {
        let keywordWeights = mergedKeywordWeights(
            persisted: rules.keywordProjectWeights,
            bootstrapRecords: bootstrapRecords
        )
        guard !keywordWeights.isEmpty else { return nil }

        let allowedProjects = Set(availableProjects.map { normalizeToken($0) }.filter { !$0.isEmpty })
        let tokenCounts = extractTokenCounts(from: record)
        guard !tokenCounts.isEmpty else { return nil }

        var projectScores: [String: Int] = [:]
        var perProjectKeywordWeights: [String: [String: Int]] = [:]

        for (keyword, count) in tokenCounts {
            guard let projectWeights = keywordWeights[keyword] else { continue }
            for (project, weight) in projectWeights {
                guard weight > 0 else { continue }
                let normalizedProject = normalizeProject(project)
                guard !normalizedProject.isEmpty else { continue }
                if !allowedProjects.isEmpty {
                    let allowed = allowedProjects.contains(normalizeToken(normalizedProject))
                    if !allowed { continue }
                }

                let contribution = weight * count
                projectScores[normalizedProject, default: 0] += contribution
                perProjectKeywordWeights[normalizedProject, default: [:]][keyword, default: 0] += contribution
            }
        }

        guard let winner = projectScores.max(by: { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value < rhs.value
            }
            return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedDescending
        }), winner.value > 0 else {
            return nil
        }

        let keywordMatches = (perProjectKeywordWeights[winner.key] ?? [:])
            .map { ProjectTriageKeywordMatch(keyword: $0.key, weight: $0.value) }
            .sorted { lhs, rhs in
                if lhs.weight != rhs.weight {
                    return lhs.weight > rhs.weight
                }
                return lhs.keyword.localizedCaseInsensitiveCompare(rhs.keyword) == .orderedAscending
            }

        return ProjectTriageSuggestion(
            project: winner.key,
            score: winner.value,
            matchedKeywords: Array(keywordMatches.prefix(3))
        )
    }

    public func learn(
        rules: inout TriageRulesDocument,
        from record: TaskRecord,
        assignedProject: String,
        weight: Int = 1
    ) {
        let normalizedProject = normalizeProject(assignedProject)
        guard !normalizedProject.isEmpty else { return }

        let tokenCounts = extractTokenCounts(from: record)
        guard !tokenCounts.isEmpty else { return }

        let increment = max(1, weight)
        var updated = rules.keywordProjectWeights

        for (token, count) in tokenCounts {
            let normalizedCount = max(1, count)
            updated[token, default: [:]][normalizedProject, default: 0] += increment * normalizedCount
        }

        rules.keywordProjectWeights = updated
    }

    private func mergedKeywordWeights(
        persisted: [String: [String: Int]],
        bootstrapRecords: [TaskRecord]
    ) -> [String: [String: Int]] {
        var merged = persisted

        for record in bootstrapRecords {
            guard let rawProject = record.document.frontmatter.project else { continue }
            let project = normalizeProject(rawProject)
            guard !project.isEmpty else { continue }

            let tokenCounts = extractTokenCounts(from: record)
            for (token, count) in tokenCounts {
                merged[token, default: [:]][project, default: 0] += max(1, count)
            }
        }

        return merged
    }

    private func extractTokenCounts(from record: TaskRecord) -> [String: Int] {
        let frontmatter = record.document.frontmatter
        let textParts = [
            frontmatter.title,
            record.document.body,
            frontmatter.tags.joined(separator: " ")
        ]

        let tokenSource = textParts.joined(separator: " ")
        let tokens = tokenize(tokenSource)
        var counts: [String: Int] = [:]
        for token in tokens {
            counts[token, default: 0] += 1
        }
        return counts
    }

    private func tokenize(_ text: String) -> [String] {
        let lowered = text.lowercased()
        let components = lowered.split { character in
            !character.isLetter && !character.isNumber
        }

        return components
            .map(String.init)
            .map(normalizeToken)
            .filter { token in
                token.count >= 3 && !Self.stopWords.contains(token)
            }
    }

    private func normalizeProject(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeToken(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "from", "that", "this", "have", "will", "your", "about", "into", "then", "than", "task", "todo", "note", "notes"
    ]
}
