import Foundation

public struct InboxIngestResult: Sendable {
    public let task: TaskDocument
    public let createdPath: String
    public let originalFilename: String

    public init(task: TaskDocument, createdPath: String, originalFilename: String) {
        self.task = task
        self.createdPath = createdPath
        self.originalFilename = originalFilename
    }
}
