import Foundation

public struct SourceActivityEvent: Equatable, Sendable {
    public enum Action: String, Equatable, Sendable {
        case created
        case modified
        case completed
        case deleted
        case conflicted
        case unreadable
    }

    public let action: Action
    public let source: String
    public let subject: String
    public let timestamp: Date

    public init(action: Action, source: String, subject: String, timestamp: Date) {
        self.action = action
        self.source = source
        self.subject = subject
        self.timestamp = timestamp
    }
}

public struct SourceActivityEntry: Equatable, Identifiable, Sendable {
    public let source: String
    public let action: SourceActivityEvent.Action
    public let subjects: [String]
    public let timestamp: Date

    public init(source: String, action: SourceActivityEvent.Action, subjects: [String], timestamp: Date) {
        self.source = source
        self.action = action
        self.subjects = subjects
        self.timestamp = timestamp
    }

    public var id: String {
        "\(source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(action.rawValue)|\(timestamp.timeIntervalSinceReferenceDate)"
    }

    public var itemCount: Int {
        subjects.count
    }
}

public struct SourceActivityLog: Sendable {
    private let maximumEntryCount: Int
    private let groupingWindow: TimeInterval
    private var entries: [SourceActivityEntry]

    public init(maximumEntryCount: Int = 50, groupingWindow: TimeInterval = 300) {
        self.maximumEntryCount = max(1, maximumEntryCount)
        self.groupingWindow = max(0, groupingWindow)
        self.entries = []
    }

    public mutating func record(_ events: [SourceActivityEvent]) {
        for event in events {
            record(event)
        }
    }

    public mutating func record(_ event: SourceActivityEvent) {
        let normalizedSource = Self.normalizedSource(event.source)
        guard normalizedSource != nil else { return }

        let cleanedSubject = Self.cleanedSubject(event.subject)
        guard !cleanedSubject.isEmpty else { return }

        var updatedEntry = SourceActivityEntry(
            source: event.source.trimmingCharacters(in: .whitespacesAndNewlines),
            action: event.action,
            subjects: [cleanedSubject],
            timestamp: event.timestamp
        )

        if let matchingIndex = entries.firstIndex(where: { entry in
            Self.normalizedSource(entry.source) == normalizedSource &&
            entry.action == event.action &&
            abs(entry.timestamp.timeIntervalSince(event.timestamp)) <= groupingWindow
        }) {
            let existing = entries.remove(at: matchingIndex)
            updatedEntry = mergedEntry(existing: existing, event: event, subject: cleanedSubject)
        }

        entries.append(updatedEntry)
        entries.sort { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp > rhs.timestamp
            }
            if lhs.source != rhs.source {
                return lhs.source < rhs.source
            }
            return lhs.action.rawValue < rhs.action.rawValue
        }
        if entries.count > maximumEntryCount {
            entries.removeLast(entries.count - maximumEntryCount)
        }
    }

    public mutating func record(
        fileWatcherEvents: [FileWatcherEvent],
        upsertedRecordsByPath: [String: TaskRecord],
        existingRecordsByPath: [String: TaskRecord]
    ) {
        let burstPaths = Set(fileWatcherEvents.flatMap { event -> [String] in
            guard case .rateLimitedBatch(let paths, _, _) = event else { return [] }
            return paths
        })

        let mappedActivityEvents = fileWatcherEvents.flatMap { event in
            activityEvents(
                from: event,
                burstPaths: burstPaths,
                upsertedRecordsByPath: upsertedRecordsByPath,
                existingRecordsByPath: existingRecordsByPath
            )
        }
        record(mappedActivityEvents)
    }

    public func recentEntries(limit: Int = Int.max) -> [SourceActivityEntry] {
        Array(entries.prefix(max(0, limit)))
    }

    public mutating func reset() {
        entries.removeAll(keepingCapacity: false)
    }

    private func mergedEntry(
        existing: SourceActivityEntry,
        event: SourceActivityEvent,
        subject: String
    ) -> SourceActivityEntry {
        var subjects = existing.subjects
        if !subjects.contains(subject) {
            if event.timestamp >= existing.timestamp {
                subjects.append(subject)
            } else {
                subjects.insert(subject, at: 0)
            }
        }

        return SourceActivityEntry(
            source: existing.source,
            action: existing.action,
            subjects: subjects,
            timestamp: max(existing.timestamp, event.timestamp)
        )
    }

    private func activityEvents(
        from event: FileWatcherEvent,
        burstPaths: Set<String>,
        upsertedRecordsByPath: [String: TaskRecord],
        existingRecordsByPath: [String: TaskRecord]
    ) -> [SourceActivityEvent] {
        switch event {
        case .created(let path, let source, let timestamp):
            guard !burstPaths.contains(path) else { return [] }
            guard let event = buildEvent(
                action: .created,
                path: path,
                source: source ?? upsertedRecordsByPath[path]?.document.frontmatter.source,
                timestamp: timestamp,
                preferredSubject: upsertedRecordsByPath[path]?.document.frontmatter.title
            ) else {
                return []
            }
            return [event]
        case .modified(let path, let source, let timestamp):
            let priorStatus = existingRecordsByPath[path]?.document.frontmatter.status
            let currentStatus = upsertedRecordsByPath[path]?.document.frontmatter.status
            let action: SourceActivityEvent.Action
            if priorStatus != .done, currentStatus == .done {
                action = .completed
            } else {
                action = .modified
            }

            guard let event = buildEvent(
                action: action,
                path: path,
                source: source ?? upsertedRecordsByPath[path]?.document.frontmatter.source ?? existingRecordsByPath[path]?.document.frontmatter.source,
                timestamp: timestamp,
                preferredSubject: upsertedRecordsByPath[path]?.document.frontmatter.title ?? existingRecordsByPath[path]?.document.frontmatter.title
            ) else {
                return []
            }
            return [event]
        case .deleted(let path, let timestamp):
            guard let event = buildEvent(
                action: .deleted,
                path: path,
                source: existingRecordsByPath[path]?.document.frontmatter.source,
                timestamp: timestamp,
                preferredSubject: existingRecordsByPath[path]?.document.frontmatter.title
            ) else {
                return []
            }
            return [event]
        case .conflict(let path, let timestamp):
            guard let event = buildEvent(
                action: .conflicted,
                path: path,
                source: upsertedRecordsByPath[path]?.document.frontmatter.source ?? existingRecordsByPath[path]?.document.frontmatter.source,
                timestamp: timestamp,
                preferredSubject: upsertedRecordsByPath[path]?.document.frontmatter.title ?? existingRecordsByPath[path]?.document.frontmatter.title
            ) else {
                return []
            }
            return [event]
        case .unparseable(let path, _, let timestamp):
            guard let event = buildEvent(
                action: .unreadable,
                path: path,
                source: existingRecordsByPath[path]?.document.frontmatter.source,
                timestamp: timestamp,
                preferredSubject: existingRecordsByPath[path]?.document.frontmatter.title
            ) else {
                return []
            }
            return [event]
        case .rateLimitedBatch(let paths, let source, let timestamp):
            return paths.compactMap { path in
                buildEvent(
                    action: .created,
                    path: path,
                    source: source ?? upsertedRecordsByPath[path]?.document.frontmatter.source ?? existingRecordsByPath[path]?.document.frontmatter.source,
                    timestamp: timestamp,
                    preferredSubject: upsertedRecordsByPath[path]?.document.frontmatter.title ?? existingRecordsByPath[path]?.document.frontmatter.title
                )
            }
        }
    }

    private func buildEvent(
        action: SourceActivityEvent.Action,
        path: String,
        source: String?,
        timestamp: Date,
        preferredSubject: String?
    ) -> SourceActivityEvent? {
        guard let cleanedSource = Self.cleanedSource(source) else { return nil }
        let subject = Self.cleanedSubject(preferredSubject ?? fallbackSubject(for: path))
        guard !subject.isEmpty else { return nil }
        return SourceActivityEvent(action: action, source: cleanedSource, subject: subject, timestamp: timestamp)
    }

    private static func cleanedSource(_ source: String?) -> String? {
        guard let trimmed = source?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }

        let normalized = normalizedSource(trimmed)
        guard normalized != nil, normalized != "unknown", normalized != "user" else {
            return nil
        }
        return trimmed
    }

    private static func cleanedSubject(_ subject: String) -> String {
        subject.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedSource(_ source: String) -> String? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }

    private func fallbackSubject(for path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let stem = url.deletingPathExtension().lastPathComponent
        if stem.isEmpty {
            return path
        }
        return stem
    }
}
