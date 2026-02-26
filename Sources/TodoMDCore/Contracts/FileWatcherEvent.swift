import Foundation

public enum FileWatcherEvent: Equatable, Sendable {
    case created(path: String, source: String?, timestamp: Date)
    case modified(path: String, source: String?, timestamp: Date)
    case deleted(path: String, timestamp: Date)
    case conflict(path: String, timestamp: Date)
    case unparseable(path: String, reason: String, timestamp: Date)
    case rateLimitedBatch(paths: [String], source: String?, timestamp: Date)
}

public struct SyncSummary: Equatable, Sendable {
    public var ingestedCount: Int
    public var failedCount: Int
    public var deletedCount: Int
    public var conflictCount: Int
    public var timestamp: Date

    public init(ingestedCount: Int, failedCount: Int, deletedCount: Int, conflictCount: Int, timestamp: Date) {
        self.ingestedCount = ingestedCount
        self.failedCount = failedCount
        self.deletedCount = deletedCount
        self.conflictCount = conflictCount
        self.timestamp = timestamp
    }
}
