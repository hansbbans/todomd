import Foundation

public final class FileWatcherService {
    public struct RateLimitPolicy: Sendable {
        public var threshold: Int
        public var windowSeconds: TimeInterval

        public init(threshold: Int = 50, windowSeconds: TimeInterval = 60) {
            self.threshold = threshold
            self.windowSeconds = windowSeconds
        }
    }

    private let rootURL: URL
    private let fileIO: TaskFileIO
    private let repository: TaskRepository
    private let rateLimitPolicy: RateLimitPolicy
    private let conflictDetectionEnabled: Bool
    private var fingerprints: [String: TaskFileFingerprint]
    private var selfWriteJournal: [String: Date]
    private var createdEventTimestamps: [Date]
    private(set) public var parseDiagnostics: [ParseFailureDiagnostic]
    private(set) public var lastPerformance: FileWatcherPerformance?

    public init(
        rootURL: URL,
        repository: TaskRepository,
        fileIO: TaskFileIO = TaskFileIO(),
        rateLimitPolicy: RateLimitPolicy = RateLimitPolicy(),
        conflictDetectionEnabled: Bool = true
    ) {
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        self.repository = repository
        self.fileIO = fileIO
        self.rateLimitPolicy = rateLimitPolicy
        self.conflictDetectionEnabled = conflictDetectionEnabled
        self.fingerprints = [:]
        self.selfWriteJournal = [:]
        self.createdEventTimestamps = []
        self.parseDiagnostics = []
        self.lastPerformance = nil
    }

    public func markSelfWrite(path: String, modificationDate: Date = Date()) {
        selfWriteJournal[path] = modificationDate
    }

    public func synchronize(now: Date = Date()) throws -> (summary: SyncSummary, events: [FileWatcherEvent], records: [TaskRecord]) {
        purgeStaleSelfWrites(reference: now)

        let enumerateStart = ContinuousClock.now
        let discoveredFingerprints = try fileIO.enumerateMarkdownFingerprints(rootURL: rootURL)
        let enumerateMilliseconds = elapsedMilliseconds(since: enumerateStart)
        var newFingerprints: [String: TaskFileFingerprint] = [:]
        var changedPaths: [String] = []
        var createdPaths: [String] = []
        var events: [FileWatcherEvent] = []

        for fingerprint in discoveredFingerprints {
            newFingerprints[fingerprint.path] = fingerprint

            if let previous = fingerprints[fingerprint.path] {
                if previous != fingerprint {
                    if conflictDetectionEnabled,
                       let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: URL(fileURLWithPath: fingerprint.path)),
                       !conflicts.isEmpty
                    {
                        events.append(.conflict(path: fingerprint.path, timestamp: now))
                    }
                    if !isSelfWrite(path: fingerprint.path, modificationDate: fingerprint.modificationDate) {
                        changedPaths.append(fingerprint.path)
                    }
                }
            } else {
                if conflictDetectionEnabled,
                   let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: URL(fileURLWithPath: fingerprint.path)),
                   !conflicts.isEmpty
                {
                    events.append(.conflict(path: fingerprint.path, timestamp: now))
                }
                createdPaths.append(fingerprint.path)
                if !isSelfWrite(path: fingerprint.path, modificationDate: fingerprint.modificationDate) {
                    changedPaths.append(fingerprint.path)
                }
            }
        }

        let deletedPaths = Set(fingerprints.keys).subtracting(newFingerprints.keys)

        var records: [TaskRecord] = []
        var failed = 0
        var parseMilliseconds = 0.0

        recordCreations(count: createdPaths.count, at: now)
        let isRateLimited = creationsInWindow(reference: now) > rateLimitPolicy.threshold

        var sourceCounts: [String: Int] = [:]

        let sortedChangedPaths = changedPaths.sorted()
        let chunks: [[String]]
        if isRateLimited {
            chunks = sortedChangedPaths.chunked(into: max(1, rateLimitPolicy.threshold))
        } else {
            chunks = [sortedChangedPaths]
        }

        for batch in chunks {
            for path in batch {
                let parseStart = ContinuousClock.now
                do {
                    let record = try repository.load(path: path)
                    records.append(record)
                    sourceCounts[record.document.frontmatter.source, default: 0] += 1

                    if fingerprints[path] == nil {
                        events.append(.created(path: path, source: record.document.frontmatter.source, timestamp: now))
                    } else {
                        events.append(.modified(path: path, source: record.document.frontmatter.source, timestamp: now))
                    }
                } catch {
                    failed += 1
                    parseDiagnostics.append(
                        ParseFailureDiagnostic(path: path, reason: error.localizedDescription, timestamp: now)
                    )
                    events.append(.unparseable(path: path, reason: error.localizedDescription, timestamp: now))
                }
                parseMilliseconds += elapsedMilliseconds(since: parseStart)
            }
        }

        if isRateLimited, !createdPaths.isEmpty {
            let attributedSource = sourceCounts.max(by: { $0.value < $1.value })?.key
            events.append(.rateLimitedBatch(paths: createdPaths.sorted(), source: attributedSource, timestamp: now))
        }

        for path in deletedPaths.sorted() {
            events.append(.deleted(path: path, timestamp: now))
        }

        fingerprints = newFingerprints
        lastPerformance = FileWatcherPerformance(
            enumerateMilliseconds: enumerateMilliseconds,
            parseMilliseconds: parseMilliseconds
        )

        let summary = SyncSummary(
            ingestedCount: records.count,
            failedCount: failed,
            deletedCount: deletedPaths.count,
            conflictCount: events.reduce(into: 0) { count, event in
                if case .conflict = event { count += 1 }
            },
            timestamp: now
        )

        return (summary, events, records)
    }

    private func elapsedMilliseconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now)
        let seconds = Double(duration.components.seconds)
        let attoseconds = Double(duration.components.attoseconds)
        return (seconds * 1_000) + (attoseconds / 1_000_000_000_000_000)
    }

    private func isSelfWrite(path: String, modificationDate: Date) -> Bool {
        guard let writeDate = selfWriteJournal[path] else { return false }
        return abs(writeDate.timeIntervalSince(modificationDate)) <= 2
    }

    private func purgeStaleSelfWrites(reference: Date) {
        selfWriteJournal = selfWriteJournal.filter { _, value in
            abs(reference.timeIntervalSince(value)) <= 2
        }
    }

    private func recordCreations(count: Int, at date: Date) {
        guard count > 0 else {
            createdEventTimestamps = createdEventTimestamps.filter {
                abs(date.timeIntervalSince($0)) <= rateLimitPolicy.windowSeconds
            }
            return
        }

        createdEventTimestamps.append(contentsOf: Array(repeating: date, count: count))
        createdEventTimestamps = createdEventTimestamps.filter {
            abs(date.timeIntervalSince($0)) <= rateLimitPolicy.windowSeconds
        }
    }

    private func creationsInWindow(reference: Date) -> Int {
        createdEventTimestamps = createdEventTimestamps.filter {
            abs(reference.timeIntervalSince($0)) <= rateLimitPolicy.windowSeconds
        }
        return createdEventTimestamps.count
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var chunks: [[Element]] = []
        chunks.reserveCapacity((count / size) + 1)

        var index = startIndex
        while index < endIndex {
            let nextIndex = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(Array(self[index..<nextIndex]))
            index = nextIndex
        }

        return chunks
    }
}
