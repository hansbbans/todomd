import Foundation

public struct ProjectMetadataRepository {
    public var fileIO: TaskFileIO

    public init(fileIO: TaskFileIO = TaskFileIO()) {
        self.fileIO = fileIO
    }

    public func load(rootURL: URL) throws -> ProjectMetadataDocument {
        let url = metadataURL(rootURL: rootURL)
        resolveConflictsIfNeeded(at: url)
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            return ProjectMetadataDocument(version: 1, projects: [], colors: [:], icons: [:], unknownTopLevel: [:])
        }

        let raw = try fileIO.read(path: path)
        guard let data = raw.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TaskError.parseFailure(".projects.json is malformed")
        }

        let version = object["version"] as? Int ?? 1
        let projects = object["projects"] as? [String] ?? []

        var colors: [String: String] = [:]
        if let rawColors = object["colors"] as? [String: Any] {
            for (project, value) in rawColors {
                guard let color = value as? String else { continue }
                colors[project] = color
            }
        }

        var icons: [String: String] = [:]
        if let rawIcons = object["icons"] as? [String: Any] {
            for (project, value) in rawIcons {
                guard let icon = value as? String else { continue }
                icons[project] = icon
            }
        }

        var unknown: [String: JSONValue] = [:]
        for (key, value) in object where key != "version" && key != "projects" && key != "colors" && key != "icons" {
            unknown[key] = JSONValue(any: value)
        }

        return ProjectMetadataDocument(
            version: version,
            projects: projects,
            colors: colors,
            icons: icons,
            unknownTopLevel: unknown
        )
    }

    public func save(_ document: ProjectMetadataDocument, rootURL: URL) throws {
        let url = metadataURL(rootURL: rootURL)
        resolveConflictsIfNeeded(at: url)

        var object: [String: Any] = [
            "version": document.version,
            "projects": document.projects,
            "colors": document.colors,
            "icons": document.icons
        ]

        for (key, value) in document.unknownTopLevel {
            object[key] = value.anyValue
        }

        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        guard let content = String(data: data, encoding: .utf8) else {
            throw TaskError.ioFailure("Failed to encode .projects.json content")
        }

        try fileIO.write(path: url.path, content: content)
    }

    public func metadataURL(rootURL: URL) -> URL {
        rootURL.appendingPathComponent(".projects.json")
    }

    private func resolveConflictsIfNeeded(at url: URL) {
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
