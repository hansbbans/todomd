import Foundation

public struct PerspectivesDocument: Equatable, Sendable {
    public var version: Int
    public var order: [String]
    public var perspectives: [String: PerspectiveDefinition]
    public var unknownTopLevel: [String: JSONValue]

    public init(
        version: Int = 1,
        order: [String] = [],
        perspectives: [String: PerspectiveDefinition] = [:],
        unknownTopLevel: [String: JSONValue] = [:]
    ) {
        self.version = version
        self.order = order
        self.perspectives = perspectives
        self.unknownTopLevel = unknownTopLevel
    }
}
