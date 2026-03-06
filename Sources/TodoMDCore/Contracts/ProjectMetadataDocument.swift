import Foundation

public struct ProjectMetadataDocument: Equatable, Sendable {
    public var version: Int
    public var projects: [String]
    public var colors: [String: String]
    public var icons: [String: String]
    public var unknownTopLevel: [String: JSONValue]

    public init(
        version: Int = 1,
        projects: [String] = [],
        colors: [String: String] = [:],
        icons: [String: String] = [:],
        unknownTopLevel: [String: JSONValue] = [:]
    ) {
        self.version = version
        self.projects = projects
        self.colors = colors
        self.icons = icons
        self.unknownTopLevel = unknownTopLevel
    }
}
