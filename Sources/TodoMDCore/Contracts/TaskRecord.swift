import Foundation

public struct TaskRecord: Equatable, Sendable {
    public var identity: TaskFileIdentity
    public var document: TaskDocument

    public init(identity: TaskFileIdentity, document: TaskDocument) {
        self.identity = identity
        self.document = document
    }
}

extension TaskRecord: Identifiable {
    public var id: String { identity.path }
}
