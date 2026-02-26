import Foundation

public struct ParseFailureDiagnostic: Equatable, Sendable {
    public let path: String
    public let reason: String
    public let timestamp: Date

    public init(path: String, reason: String, timestamp: Date) {
        self.path = path
        self.reason = reason
        self.timestamp = timestamp
    }
}

public struct RuntimeCounters: Equatable, Sendable {
    public var lastSync: Date?
    public var totalFilesIndexed: Int
    public var parseFailureCount: Int
    public var pendingNotificationCount: Int
    public var enumerateMilliseconds: Double
    public var parseMilliseconds: Double
    public var indexMilliseconds: Double
    public var queryMilliseconds: Double

    public init(
        lastSync: Date? = nil,
        totalFilesIndexed: Int = 0,
        parseFailureCount: Int = 0,
        pendingNotificationCount: Int = 0,
        enumerateMilliseconds: Double = 0,
        parseMilliseconds: Double = 0,
        indexMilliseconds: Double = 0,
        queryMilliseconds: Double = 0
    ) {
        self.lastSync = lastSync
        self.totalFilesIndexed = totalFilesIndexed
        self.parseFailureCount = parseFailureCount
        self.pendingNotificationCount = pendingNotificationCount
        self.enumerateMilliseconds = enumerateMilliseconds
        self.parseMilliseconds = parseMilliseconds
        self.indexMilliseconds = indexMilliseconds
        self.queryMilliseconds = queryMilliseconds
    }
}

public struct FileWatcherPerformance: Equatable, Sendable {
    public var enumerateMilliseconds: Double
    public var parseMilliseconds: Double

    public init(enumerateMilliseconds: Double, parseMilliseconds: Double) {
        self.enumerateMilliseconds = enumerateMilliseconds
        self.parseMilliseconds = parseMilliseconds
    }
}
