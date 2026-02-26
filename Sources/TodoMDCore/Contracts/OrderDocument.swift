import Foundation

public struct OrderDocument: Equatable, Sendable {
    public var version: Int
    public var views: [String: [String]]
    public var unknownTopLevel: [String: JSONValue]

    public init(version: Int = 1, views: [String: [String]] = [:], unknownTopLevel: [String: JSONValue] = [:]) {
        self.version = version
        self.views = views
        self.unknownTopLevel = unknownTopLevel
    }
}
