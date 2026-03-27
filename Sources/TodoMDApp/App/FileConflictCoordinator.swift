import Foundation

struct ConflictVersionSummary: Identifiable, Equatable {
    let id: String
    let displayName: String
    let savingComputer: String
    let modifiedAt: Date?
    let versionURLPath: String?
    let hasLocalContents: Bool
    let preview: String?
}

struct ConflictSummary: Identifiable, Equatable {
    let path: String
    let filename: String
    let localSource: String
    let localModifiedAt: Date?
    let versions: [ConflictVersionSummary]

    var id: String { path }
}

protocol FileConflictVersionRepresenting: AnyObject {
    var persistentIdentifierDescription: String { get }
    var localizedName: String? { get }
    var localizedNameOfSavingComputer: String? { get }
    var modificationDate: Date? { get }
    var versionURLPath: String? { get }
    var hasLocalContents: Bool { get }
    var isResolved: Bool { get set }

    func replaceItem(at url: URL) throws
    func remove() throws
}

extension NSFileVersion: FileConflictVersionRepresenting {
    var persistentIdentifierDescription: String {
        String(describing: persistentIdentifier)
    }

    var versionURLPath: String? {
        url.path
    }

    func replaceItem(at url: URL) throws {
        _ = try replaceItem(at: url, options: [])
    }
}

struct FileConflictCoordinator {
    typealias ConflictVersionsLoader = (URL) -> [any FileConflictVersionRepresenting]
    typealias RemoveOtherVersions = (URL) -> Void
    typealias FileContentsReader = (String) -> String?

    let loadConflictVersions: ConflictVersionsLoader
    let removeOtherVersions: RemoveOtherVersions
    let readContents: FileContentsReader

    init(
        loadConflictVersions: @escaping ConflictVersionsLoader = { url in
            (NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).map { $0 as any FileConflictVersionRepresenting }
        },
        removeOtherVersions: @escaping RemoveOtherVersions = { url in
            _ = try? NSFileVersion.removeOtherVersionsOfItem(at: url)
        },
        readContents: @escaping FileContentsReader = { path in
            try? String(contentsOfFile: path, encoding: .utf8)
        }
    ) {
        self.loadConflictVersions = loadConflictVersions
        self.removeOtherVersions = removeOtherVersions
        self.readContents = readContents
    }

    func buildConflictSummaries(
        from events: [FileWatcherEvent],
        canonicalByPath: [String: TaskRecord]
    ) -> [ConflictSummary] {
        let conflictPaths = Set(events.compactMap { event -> String? in
            guard case .conflict(let path, _) = event else { return nil }
            return path
        })

        return conflictPaths.sorted().map { path in
            let url = URL(fileURLWithPath: path)
            let versions = loadConflictVersions(url).map { version in
                let preview: String?
                if version.hasLocalContents, let versionPath = version.versionURLPath {
                    preview = readContents(versionPath).map { String($0.prefix(400)) }
                } else {
                    preview = nil
                }

                return ConflictVersionSummary(
                    id: version.persistentIdentifierDescription,
                    displayName: version.localizedName ?? "Version",
                    savingComputer: version.localizedNameOfSavingComputer ?? "Unknown device",
                    modifiedAt: version.modificationDate,
                    versionURLPath: version.versionURLPath,
                    hasLocalContents: version.hasLocalContents,
                    preview: preview
                )
            }

            let localRecord = canonicalByPath[path]
            return ConflictSummary(
                path: path,
                filename: url.lastPathComponent,
                localSource: localRecord?.document.frontmatter.source ?? "unknown",
                localModifiedAt: localRecord?.document.frontmatter.modified ?? localRecord?.document.frontmatter.created,
                versions: versions
            )
        }
    }

    func resolveConflictKeepLocal(path: String) {
        let url = URL(fileURLWithPath: path)
        let versions = loadConflictVersions(url)
        guard !versions.isEmpty else { return }

        for version in versions {
            version.isResolved = true
            try? version.remove()
        }

        removeOtherVersions(url)
    }

    func resolveConflictKeepRemote(path: String) {
        resolveConflictKeepRemote(path: path, preferredVersionID: nil)
    }

    func resolveConflictKeepRemote(path: String, preferredVersionID: String?) {
        let url = URL(fileURLWithPath: path)
        let versions = loadConflictVersions(url)
        guard !versions.isEmpty else { return }

        let selected: (any FileConflictVersionRepresenting)?
        if let preferredVersionID {
            selected = versions.first(where: { $0.persistentIdentifierDescription == preferredVersionID })
                ?? versions.max(by: { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) })
        } else {
            selected = versions.max(by: { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) })
        }

        if let selected {
            try? selected.replaceItem(at: url)
        }

        for version in versions {
            version.isResolved = true
            try? version.remove()
        }

        removeOtherVersions(url)
    }

    func localFileContents(path: String) -> String {
        readContents(path) ?? ""
    }

    func conflictVersionContents(atPath path: String?) -> String {
        guard let path else { return "" }
        return readContents(path) ?? ""
    }
}
