import Foundation

public struct TaskFileIO {
    public var fileManager: FileManager

    private static let ignoredMarkdownFilenames: Set<String> = ["agents.md"]

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func enumerateMarkdownFiles(rootURL: URL) throws -> [URL] {
        try enumerateMarkdownFiles(in: rootURL)
    }

    public func enumerateMarkdownFiles(in directoryURL: URL) throws -> [URL] {
        let normalizedRoot = directoryURL.standardizedFileURL.resolvingSymlinksInPath()
        guard let enumerator = fileManager.enumerator(
            at: normalizedRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            guard shouldTrackMarkdownFile(url) else { continue }
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            let values = try resolved.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory != true else { continue }
            urls.append(resolved)
        }

        return urls.sorted { $0.path < $1.path }
    }

    public func enumerateMarkdownFingerprints(rootURL: URL) throws -> [TaskFileFingerprint] {
        try enumerateMarkdownFingerprints(in: rootURL)
    }

    public func enumerateMarkdownFingerprints(in directoryURL: URL) throws -> [TaskFileFingerprint] {
        let normalizedRoot = directoryURL.standardizedFileURL.resolvingSymlinksInPath()
        guard let enumerator = fileManager.enumerator(
            at: normalizedRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var fingerprints: [TaskFileFingerprint] = []
        for case let url as URL in enumerator {
            guard shouldTrackMarkdownFile(url) else { continue }
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            let values = try resolved.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            if values.isDirectory == true {
                continue
            }
            fingerprints.append(
                TaskFileFingerprint(
                    path: resolved.path,
                    fileSize: UInt64(values.fileSize ?? 0),
                    modificationDate: values.contentModificationDate ?? Date.distantPast
                )
            )
        }

        return fingerprints.sorted { $0.path < $1.path }
    }

    public func enumerateDirectories(rootURL: URL) throws -> [URL] {
        let normalizedRoot = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        guard let enumerator = fileManager.enumerator(
            at: normalizedRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [normalizedRoot]
        }

        var directories: [URL] = [normalizedRoot]
        for case let url as URL in enumerator {
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            let values = try resolved.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }
            directories.append(resolved)
        }

        return directories.sorted { $0.path < $1.path }
    }

    public func enumerateDirectoryFingerprints(rootURL: URL) throws -> [TaskDirectoryFingerprint] {
        let directories = try enumerateDirectories(rootURL: rootURL)
        return try directories.map { directory in
            let values = try directory.resourceValues(forKeys: [.contentModificationDateKey])
            return TaskDirectoryFingerprint(
                path: directory.path,
                modificationDate: values.contentModificationDate ?? .distantPast
            )
        }
    }

    public func directoryExists(path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { return false }
        return isDirectory.boolValue
    }

    public func read(path: String) throws -> String {
        let data = try readData(path: path)
        guard let content = String(data: data, encoding: .utf8) else {
            throw TaskError.ioFailure("Failed to decode UTF-8 file at \(path)")
        }
        return content
    }

    public func readData(path: String) throws -> Data {
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        guard fileManager.fileExists(atPath: url.path) else {
            throw TaskError.fileNotFound(path)
        }

        let requiresCoordinatedAccess = try ensureLocalAvailability(for: url)
        if !requiresCoordinatedAccess {
            do {
                return try Data(contentsOf: url, options: [.mappedIfSafe])
            } catch {
                throw TaskError.ioFailure("Failed to read file at \(path): \(error.localizedDescription)")
            }
        }

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var readError: Error?
        var data = Data()
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do {
                data = try Data(contentsOf: coordinatedURL, options: [.mappedIfSafe])
            } catch {
                readError = error
            }
        }

        if let coordinationError {
            throw TaskError.ioFailure("Failed to read file at \(path): \(coordinationError.localizedDescription)")
        }

        if let readError {
            throw TaskError.ioFailure("Failed to read file at \(path): \(readError.localizedDescription)")
        }

        return data
    }

    @discardableResult
    private func ensureLocalAvailability(for url: URL) throws -> Bool {
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        let values = try url.resourceValues(forKeys: keys)
        guard values.isUbiquitousItem == true else { return false }

        if values.ubiquitousItemDownloadingStatus == URLUbiquitousItemDownloadingStatus.current {
            return true
        }

        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.startDownloadingUbiquitousItem(at: url)
        }

        throw TaskError.ioFailure("iCloud file is not downloaded yet: \(url.path)")
    }

    public func write(path: String, content: String) throws {
        guard let data = content.data(using: .utf8) else {
            throw TaskError.ioFailure("Failed to encode UTF-8 file at \(path)")
        }
        try writeData(path: path, data: data)
    }

    public func writeData(path: String, data: Data) throws {
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let requiresCoordinatedAccess = (try? ensureLocalAvailability(for: url)) ?? false
        if !requiresCoordinatedAccess {
            do {
                try data.write(to: url, options: .atomic)
                return
            } catch {
                throw TaskError.ioFailure("Failed to write file at \(path): \(error.localizedDescription)")
            }
        }

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var writeError: Error?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                try data.write(to: coordinatedURL, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let coordinationError {
            throw TaskError.ioFailure("Failed to write file at \(path): \(coordinationError.localizedDescription)")
        }

        if let writeError {
            throw TaskError.ioFailure("Failed to write file at \(path): \(writeError.localizedDescription)")
        }
    }

    public func delete(path: String) throws {
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        guard fileManager.fileExists(atPath: url.path) else { return }

        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw TaskError.ioFailure("Failed to delete file at \(path): \(error.localizedDescription)")
        }
    }

    public func fingerprint(for path: String) throws -> TaskFileFingerprint {
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return TaskFileFingerprint(
            path: url.path,
            fileSize: UInt64(values.fileSize ?? 0),
            modificationDate: values.contentModificationDate ?? Date.distantPast
        )
    }

    public func shouldTrackMarkdownFile(_ url: URL) -> Bool {
        let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
        guard normalized.pathExtension.lowercased() == "md" else { return false }
        return !Self.ignoredMarkdownFilenames.contains(normalized.lastPathComponent.lowercased())
    }

    public func shouldTrackMarkdownFile(path: String) -> Bool {
        shouldTrackMarkdownFile(URL(fileURLWithPath: path))
    }
}

public struct TaskSnapshotHydration: Sendable {
    public let records: [TaskRecord]
    public let fingerprints: [TaskFileFingerprint]
    public let metadataEntries: [TaskMetadataEntry]
    public let failures: [ParseFailureDiagnostic]
    public let requiresValidation: Bool

    public init(
        records: [TaskRecord],
        fingerprints: [TaskFileFingerprint],
        metadataEntries: [TaskMetadataEntry],
        failures: [ParseFailureDiagnostic],
        requiresValidation: Bool
    ) {
        self.records = records
        self.fingerprints = fingerprints
        self.metadataEntries = metadataEntries
        self.failures = failures
        self.requiresValidation = requiresValidation
    }
}

public struct TaskDirectoryFingerprint: Hashable, Sendable {
    public let path: String
    public let modificationDate: Date

    public init(path: String, modificationDate: Date) {
        self.path = path
        self.modificationDate = modificationDate
    }
}

public struct TaskRecordSnapshotStore: @unchecked Sendable {
    public enum HydrationMode: Sendable {
        case validated
        case optimistic
    }

    public var fileIO: TaskFileIO
    public var fileManager: FileManager
    public var cacheBaseURL: URL?

    public init(
        fileIO: TaskFileIO = TaskFileIO(),
        fileManager: FileManager = .default,
        cacheBaseURL: URL? = nil
    ) {
        self.fileIO = fileIO
        self.fileManager = fileManager
        self.cacheBaseURL = cacheBaseURL
    }

    public func hydrate(
        rootURL: URL,
        repository: FileTaskRepository,
        mode: HydrationMode = .validated
    ) throws -> TaskSnapshotHydration {
        let manifest = try loadManifest(rootURL: rootURL)
        if mode == .optimistic,
           let optimisticHydration = try optimisticHydrationIfAvailable(rootURL: rootURL, manifest: manifest) {
            return optimisticHydration
        }

        let currentFingerprints = try fileIO.enumerateMarkdownFingerprints(rootURL: rootURL)
        let cachedByPath = Dictionary(uniqueKeysWithValues: manifest.entries.map { ($0.fingerprint.path, $0) })

        var records: [TaskRecord] = []
        var metadataEntries: [TaskMetadataEntry] = []
        var updatedEntries: [TaskSnapshotManifestEntry] = []
        var failures: [ParseFailureDiagnostic] = []
        var isDirty = manifest.version < 3 || manifest.entries.count != currentFingerprints.count || manifest.directories.isEmpty

        records.reserveCapacity(currentFingerprints.count)
        metadataEntries.reserveCapacity(currentFingerprints.count)
        updatedEntries.reserveCapacity(currentFingerprints.count)

        var pathsNeedingReload: [String] = []

        for fingerprint in currentFingerprints {
            if let cached = cachedByPath[fingerprint.path],
               cached.fingerprint.matches(fingerprint),
               let record = try loadRecordSnapshot(cacheKey: cached.cacheKey, rootURL: rootURL)?.makeRecord() {
                records.append(record)
                let metadataEntry = cached.metadata ?? TaskMetadataEntry(from: record)
                if cached.metadata == nil {
                    isDirty = true
                }
                metadataEntries.append(metadataEntry)
                updatedEntries.append(
                    TaskSnapshotManifestEntry(
                        cacheKey: cached.cacheKey,
                        fingerprint: .init(fingerprint),
                        metadata: metadataEntry
                    )
                )
            } else {
                isDirty = true
                pathsNeedingReload.append(fingerprint.path)
            }
        }

        let currentFingerprintsByPath = Dictionary(uniqueKeysWithValues: currentFingerprints.map { ($0.path, $0) })
        let reloaded = loadRecords(paths: pathsNeedingReload, repository: repository)
        records.append(contentsOf: reloaded.records)
        metadataEntries.append(contentsOf: reloaded.metadataEntries)
        failures.append(contentsOf: reloaded.failures)
        for record in reloaded.records {
            guard let fingerprint = currentFingerprintsByPath[record.identity.path] else { continue }
            let cacheKey = cachedByPath[record.identity.path]?.cacheKey ?? cacheKey(for: record.identity.path)
            let metadataEntry = TaskMetadataEntry(from: record)
            try writeRecordSnapshot(.init(record), cacheKey: cacheKey, rootURL: rootURL)
            updatedEntries.append(
                TaskSnapshotManifestEntry(
                    cacheKey: cacheKey,
                    fingerprint: .init(fingerprint),
                    metadata: metadataEntry
                )
            )
        }

        updatedEntries.sort { $0.fingerprint.path < $1.fingerprint.path }
        records.sort { $0.identity.path < $1.identity.path }
        metadataEntries.sort { $0.path < $1.path }

        if isDirty || !reloaded.records.isEmpty || !reloaded.failures.isEmpty {
            let activeCacheKeys = Set(updatedEntries.map(\.cacheKey))
            let staleEntries = manifest.entries.filter { !activeCacheKeys.contains($0.cacheKey) }
            for entry in staleEntries {
                try? removeRecordSnapshot(cacheKey: entry.cacheKey, rootURL: rootURL)
            }
            let directorySignatures = try fileIO.enumerateDirectoryFingerprints(rootURL: rootURL)
            try? saveManifest(entries: updatedEntries, directoryFingerprints: directorySignatures, rootURL: rootURL)
            try? saveLaunchState(records: records, rootURL: rootURL)
        }

        return TaskSnapshotHydration(
            records: records,
            fingerprints: currentFingerprints,
            metadataEntries: metadataEntries,
            failures: failures,
            requiresValidation: false
        )
    }

    public func save(records: [TaskRecord], fingerprints: [TaskFileFingerprint], rootURL: URL) throws {
        try applyDelta(
            upsertedRecords: records,
            deletedPaths: [],
            fingerprints: fingerprints,
            rootURL: rootURL
        )
    }

    public func applyDelta(
        upsertedRecords: [TaskRecord],
        deletedPaths: Set<String>,
        fingerprints: [TaskFileFingerprint],
        rootURL: URL
    ) throws {
        let manifest = try loadManifest(rootURL: rootURL)
        let fingerprintsByPath = Dictionary(uniqueKeysWithValues: fingerprints.map { ($0.path, $0) })
        var manifestByPath = Dictionary(uniqueKeysWithValues: manifest.entries.map { ($0.fingerprint.path, $0) })

        for path in deletedPaths {
            if let removed = manifestByPath.removeValue(forKey: path) {
                try? removeRecordSnapshot(cacheKey: removed.cacheKey, rootURL: rootURL)
            }
        }

        for (path, entry) in manifestByPath where fingerprintsByPath[path] == nil {
            manifestByPath.removeValue(forKey: path)
            try? removeRecordSnapshot(cacheKey: entry.cacheKey, rootURL: rootURL)
        }

        for record in upsertedRecords {
            guard let fingerprint = fingerprintsByPath[record.identity.path] else { continue }
            let cacheKey = manifestByPath[record.identity.path]?.cacheKey ?? cacheKey(for: record.identity.path)
            try writeRecordSnapshot(.init(record), cacheKey: cacheKey, rootURL: rootURL)
            manifestByPath[record.identity.path] = TaskSnapshotManifestEntry(
                cacheKey: cacheKey,
                fingerprint: .init(fingerprint),
                metadata: TaskMetadataEntry(from: record)
            )
        }

        let entries = manifestByPath.values.sorted { $0.fingerprint.path < $1.fingerprint.path }
        let directoryFingerprints = try fileIO.enumerateDirectoryFingerprints(rootURL: rootURL)
        try saveManifest(entries: entries, directoryFingerprints: directoryFingerprints, rootURL: rootURL)
        try saveLaunchState(
            existingRecords: try loadLaunchState(rootURL: rootURL)?.records ?? [],
            upsertedRecords: upsertedRecords,
            deletedPaths: deletedPaths,
            fingerprintsByPath: fingerprintsByPath,
            rootURL: rootURL
        )
    }

    private func loadManifest(rootURL: URL) throws -> TaskSnapshotManifest {
        let path = manifestURL(rootURL: rootURL).path
        guard fileManager.fileExists(atPath: path) else {
            return TaskSnapshotManifest(entries: [])
        }
        let data = try fileIO.readData(path: path)
        return try JSONDecoder().decode(TaskSnapshotManifest.self, from: data)
    }

    private func saveManifest(
        entries: [TaskSnapshotManifestEntry],
        directoryFingerprints: [TaskDirectoryFingerprint],
        rootURL: URL
    ) throws {
        let cache = TaskSnapshotManifest(
            version: 3,
            entries: entries.sorted { $0.fingerprint.path < $1.fingerprint.path },
            directories: directoryFingerprints.map(TaskDirectoryFingerprintSnapshot.init),
            generatedAt: DateCoding.encode(Date())
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(cache)
        try fileManager.createDirectory(at: cacheDirectoryURL(rootURL: rootURL), withIntermediateDirectories: true)
        try fileIO.writeData(path: manifestURL(rootURL: rootURL).path, data: data)
    }

    private func loadRecordSnapshot(cacheKey: String, rootURL: URL) throws -> TaskRecordSnapshot? {
        let path = entryURL(cacheKey: cacheKey, rootURL: rootURL).path
        guard fileManager.fileExists(atPath: path) else {
            return nil
        }
        let data = try fileIO.readData(path: path)
        return try JSONDecoder().decode(TaskRecordSnapshot.self, from: data)
    }

    private func writeRecordSnapshot(_ record: TaskRecordSnapshot, cacheKey: String, rootURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        try fileManager.createDirectory(at: entriesDirectoryURL(rootURL: rootURL), withIntermediateDirectories: true)
        try fileIO.writeData(path: entryURL(cacheKey: cacheKey, rootURL: rootURL).path, data: data)
    }

    private func removeRecordSnapshot(cacheKey: String, rootURL: URL) throws {
        try fileIO.delete(path: entryURL(cacheKey: cacheKey, rootURL: rootURL).path)
    }

    private func cacheDirectoryURL(rootURL: URL) -> URL {
        let baseDirectory: URL
        if let cacheBaseURL {
            baseDirectory = cacheBaseURL.standardizedFileURL.resolvingSymlinksInPath()
        } else if let sharedContainer = TaskFolderPreferences.sharedContainerURL(fileManager: fileManager) {
            baseDirectory = sharedContainer
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Caches", isDirectory: true)
        } else {
            baseDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
        }
        return baseDirectory
            .appendingPathComponent("TodoMD", isDirectory: true)
            .appendingPathComponent("task-record-snapshot-v3", isDirectory: true)
            .appendingPathComponent(cacheKey(for: rootURL.standardizedFileURL.resolvingSymlinksInPath().path), isDirectory: true)
    }

    private func entriesDirectoryURL(rootURL: URL) -> URL {
        cacheDirectoryURL(rootURL: rootURL).appendingPathComponent("entries", isDirectory: true)
    }

    private func manifestURL(rootURL: URL) -> URL {
        cacheDirectoryURL(rootURL: rootURL).appendingPathComponent("manifest.json", isDirectory: false)
    }

    private func launchStateURL(rootURL: URL) -> URL {
        cacheDirectoryURL(rootURL: rootURL).appendingPathComponent("launch-state.json", isDirectory: false)
    }

    private func entryURL(cacheKey: String, rootURL: URL) -> URL {
        entriesDirectoryURL(rootURL: rootURL).appendingPathComponent("\(cacheKey).json", isDirectory: false)
    }

    private func cacheKey(for path: String) -> String {
        let prime: UInt64 = 1_099_511_628_211
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash &*= prime
        }
        return String(format: "%016llx", hash)
    }

    private func optimisticHydrationIfAvailable(
        rootURL: URL,
        manifest: TaskSnapshotManifest
    ) throws -> TaskSnapshotHydration? {
        guard !manifest.entries.isEmpty else { return nil }
        guard cachedDirectoriesMatchCurrentState(manifest.directories) else { return nil }

        let records: [TaskRecord]
        let metadataEntries: [TaskMetadataEntry]

        if let launchState = try loadLaunchState(rootURL: rootURL),
           launchState.records.count == manifest.entries.count {
            records = launchState.records
                .map { $0.makeRecord() }
                .sorted { $0.identity.path < $1.identity.path }
            metadataEntries = records.map(TaskMetadataEntry.init(from:))
        } else {
            let cached = loadCachedSnapshots(entries: manifest.entries, rootURL: rootURL)
            guard cached.records.count == manifest.entries.count else { return nil }
            records = cached.records
            metadataEntries = cached.metadataEntries.isEmpty
                ? records.map(TaskMetadataEntry.init(from:))
                : cached.metadataEntries
        }

        return TaskSnapshotHydration(
            records: records,
            fingerprints: manifest.entries.map { $0.fingerprint.fingerprint },
            metadataEntries: metadataEntries,
            failures: [],
            requiresValidation: true
        )
    }

    private func cachedDirectoriesMatchCurrentState(
        _ cachedDirectories: [TaskDirectoryFingerprintSnapshot]
    ) -> Bool {
        guard !cachedDirectories.isEmpty else { return false }

        // Optimistic hydration only needs to know whether any previously known
        // directory changed. Statting the cached directories is much cheaper
        // than re-enumerating every file in the tree on launch.
        for cachedDirectory in cachedDirectories {
            let url = URL(fileURLWithPath: cachedDirectory.path)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            do {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
                guard values.isDirectory == true else { return false }
                guard values.contentModificationDate ?? .distantPast == cachedDirectory.fingerprint.modificationDate else {
                    return false
                }
            } catch {
                return false
            }
        }

        return true
    }

    private func loadLaunchState(rootURL: URL) throws -> TaskLaunchState? {
        let path = launchStateURL(rootURL: rootURL).path
        guard fileManager.fileExists(atPath: path) else {
            return nil
        }
        let data = try fileIO.readData(path: path)
        return try PropertyListDecoder().decode(TaskLaunchState.self, from: data)
    }

    private func saveLaunchState(records: [TaskRecord], rootURL: URL) throws {
        try saveLaunchStateSnapshots(records.map(TaskLaunchRecordSnapshot.init), rootURL: rootURL)
    }

    private func saveLaunchState(
        existingRecords: [TaskLaunchRecordSnapshot],
        upsertedRecords: [TaskRecord],
        deletedPaths: Set<String>,
        fingerprintsByPath: [String: TaskFileFingerprint],
        rootURL: URL
    ) throws {
        var recordsByPath = Dictionary(uniqueKeysWithValues: existingRecords.map { ($0.path, $0) })
        for path in deletedPaths {
            recordsByPath.removeValue(forKey: path)
        }
        for (path, _) in recordsByPath where fingerprintsByPath[path] == nil {
            recordsByPath.removeValue(forKey: path)
        }
        for record in upsertedRecords {
            guard fingerprintsByPath[record.identity.path] != nil else { continue }
            recordsByPath[record.identity.path] = TaskLaunchRecordSnapshot(record)
        }
        try saveLaunchStateSnapshots(recordsByPath.values.sorted { $0.path < $1.path }, rootURL: rootURL)
    }

    private func saveLaunchStateSnapshots(_ records: [TaskLaunchRecordSnapshot], rootURL: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(TaskLaunchState(records: records))
        try fileManager.createDirectory(at: cacheDirectoryURL(rootURL: rootURL), withIntermediateDirectories: true)
        try fileIO.writeData(path: launchStateURL(rootURL: rootURL).path, data: data)
    }

    private func loadCachedSnapshots(
        entries: [TaskSnapshotManifestEntry],
        rootURL: URL
    ) -> (records: [TaskRecord], metadataEntries: [TaskMetadataEntry]) {
        guard !entries.isEmpty else { return ([], []) }
        if entries.count < 64 {
            let sortedEntries = entries.sorted { $0.fingerprint.path < $1.fingerprint.path }
            var records: [TaskRecord] = []
            var metadataEntries: [TaskMetadataEntry] = []
            records.reserveCapacity(sortedEntries.count)
            metadataEntries.reserveCapacity(sortedEntries.count)
            for entry in sortedEntries {
                guard let snapshot = try? loadRecordSnapshot(cacheKey: entry.cacheKey, rootURL: rootURL) else {
                    continue
                }
                let record = snapshot.makeRecord()
                records.append(record)
                metadataEntries.append(entry.metadata ?? TaskMetadataEntry(from: record))
            }
            return (records, metadataEntries)
        }

        let collector = SnapshotLoadCollector()
        let sortedEntries = entries.sorted { $0.fingerprint.path < $1.fingerprint.path }
        DispatchQueue.concurrentPerform(iterations: sortedEntries.count) { index in
            let entry = sortedEntries[index]
            guard let snapshot = try? loadRecordSnapshot(cacheKey: entry.cacheKey, rootURL: rootURL) else {
                return
            }
            let record = snapshot.makeRecord()
            collector.append(
                index: index,
                record: record,
                metadataEntry: entry.metadata ?? TaskMetadataEntry(from: record)
            )
        }
        return collector.loaded()
    }

    private func loadRecords(
        paths: [String],
        repository: FileTaskRepository
    ) -> (records: [TaskRecord], metadataEntries: [TaskMetadataEntry], failures: [ParseFailureDiagnostic]) {
        guard !paths.isEmpty else { return ([], [], []) }
        if paths.count < 32 {
            var records: [TaskRecord] = []
            var metadataEntries: [TaskMetadataEntry] = []
            var failures: [ParseFailureDiagnostic] = []
            let timestamp = Date()
            for path in paths.sorted() {
                do {
                    let record = try repository.load(path: path)
                    records.append(record)
                    metadataEntries.append(TaskMetadataEntry(from: record))
                } catch {
                    failures.append(
                        ParseFailureDiagnostic(
                            path: path,
                            reason: error.localizedDescription,
                            timestamp: timestamp
                        )
                    )
                }
            }
            return (records, metadataEntries, failures)
        }

        let collector = SnapshotReloadCollector()
        let sortedPaths = paths.sorted()
        let timestamp = Date()
        DispatchQueue.concurrentPerform(iterations: sortedPaths.count) { index in
            let path = sortedPaths[index]
            do {
                let record = try repository.load(path: path)
                collector.append(index: index, record: record, metadataEntry: TaskMetadataEntry(from: record))
            } catch {
                collector.append(
                    failure: ParseFailureDiagnostic(
                        path: path,
                        reason: error.localizedDescription,
                        timestamp: timestamp
                    )
                )
            }
        }
        return collector.loaded()
    }
}

private struct TaskSnapshotManifest: Codable {
    var version: Int = 3
    var entries: [TaskSnapshotManifestEntry]
    var directories: [TaskDirectoryFingerprintSnapshot] = []
    var generatedAt: String? = nil
}

private struct TaskLaunchState: Codable {
    var records: [TaskLaunchRecordSnapshot]
}

private struct TaskSnapshotManifestEntry: Codable {
    var cacheKey: String
    var fingerprint: TaskFileFingerprintSnapshot
    var metadata: TaskMetadataEntry?
}

private struct TaskFileFingerprintSnapshot: Codable {
    var path: String
    var fileSize: UInt64
    var modificationDate: String

    init(_ fingerprint: TaskFileFingerprint) {
        self.path = fingerprint.path
        self.fileSize = fingerprint.fileSize
        self.modificationDate = DateCoding.encode(fingerprint.modificationDate)
    }

    func matches(_ fingerprint: TaskFileFingerprint) -> Bool {
        path == fingerprint.path &&
            fileSize == fingerprint.fileSize &&
            DateCoding.decode(modificationDate) == fingerprint.modificationDate
    }

    var fingerprint: TaskFileFingerprint {
        TaskFileFingerprint(
            path: path,
            fileSize: fileSize,
            modificationDate: DateCoding.decode(modificationDate) ?? .distantPast
        )
    }
}

private struct TaskDirectoryFingerprintSnapshot: Codable {
    var path: String
    var modificationDate: String

    init(_ fingerprint: TaskDirectoryFingerprint) {
        self.path = fingerprint.path
        self.modificationDate = DateCoding.encode(fingerprint.modificationDate)
    }

    var fingerprint: TaskDirectoryFingerprint {
        TaskDirectoryFingerprint(
            path: path,
            modificationDate: DateCoding.decode(modificationDate) ?? .distantPast
        )
    }
}

private struct TaskRecordSnapshot: Codable {
    var path: String
    var ref: String?
    var title: String
    var status: TaskStatus
    var due: LocalDate?
    var dueTime: LocalTime?
    var persistentReminder: Bool?
    var deferDate: LocalDate?
    var scheduled: LocalDate?
    var priority: TaskPriority
    var flagged: Bool
    var area: String?
    var project: String?
    var tags: [String]
    var recurrence: String?
    var estimatedMinutes: Int?
    var description: String?
    var locationReminder: TaskLocationReminderSnapshot?
    var created: String
    var modified: String?
    var completed: String?
    var assignee: String?
    var completedBy: String?
    var blockedBy: TaskBlockedBySnapshot?
    var source: String
    var body: String

    init(_ record: TaskRecord) {
        let frontmatter = record.document.frontmatter
        self.path = record.identity.path
        self.ref = frontmatter.ref
        self.title = frontmatter.title
        self.status = frontmatter.status
        self.due = frontmatter.due
        self.dueTime = frontmatter.dueTime
        self.persistentReminder = frontmatter.persistentReminder
        self.deferDate = frontmatter.defer
        self.scheduled = frontmatter.scheduled
        self.priority = frontmatter.priority
        self.flagged = frontmatter.flagged
        self.area = frontmatter.area
        self.project = frontmatter.project
        self.tags = frontmatter.tags
        self.recurrence = frontmatter.recurrence
        self.estimatedMinutes = frontmatter.estimatedMinutes
        self.description = frontmatter.description
        self.locationReminder = frontmatter.locationReminder.map(TaskLocationReminderSnapshot.init)
        self.created = DateCoding.encode(frontmatter.created)
        self.modified = frontmatter.modified.map(DateCoding.encode)
        self.completed = frontmatter.completed.map(DateCoding.encode)
        self.assignee = frontmatter.assignee
        self.completedBy = frontmatter.completedBy
        self.blockedBy = frontmatter.blockedBy.map(TaskBlockedBySnapshot.init)
        self.source = frontmatter.source
        self.body = record.document.body
    }

    func makeRecord() -> TaskRecord {
        let frontmatter = TaskFrontmatterV1(
            ref: ref,
            title: title,
            status: status,
            due: due,
            dueTime: dueTime,
            persistentReminder: persistentReminder,
            defer: deferDate,
            scheduled: scheduled,
            priority: priority,
            flagged: flagged,
            area: area,
            project: project,
            tags: tags,
            recurrence: recurrence,
            estimatedMinutes: estimatedMinutes,
            description: description,
            locationReminder: locationReminder?.makeLocationReminder(),
            created: DateCoding.decode(created) ?? .distantPast,
            modified: modified.flatMap(DateCoding.decode),
            completed: completed.flatMap(DateCoding.decode),
            assignee: assignee,
            completedBy: completedBy,
            blockedBy: blockedBy?.makeBlockedBy(),
            source: source
        )
        return TaskRecord(
            identity: TaskFileIdentity(path: path),
            document: TaskDocument(frontmatter: frontmatter, body: body)
        )
    }
}

private struct TaskLaunchRecordSnapshot: Codable {
    var path: String
    var ref: String?
    var title: String
    var status: TaskStatus
    var due: LocalDate?
    var dueTime: LocalTime?
    var persistentReminder: Bool?
    var deferDate: LocalDate?
    var scheduled: LocalDate?
    var priority: TaskPriority
    var flagged: Bool
    var area: String?
    var project: String?
    var tags: [String]
    var recurrence: String?
    var estimatedMinutes: Int?
    var description: String?
    var locationReminder: TaskLocationReminderSnapshot?
    var created: String
    var modified: String?
    var completed: String?
    var assignee: String?
    var completedBy: String?
    var blockedBy: TaskBlockedBySnapshot?
    var source: String

    init(_ record: TaskRecord) {
        let snapshot = TaskRecordSnapshot(record)
        self.path = snapshot.path
        self.ref = snapshot.ref
        self.title = snapshot.title
        self.status = snapshot.status
        self.due = snapshot.due
        self.dueTime = snapshot.dueTime
        self.persistentReminder = snapshot.persistentReminder
        self.deferDate = snapshot.deferDate
        self.scheduled = snapshot.scheduled
        self.priority = snapshot.priority
        self.flagged = snapshot.flagged
        self.area = snapshot.area
        self.project = snapshot.project
        self.tags = snapshot.tags
        self.recurrence = snapshot.recurrence
        self.estimatedMinutes = snapshot.estimatedMinutes
        self.description = snapshot.description
        self.locationReminder = snapshot.locationReminder
        self.created = snapshot.created
        self.modified = snapshot.modified
        self.completed = snapshot.completed
        self.assignee = snapshot.assignee
        self.completedBy = snapshot.completedBy
        self.blockedBy = snapshot.blockedBy
        self.source = snapshot.source
    }

    func makeRecord() -> TaskRecord {
        let frontmatter = TaskFrontmatterV1(
            ref: ref,
            title: title,
            status: status,
            due: due,
            dueTime: dueTime,
            persistentReminder: persistentReminder,
            defer: deferDate,
            scheduled: scheduled,
            priority: priority,
            flagged: flagged,
            area: area,
            project: project,
            tags: tags,
            recurrence: recurrence,
            estimatedMinutes: estimatedMinutes,
            description: description,
            locationReminder: locationReminder?.makeLocationReminder(),
            created: DateCoding.decode(created) ?? .distantPast,
            modified: modified.flatMap(DateCoding.decode),
            completed: completed.flatMap(DateCoding.decode),
            assignee: assignee,
            completedBy: completedBy,
            blockedBy: blockedBy?.makeBlockedBy(),
            source: source
        )
        return TaskRecord(
            identity: TaskFileIdentity(path: path),
            document: TaskDocument(frontmatter: frontmatter, body: "")
        )
    }
}

private final class SnapshotLoadCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var indexedRecords: [(Int, TaskRecord)] = []
    private var indexedMetadataEntries: [(Int, TaskMetadataEntry)] = []

    func append(index: Int, record: TaskRecord, metadataEntry: TaskMetadataEntry) {
        lock.lock()
        indexedRecords.append((index, record))
        indexedMetadataEntries.append((index, metadataEntry))
        lock.unlock()
    }

    func loaded() -> (records: [TaskRecord], metadataEntries: [TaskMetadataEntry]) {
        lock.lock()
        defer { lock.unlock() }
        return (
            indexedRecords.sorted { $0.0 < $1.0 }.map(\.1),
            indexedMetadataEntries.sorted { $0.0 < $1.0 }.map(\.1)
        )
    }
}

private final class SnapshotReloadCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var indexedRecords: [(Int, TaskRecord)] = []
    private var indexedMetadataEntries: [(Int, TaskMetadataEntry)] = []
    private var failures: [ParseFailureDiagnostic] = []

    func append(index: Int, record: TaskRecord, metadataEntry: TaskMetadataEntry) {
        lock.lock()
        indexedRecords.append((index, record))
        indexedMetadataEntries.append((index, metadataEntry))
        lock.unlock()
    }

    func append(failure: ParseFailureDiagnostic) {
        lock.lock()
        failures.append(failure)
        lock.unlock()
    }

    func loaded() -> (records: [TaskRecord], metadataEntries: [TaskMetadataEntry], failures: [ParseFailureDiagnostic]) {
        lock.lock()
        defer { lock.unlock() }
        return (
            indexedRecords.sorted { $0.0 < $1.0 }.map(\.1),
            indexedMetadataEntries.sorted { $0.0 < $1.0 }.map(\.1),
            failures.sorted { $0.path < $1.path }
        )
    }
}

private struct TaskLocationReminderSnapshot: Codable {
    var name: String?
    var latitude: Double
    var longitude: Double
    var radiusMeters: Double
    var trigger: String

    init(_ reminder: TaskLocationReminder) {
        self.name = reminder.name
        self.latitude = reminder.latitude
        self.longitude = reminder.longitude
        self.radiusMeters = reminder.radiusMeters
        self.trigger = reminder.trigger.rawValue
    }

    func makeLocationReminder() -> TaskLocationReminder {
        TaskLocationReminder(
            name: name,
            latitude: latitude,
            longitude: longitude,
            radiusMeters: radiusMeters,
            trigger: TaskLocationReminderTrigger(rawValue: trigger) ?? .onArrival
        )
    }
}

private struct TaskBlockedBySnapshot: Codable {
    var isManual: Bool
    var refs: [String]

    init(_ blockedBy: TaskBlockedBy) {
        switch blockedBy {
        case .manual:
            self.isManual = true
            self.refs = []
        case .refs(let refs):
            self.isManual = false
            self.refs = refs
        }
    }

    func makeBlockedBy() -> TaskBlockedBy? {
        if isManual {
            return .manual
        }
        return refs.isEmpty ? nil : .refs(refs)
    }
}
