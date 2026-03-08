import Foundation
#if os(macOS)
import CoreServices
#endif

public final class FileWatcherService: @unchecked Sendable {
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
    private var knownDirectories: Set<String>
    private var selfWriteJournal: [String: Date]
    private var createdEventTimestamps: [Date]
    private(set) public var parseDiagnostics: [ParseFailureDiagnostic]
    private(set) public var lastPerformance: FileWatcherPerformance?
#if os(macOS)
    private let fileEventStream: FileEventStream?
#endif

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
        self.knownDirectories = []
        self.selfWriteJournal = [:]
        self.createdEventTimestamps = []
        self.parseDiagnostics = []
        self.lastPerformance = nil
#if os(macOS)
        self.fileEventStream = FileEventStream(rootURL: self.rootURL)
#endif
    }

    public func markSelfWrite(path: String, modificationDate: Date = Date()) {
        selfWriteJournal[path] = modificationDate
    }

    public func prime(fingerprints: [TaskFileFingerprint]) {
        self.fingerprints = Dictionary(uniqueKeysWithValues: fingerprints.map { ($0.path, $0) })
        self.knownDirectories = buildKnownDirectories(from: fingerprints.map(\.path))
    }

    public func currentFingerprints() -> [TaskFileFingerprint] {
        fingerprints.values.sorted { $0.path < $1.path }
    }

    public func synchronize(
        now: Date = Date(),
        forceFullScan: Bool = false
    ) throws -> (summary: SyncSummary, events: [FileWatcherEvent], records: [TaskRecord]) {
        purgeStaleSelfWrites(reference: now)

        let enumerateStart = ContinuousClock.now
        let discovery = try discoverChanges(forceFullScan: forceFullScan)
        let enumerateMilliseconds = elapsedMilliseconds(since: enumerateStart)
        let newFingerprints = discovery.fingerprints
        let changedPaths = discovery.changedPaths
        let createdPaths = discovery.createdPaths
        var events: [FileWatcherEvent] = []
        let deletedPaths = discovery.deletedPaths

        var failed = 0
        var parseMilliseconds = 0.0

        recordCreations(count: createdPaths.count, at: now)
        let isRateLimited = creationsInWindow(reference: now) > rateLimitPolicy.threshold

        var sourceCounts: [String: Int] = [:]
        var successfulPaths: [String] = []
        var newParseDiagnostics: [ParseFailureDiagnostic] = []

        let sortedChangedPaths = changedPaths.sorted()
        for path in sortedChangedPaths where hasConflicts(at: path) {
            events.append(.conflict(path: path, timestamp: now))
        }
        let chunks: [[String]]
        if isRateLimited {
            chunks = sortedChangedPaths.chunked(into: max(1, rateLimitPolicy.threshold))
        } else {
            chunks = [sortedChangedPaths]
        }

        var records: [TaskRecord] = []
        for batch in chunks {
            let parseResults = parseBatch(batch, timestamp: now)
            for result in parseResults {
                parseMilliseconds += result.parseMilliseconds
                switch result.outcome {
                case .record(let record):
                    records.append(record)
                    successfulPaths.append(result.path)
                    sourceCounts[record.document.frontmatter.source, default: 0] += 1

                    if fingerprints[result.path] == nil {
                        events.append(.created(path: result.path, source: record.document.frontmatter.source, timestamp: now))
                    } else {
                        events.append(.modified(path: result.path, source: record.document.frontmatter.source, timestamp: now))
                    }
                case .failure(let diagnostic):
                    failed += 1
                    newParseDiagnostics.append(diagnostic)
                    events.append(.unparseable(path: result.path, reason: diagnostic.reason, timestamp: now))
                }
            }
        }

        if isRateLimited, !createdPaths.isEmpty {
            let attributedSource = sourceCounts.max(by: { $0.value < $1.value })?.key
            events.append(.rateLimitedBatch(paths: createdPaths.sorted(), source: attributedSource, timestamp: now))
        }

        for path in deletedPaths.sorted() {
            events.append(.deleted(path: path, timestamp: now))
        }

        let clearedPaths = Set(successfulPaths).union(deletedPaths)
        parseDiagnostics = parseDiagnostics.filter { !clearedPaths.contains($0.path) }
        parseDiagnostics.append(contentsOf: newParseDiagnostics)
        fingerprints = newFingerprints
        knownDirectories = discovery.knownDirectories
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

    private func discoverChanges(forceFullScan: Bool) throws -> FingerprintDiscovery {
        if forceFullScan {
            discardPendingFileEventsBeforeFullDiscovery()
            return try fullDiscovery()
        }
        if !fingerprints.isEmpty, fingerprints.count <= 128 {
            discardPendingFileEventsBeforeFullDiscovery()
            return try fullDiscovery()
        }
#if os(macOS)
        if !fingerprints.isEmpty, let fileEventStream {
            let pending = fileEventStream.takePendingChanges()
            if !pending.requiresFullRescan {
                if pending.events.isEmpty {
                    lastPerformance = FileWatcherPerformance(enumerateMilliseconds: 0, parseMilliseconds: 0)
                    return FingerprintDiscovery(
                        fingerprints: fingerprints,
                        knownDirectories: knownDirectories,
                        changedPaths: [],
                        createdPaths: [],
                        deletedPaths: [],
                        usedIncrementalScan: true
                    )
                }
                return try incrementalDiscovery(changedEvents: pending.events)
            }
        }
#endif

        discardPendingFileEventsBeforeFullDiscovery()
        return try fullDiscovery()
    }

    private func fullDiscovery() throws -> FingerprintDiscovery {
        let discoveredFingerprints = try fileIO.enumerateMarkdownFingerprints(rootURL: rootURL)
        var newFingerprints: [String: TaskFileFingerprint] = [:]
        var changedPaths: [String] = []
        var createdPaths: [String] = []

        for fingerprint in discoveredFingerprints {
            newFingerprints[fingerprint.path] = fingerprint

            if let previous = fingerprints[fingerprint.path] {
                if previous != fingerprint {
                    if hasConflicts(at: fingerprint.path) {
                        // Conflict event is appended in synchronize.
                    }
                    if !isSelfWrite(path: fingerprint.path, modificationDate: fingerprint.modificationDate) {
                        changedPaths.append(fingerprint.path)
                    }
                }
            } else {
                createdPaths.append(fingerprint.path)
                if !isSelfWrite(path: fingerprint.path, modificationDate: fingerprint.modificationDate) {
                    changedPaths.append(fingerprint.path)
                }
            }
        }

        let deletedPaths = Set(fingerprints.keys).subtracting(newFingerprints.keys)
        return FingerprintDiscovery(
            fingerprints: newFingerprints,
            knownDirectories: buildKnownDirectories(from: discoveredFingerprints.map(\.path)),
            changedPaths: changedPaths,
            createdPaths: createdPaths,
            deletedPaths: deletedPaths,
            usedIncrementalScan: false
        )
    }

#if os(macOS)
    private func incrementalDiscovery(changedEvents: [PendingFileEvent]) throws -> FingerprintDiscovery {
        var changedPaths: Set<String> = []
        var directoryHints: Set<String> = []
        var fileEventDirectories: Set<String> = []
        var fileHints: Set<String> = []

        for event in changedEvents {
            let normalized = URL(fileURLWithPath: event.path).standardizedFileURL.resolvingSymlinksInPath().path
            guard isPathWithinRoot(normalized), !isIgnoredWatchPath(normalized) else { continue }

            changedPaths.insert(normalized)

            if event.isDirectoryHint {
                directoryHints.insert(normalized)
                continue
            }

            if event.isFileHint, let parentDirectory = parentDirectoryPath(for: normalized) {
                fileHints.insert(normalized)
                fileEventDirectories.insert(parentDirectory)
            }
        }

        return try incrementalDiscovery(
            changedEventPaths: Array(changedPaths),
            directoryHints: directoryHints,
            fileEventDirectories: fileEventDirectories,
            fileHints: fileHints
        )
    }
#endif

    private func incrementalDiscovery(
        changedEventPaths: [String],
        directoryHints: Set<String> = [],
        fileEventDirectories initialFileEventDirectories: Set<String> = [],
        fileHints: Set<String> = []
    ) throws -> FingerprintDiscovery {
        var updatedFingerprints = fingerprints
        var updatedKnownDirectories = knownDirectories
        var changedPaths: Set<String> = []
        var createdPaths: Set<String> = []
        var deletedPaths: Set<String> = []
        var dirtyDirectories: Set<String> = []
        var fileEventDirectories = initialFileEventDirectories

        for rawPath in changedEventPaths {
            let normalized = URL(fileURLWithPath: rawPath).standardizedFileURL.resolvingSymlinksInPath().path
            guard isPathWithinRoot(normalized), !isIgnoredWatchPath(normalized) else { continue }

            if URL(fileURLWithPath: normalized).pathExtension.lowercased() == "md" {
                if let parentDirectory = parentDirectoryPath(for: normalized) {
                    fileEventDirectories.insert(parentDirectory)
                }
                guard fileIO.shouldTrackMarkdownFile(path: normalized) else {
                    if updatedFingerprints.removeValue(forKey: normalized) != nil {
                        deletedPaths.insert(normalized)
                        updatedKnownDirectories = buildKnownDirectories(from: updatedFingerprints.keys)
                    }
                    continue
                }
                if fileIO.directoryExists(path: normalized) {
                    dirtyDirectories.insert(normalized)
                    continue
                }

                if FileManager.default.fileExists(atPath: normalized) {
                    let fingerprint = try fileIO.fingerprint(for: normalized)
                    let previous = updatedFingerprints.updateValue(fingerprint, forKey: normalized)
                    if previous == nil {
                        createdPaths.insert(normalized)
                        updatedKnownDirectories = buildKnownDirectories(from: updatedFingerprints.keys)
                    } else if previous != fingerprint, !isSelfWrite(path: normalized, modificationDate: fingerprint.modificationDate) {
                        changedPaths.insert(normalized)
                    }
                } else {
                    if updatedFingerprints.removeValue(forKey: normalized) != nil {
                        deletedPaths.insert(normalized)
                        updatedKnownDirectories = buildKnownDirectories(from: updatedFingerprints.keys)
                    }
                }
                continue
            }

            if directoryHints.contains(normalized) || fileIO.directoryExists(path: normalized) {
                if isPathWithinRoot(normalized) {
                    dirtyDirectories.insert(normalized)
                }
                continue
            }

            if fileHints.contains(normalized) {
                continue
            }

            guard directoryHints.contains(normalized) || hasKnownDescendants(at: normalized, in: updatedKnownDirectories) else {
                continue
            }

            let deletedNestedPaths = updatedFingerprints.keys.filter { isPath($0, withinDirectory: normalized) }
            if !deletedNestedPaths.isEmpty {
                for deletedPath in deletedNestedPaths {
                    updatedFingerprints.removeValue(forKey: deletedPath)
                    deletedPaths.insert(deletedPath)
                }
                updatedKnownDirectories = buildKnownDirectories(from: updatedFingerprints.keys)
            }
        }

        let filteredDirtyDirectories = dirtyDirectories.filter { directoryPath in
            !fileEventDirectories.contains { fileEventDirectory in
                fileEventDirectory == directoryPath || isPath(fileEventDirectory, withinDirectory: directoryPath)
            }
        }

        for directoryPath in collapsedDirectories(filteredDirtyDirectories) {
            let directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
            let rescannedFingerprints = try fileIO.enumerateMarkdownFingerprints(in: directoryURL)
            let rescannedByPath = Dictionary(uniqueKeysWithValues: rescannedFingerprints.map { ($0.path, $0) })
            let existingPaths = updatedFingerprints.keys.filter { isPath($0, withinDirectory: directoryPath) }

            for existingPath in existingPaths where rescannedByPath[existingPath] == nil {
                updatedFingerprints.removeValue(forKey: existingPath)
                deletedPaths.insert(existingPath)
            }

            for fingerprint in rescannedFingerprints {
                let previous = updatedFingerprints.updateValue(fingerprint, forKey: fingerprint.path)
                if previous == nil {
                    createdPaths.insert(fingerprint.path)
                    updatedKnownDirectories = buildKnownDirectories(from: updatedFingerprints.keys)
                } else if previous != fingerprint, !isSelfWrite(path: fingerprint.path, modificationDate: fingerprint.modificationDate) {
                    changedPaths.insert(fingerprint.path)
                }
            }
        }

        return FingerprintDiscovery(
            fingerprints: updatedFingerprints,
            knownDirectories: updatedKnownDirectories,
            changedPaths: Array(changedPaths.subtracting(createdPaths)),
            createdPaths: Array(createdPaths),
            deletedPaths: deletedPaths,
            usedIncrementalScan: true
        )
    }

    private func collapsedDirectories(_ directories: Set<String>) -> [String] {
        directories.sorted().filter { candidate in
            !directories.contains { other in
                other != candidate && isPath(candidate, withinDirectory: other)
            }
        }
    }

    private func parentDirectoryPath(for path: String) -> String? {
        let parentPath = URL(fileURLWithPath: path).deletingLastPathComponent().path
        guard isPathWithinRoot(parentPath) else { return nil }
        return parentPath
    }

    private func isPathWithinRoot(_ path: String) -> Bool {
        path == rootURL.path || path.hasPrefix(rootURL.path + "/")
    }

    private func isIgnoredWatchPath(_ path: String) -> Bool {
        guard path != rootURL.path else { return false }
        let relativePath = path.dropFirst(rootURL.path.count)
        return relativePath.split(separator: "/").contains { $0.hasPrefix(".") }
    }

    private func hasKnownDescendants(at path: String, in knownDirectories: Set<String>) -> Bool {
        knownDirectories.contains(path)
    }

    private func isPath(_ path: String, withinDirectory directoryPath: String) -> Bool {
        path == directoryPath || path.hasPrefix(directoryPath + "/")
    }

    private func discardPendingFileEventsBeforeFullDiscovery() {
#if os(macOS)
        _ = fileEventStream?.takePendingChanges()
#endif
    }

    private func buildKnownDirectories<S: Sequence>(from paths: S) -> Set<String> where S.Element == String {
        var directories: Set<String> = []
        for path in paths {
            var current = URL(fileURLWithPath: path).deletingLastPathComponent().path
            while isPathWithinRoot(current) && current != rootURL.path {
                directories.insert(current)
                let parent = URL(fileURLWithPath: current).deletingLastPathComponent().path
                if parent == current {
                    break
                }
                current = parent
            }
            if current == rootURL.path {
                directories.insert(current)
            }
        }
        return directories
    }

    private func hasConflicts(at path: String) -> Bool {
        guard conflictDetectionEnabled else { return false }
        guard let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: URL(fileURLWithPath: path)) else {
            return false
        }
        return !conflicts.isEmpty
    }

    private func parseBatch(_ paths: [String], timestamp: Date) -> [ParsedPathResult] {
        if paths.count < 32 {
            return paths.map { path in
                let parseStart = ContinuousClock.now
                do {
                    let record = try repository.load(path: path)
                    return ParsedPathResult(
                        path: path,
                        parseMilliseconds: elapsedMilliseconds(since: parseStart),
                        outcome: .record(record)
                    )
                } catch {
                    return ParsedPathResult(
                        path: path,
                        parseMilliseconds: elapsedMilliseconds(since: parseStart),
                        outcome: .failure(
                            ParseFailureDiagnostic(path: path, reason: error.localizedDescription, timestamp: timestamp)
                        )
                    )
                }
            }
        }

        let collector = ParsedPathResultCollector()

        DispatchQueue.concurrentPerform(iterations: paths.count) { index in
            let path = paths[index]
            let parseStart = ContinuousClock.now
            let result: ParsedPathResult
            do {
                let record = try repository.load(path: path)
                result = ParsedPathResult(
                    path: path,
                    parseMilliseconds: elapsedMilliseconds(since: parseStart),
                    outcome: .record(record)
                )
            } catch {
                result = ParsedPathResult(
                    path: path,
                    parseMilliseconds: elapsedMilliseconds(since: parseStart),
                    outcome: .failure(
                        ParseFailureDiagnostic(path: path, reason: error.localizedDescription, timestamp: timestamp)
                    )
                )
            }

            collector.append(result)
        }

        return collector.results.sorted { $0.path < $1.path }
    }
}

private struct ParsedPathResult {
    enum Outcome {
        case record(TaskRecord)
        case failure(ParseFailureDiagnostic)
    }

    var path: String
    var parseMilliseconds: Double
    var outcome: Outcome
}

private final class ParsedPathResultCollector: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var results: [ParsedPathResult] = []

    func append(_ result: ParsedPathResult) {
        lock.lock()
        results.append(result)
        lock.unlock()
    }
}

private struct FingerprintDiscovery {
    var fingerprints: [String: TaskFileFingerprint]
    var knownDirectories: Set<String>
    var changedPaths: [String]
    var createdPaths: [String]
    var deletedPaths: Set<String>
    var usedIncrementalScan: Bool
}

#if os(macOS)
private struct PendingFileEventChanges {
    var events: [PendingFileEvent]
    var requiresFullRescan: Bool
}

private struct PendingFileEvent {
    var path: String
    var flags: FSEventStreamEventFlags

    var isDirectoryHint: Bool {
        flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0
    }

    var isFileHint: Bool {
        flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile) != 0
    }
}

private final class FileEventStream: @unchecked Sendable {
    private let queue = DispatchQueue(label: "todo-md.file-events")
    private let lock = NSLock()
    private var pendingEventsByPath: [String: FSEventStreamEventFlags] = [:]
    private var requiresFullRescan = false
    private var stream: FSEventStreamRef?

    init?(rootURL: URL) {
        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagWatchRoot
        )

        guard let stream = FSEventStreamCreate(
            nil,
            { _, info, eventCount, eventPathsPointer, eventFlagsPointer, _ in
                guard let info else { return }
                let fileEventStream = Unmanaged<FileEventStream>.fromOpaque(info).takeUnretainedValue()
                let paths = Unmanaged<CFArray>.fromOpaque(eventPathsPointer).takeUnretainedValue() as NSArray as? [String] ?? []
                let flagsBuffer = UnsafeBufferPointer(start: eventFlagsPointer, count: Int(eventCount))
                fileEventStream.capture(paths: paths, flags: Array(flagsBuffer))
            },
            &context,
            [rootURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.01,
            flags
        ) else {
            return nil
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            return nil
        }
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    func takePendingChanges() -> PendingFileEventChanges {
        if let stream {
            FSEventStreamFlushSync(stream)
        }

        lock.lock()
        let snapshot = PendingFileEventChanges(
            events: pendingEventsByPath
                .map { PendingFileEvent(path: $0.key, flags: $0.value) }
                .sorted { $0.path < $1.path },
            requiresFullRescan: requiresFullRescan
        )
        pendingEventsByPath.removeAll()
        requiresFullRescan = false
        lock.unlock()
        return snapshot
    }

    private func capture(paths: [String], flags: [FSEventStreamEventFlags]) {
        lock.lock()
        for (path, flag) in zip(paths, flags) {
            if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0
                || flag & FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped) != 0
                || flag & FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped) != 0
                || flag & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 {
                requiresFullRescan = true
            }
            pendingEventsByPath[path, default: 0] |= flag
        }
        lock.unlock()
    }
}
#endif

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
