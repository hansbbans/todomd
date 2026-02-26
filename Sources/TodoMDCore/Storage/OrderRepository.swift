import Foundation

public struct OrderRepository {
    public var fileIO: TaskFileIO

    public init(fileIO: TaskFileIO = TaskFileIO()) {
        self.fileIO = fileIO
    }

    public func load(rootURL: URL) throws -> OrderDocument {
        let url = orderURL(rootURL: rootURL)
        resolveOrderConflictsIfNeeded(at: url)
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            return OrderDocument(version: 1, views: [:], unknownTopLevel: [:])
        }

        let raw = try fileIO.read(path: path)
        guard let data = raw.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TaskError.parseFailure(".order.json is malformed")
        }

        let version = object["version"] as? Int ?? 1

        var views: [String: [String]] = [:]
        if let rawViews = object["views"] as? [String: Any] {
            for (key, value) in rawViews {
                if let array = value as? [String] {
                    views[key] = array
                }
            }
        }

        var unknown: [String: JSONValue] = [:]
        for (key, value) in object where key != "version" && key != "views" {
            unknown[key] = JSONValue(any: value)
        }

        return OrderDocument(version: version, views: views, unknownTopLevel: unknown)
    }

    public func save(_ document: OrderDocument, rootURL: URL) throws {
        let url = orderURL(rootURL: rootURL)
        resolveOrderConflictsIfNeeded(at: url)

        var object: [String: Any] = [
            "version": document.version,
            "views": document.views
        ]

        for (key, value) in document.unknownTopLevel {
            object[key] = value.anyValue
        }

        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        guard let content = String(data: data, encoding: .utf8) else {
            throw TaskError.ioFailure("Failed to encode .order.json content")
        }

        try fileIO.write(path: url.path, content: content)
    }

    private func orderURL(rootURL: URL) -> URL {
        rootURL.appendingPathComponent(".order.json")
    }

    // v1 policy: if .order.json has unresolved iCloud conflict versions, pick the newest by mtime.
    private func resolveOrderConflictsIfNeeded(at url: URL) {
        guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !versions.isEmpty else {
            return
        }

        let localModificationDate: Date = {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let date = values.contentModificationDate else {
                return .distantPast
            }
            return date
        }()

        let newestConflict = versions.max { lhs, rhs in
            (lhs.modificationDate ?? .distantPast) < (rhs.modificationDate ?? .distantPast)
        }

        if let newestConflict,
           (newestConflict.modificationDate ?? .distantPast) > localModificationDate {
            _ = try? newestConflict.replaceItem(at: url, options: [])
        }

        for version in versions {
            version.isResolved = true
            _ = try? version.remove()
        }
        _ = try? NSFileVersion.removeOtherVersionsOfItem(at: url)
    }
}
