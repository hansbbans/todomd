import Foundation

public struct PerspectivesRepository {
    public var fileIO: TaskFileIO
    public var fileManager: FileManager

    public init(fileIO: TaskFileIO = TaskFileIO(), fileManager: FileManager = .default) {
        self.fileIO = fileIO
        self.fileManager = fileManager
    }

    public func load(rootURL: URL) throws -> PerspectivesDocument {
        let url = perspectivesURL(rootURL: rootURL)
        resolvePerspectivesConflictsIfNeeded(at: url)

        guard fileManager.fileExists(atPath: url.path) else {
            return PerspectivesDocument()
        }

        let raw = try fileIO.read(path: url.path)
        guard let data = raw.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TaskError.parseFailure(".perspectives.json is malformed")
        }

        let version = object["version"] as? Int ?? 1
        let order = object["order"] as? [String] ?? []

        var perspectives: [String: PerspectiveDefinition] = [:]
        if let mapped = object["perspectives"] as? [String: Any] {
            let decoder = JSONDecoder()
            for (id, rawPerspective) in mapped {
                guard JSONSerialization.isValidJSONObject(rawPerspective),
                      let perspectiveData = try? JSONSerialization.data(withJSONObject: rawPerspective),
                      var perspective = try? decoder.decode(PerspectiveDefinition.self, from: perspectiveData) else {
                    continue
                }
                if perspective.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    perspective.id = id
                }
                perspectives[perspective.id] = perspective
            }
        } else if let legacyArray = object["perspectives"] as? [Any] {
            let decoder = JSONDecoder()
            for rawPerspective in legacyArray {
                guard JSONSerialization.isValidJSONObject(rawPerspective),
                      let perspectiveData = try? JSONSerialization.data(withJSONObject: rawPerspective),
                      let perspective = try? decoder.decode(PerspectiveDefinition.self, from: perspectiveData) else {
                    continue
                }
                perspectives[perspective.id] = perspective
            }
        }

        var unknownTopLevel: [String: JSONValue] = [:]
        for (key, value) in object where key != "version" && key != "order" && key != "perspectives" {
            unknownTopLevel[key] = JSONValue(any: value)
        }

        return PerspectivesDocument(
            version: version,
            order: order,
            perspectives: perspectives,
            unknownTopLevel: unknownTopLevel
        )
    }

    public func save(_ document: PerspectivesDocument, rootURL: URL) throws {
        let url = perspectivesURL(rootURL: rootURL)
        resolvePerspectivesConflictsIfNeeded(at: url)

        var mapped: [String: Any] = [:]
        let encoder = JSONEncoder()
        for perspective in document.perspectives.values {
            let data = try encoder.encode(perspective)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            mapped[perspective.id] = object
        }

        var object: [String: Any] = [
            "version": document.version,
            "order": document.order,
            "perspectives": mapped
        ]

        for (key, value) in document.unknownTopLevel {
            object[key] = value.anyValue
        }

        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        guard let content = String(data: data, encoding: .utf8) else {
            throw TaskError.ioFailure("Failed to encode .perspectives.json content")
        }

        try writeAtomically(url: url, content: content)
    }

    @discardableResult
    public func backupCorruptedFile(rootURL: URL) -> URL? {
        let url = perspectivesURL(rootURL: rootURL)
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        let backupURL = rootURL.appendingPathComponent(".perspectives.json.backup")
        do {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.copyItem(at: url, to: backupURL)
            return backupURL
        } catch {
            return nil
        }
    }

    public func perspectivesURL(rootURL: URL) -> URL {
        rootURL.appendingPathComponent(".perspectives.json")
    }

    private func writeAtomically(url: URL, content: String) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let tempURL = directory.appendingPathComponent(".perspectives-\(UUID().uuidString).tmp")
        do {
            try content.write(to: tempURL, atomically: false, encoding: .utf8)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            try fileManager.moveItem(at: tempURL, to: url)
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw TaskError.ioFailure("Failed to write .perspectives.json: \(error.localizedDescription)")
        }
    }

    private func resolvePerspectivesConflictsIfNeeded(at url: URL) {
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
