// PendingWriteJournal.swift
// Lightweight journal for pending writes when iCloud Drive is temporarily unavailable.
// Stores pending writes as JSON. On reconnect, replays them before a full sync.

import Foundation

// MARK: - PendingWriteEntry

/// A single pending write operation, captured at the time of the failed write attempt.
public struct PendingWriteEntry: Codable, Sendable, Identifiable {
    /// Unique identifier for this entry; used to dequeue after a successful write.
    public let id: String
    /// Absolute filesystem path of the file to write.
    public let path: String
    /// Full UTF-8 content to write to `path`.
    public let content: String
    /// When this entry was enqueued (UTC).
    public let enqueuedAt: Date

    public init(id: String = UUID().uuidString, path: String, content: String, enqueuedAt: Date = Date()) {
        self.id = id
        self.path = path
        self.content = content
        self.enqueuedAt = enqueuedAt
    }
}

// MARK: - PendingWriteJournal

/// Thread-safe journal that persists pending write operations as JSON.
///
/// Typical lifecycle:
/// 1. When a write fails because iCloud Drive is unavailable, call `enqueue(path:content:)`.
/// 2. When connectivity is restored, call `replay(using:)` to flush the queue.
/// 3. Successful entries are automatically removed; failed ones remain for the next attempt.
///
/// Journal location: `<Application Support>/TodoMD/pending-writes.json`
public final class PendingWriteJournal: @unchecked Sendable {

    // MARK: - Private state

    private let journalURL: URL
    private let lock = NSLock()

    // MARK: - Initialisation

    /// Creates a journal backed by the default Application Support directory.
    public convenience init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let journalURL = appSupport
            .appendingPathComponent("TodoMD", isDirectory: true)
            .appendingPathComponent("pending-writes.json")
        self.init(journalURL: journalURL)
    }

    /// Creates a journal at an explicit URL (primarily for testing).
    public init(journalURL: URL) {
        self.journalURL = journalURL
    }

    // MARK: - Public API

    /// Adds a new pending write entry to the journal.
    ///
    /// - Parameters:
    ///   - path: Absolute filesystem path of the file to write.
    ///   - content: Full UTF-8 file content.
    /// - Returns: The newly created `PendingWriteEntry`, or `nil` if the journal could not be persisted.
    @discardableResult
    public func enqueue(path: String, content: String) -> PendingWriteEntry? {
        lock.lock()
        defer { lock.unlock() }

        var entries = loadEntries()
        let entry = PendingWriteEntry(path: path, content: content)
        entries.append(entry)
        do {
            try saveEntries(entries)
            return entry
        } catch {
            // Best-effort; if we can't persist the journal there is nothing more we can do here.
            return nil
        }
    }

    /// Removes the entry with the given `id` from the journal (call after a successful write).
    ///
    /// - Parameter id: The `PendingWriteEntry.id` returned by `enqueue`.
    public func dequeue(id: String) {
        lock.lock()
        defer { lock.unlock() }

        var entries = loadEntries()
        entries.removeAll { $0.id == id }
        try? saveEntries(entries)
    }

    /// Returns all currently pending entries in the order they were enqueued.
    public func allPending() -> [PendingWriteEntry] {
        lock.lock()
        defer { lock.unlock() }
        return loadEntries()
    }

    /// Attempts to replay every pending write using the provided `write` closure.
    ///
    /// Entries that succeed are removed from the journal immediately.
    /// Entries that fail remain in the journal so they can be retried later.
    ///
    /// - Parameter write: A closure that takes `(path, content)` and performs the actual file write.
    ///   The closure may throw; a thrown error is treated as a transient failure.
    public func replay(using write: (String, String) throws -> Void) throws {
        lock.lock()
        let entries = loadEntries()
        lock.unlock()

        var failedEntries: [PendingWriteEntry] = []

        for entry in entries {
            do {
                try write(entry.path, entry.content)
            } catch {
                // Retain failed entries so they can be retried on the next replay.
                failedEntries.append(entry)
            }
        }

        lock.lock()
        defer { lock.unlock() }

        // Merge: keep entries that still exist in the journal AND failed this replay.
        // (New entries may have been enqueued concurrently while we were replaying.)
        let failedIDs = Set(failedEntries.map(\.id))
        let currentEntries = loadEntries()
        let mergedEntries = currentEntries.filter { entry in
            // Retain if it was not part of this replay attempt, OR it failed.
            let wasReplayed = entries.contains(where: { $0.id == entry.id })
            return !wasReplayed || failedIDs.contains(entry.id)
        }

        try saveEntries(mergedEntries)
    }

    // MARK: - Persistence helpers

    /// Loads and decodes the current journal file. Returns an empty array if the file does not exist
    /// or cannot be decoded (treated as a fresh journal).
    private func loadEntries() -> [PendingWriteEntry] {
        guard FileManager.default.fileExists(atPath: journalURL.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: journalURL)
            return try JSONDecoder().decode([PendingWriteEntry].self, from: data)
        } catch {
            // Corrupt or unreadable journal — treat as empty to avoid a stuck state.
            return []
        }
    }

    /// Encodes and writes the entries array to the journal file, creating parent directories as needed.
    private func saveEntries(_ entries: [PendingWriteEntry]) throws {
        let directory = journalURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(entries)
        try data.write(to: journalURL, options: .atomicWrite)
    }
}
