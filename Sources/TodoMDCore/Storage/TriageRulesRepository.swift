import Foundation

public struct TriageRulesRepository {
    public var fileIO: TaskFileIO

    public init(fileIO: TaskFileIO = TaskFileIO()) {
        self.fileIO = fileIO
    }

    public func load(rootURL: URL) throws -> TriageRulesDocument {
        let url = rulesURL(rootURL: rootURL)
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            return TriageRulesDocument()
        }

        let raw = try fileIO.read(path: path)
        guard let data = raw.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TaskError.parseFailure(".triage-rules.json is malformed")
        }

        let version = object["version"] as? Int ?? 1
        var keywordProjectWeights: [String: [String: Int]] = [:]

        if let rawRules = object["keywordProjectWeights"] as? [String: Any] {
            for (keyword, value) in rawRules {
                guard let rawProjects = value as? [String: Any] else { continue }
                var normalizedProjects: [String: Int] = [:]
                for (project, weightValue) in rawProjects {
                    if let weight = weightValue as? Int {
                        normalizedProjects[project] = max(0, weight)
                    } else if let weight = weightValue as? Double {
                        normalizedProjects[project] = max(0, Int(weight.rounded()))
                    }
                }
                if !normalizedProjects.isEmpty {
                    keywordProjectWeights[keyword] = normalizedProjects
                }
            }
        }

        var unknownTopLevel: [String: JSONValue] = [:]
        for (key, value) in object where key != "version" && key != "keywordProjectWeights" {
            unknownTopLevel[key] = JSONValue(any: value)
        }

        return TriageRulesDocument(
            version: version,
            keywordProjectWeights: keywordProjectWeights,
            unknownTopLevel: unknownTopLevel
        )
    }

    public func save(_ document: TriageRulesDocument, rootURL: URL) throws {
        let url = rulesURL(rootURL: rootURL)

        var object: [String: Any] = [
            "version": document.version,
            "keywordProjectWeights": document.keywordProjectWeights
        ]

        for (key, value) in document.unknownTopLevel {
            object[key] = value.anyValue
        }

        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        guard let content = String(data: data, encoding: .utf8) else {
            throw TaskError.ioFailure("Failed to encode .triage-rules.json content")
        }

        try fileIO.write(path: url.path, content: content)
    }

    public func rulesURL(rootURL: URL) -> URL {
        rootURL.appendingPathComponent(".triage-rules.json")
    }
}
