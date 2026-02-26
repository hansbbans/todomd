import Foundation

public struct TaskFileIdentity: Hashable, Sendable {
    public let path: String
    public let filename: String

    public init(path: String) {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        self.path = normalized
        self.filename = URL(fileURLWithPath: normalized).lastPathComponent
    }
}

public struct TaskFileFingerprint: Hashable, Sendable {
    public let path: String
    public let fileSize: UInt64
    public let modificationDate: Date

    public init(path: String, fileSize: UInt64, modificationDate: Date) {
        self.path = path
        self.fileSize = fileSize
        self.modificationDate = modificationDate
    }
}
