import Foundation

public struct TriageRulesDocument: Equatable, Sendable {
    public var version: Int
    public var keywordProjectWeights: [String: [String: Int]]
    public var unknownTopLevel: [String: JSONValue]

    public init(
        version: Int = 1,
        keywordProjectWeights: [String: [String: Int]] = [:],
        unknownTopLevel: [String: JSONValue] = [:]
    ) {
        self.version = version
        self.keywordProjectWeights = keywordProjectWeights
        self.unknownTopLevel = unknownTopLevel
    }

    public var isEmpty: Bool {
        keywordProjectWeights.isEmpty
    }
}
