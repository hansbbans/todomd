import Foundation

public struct TaskFolderLocator {
    public var folderName: String
    public var fileManager: FileManager
    public var defaults: UserDefaults

    public init(folderName: String = "todo.md", fileManager: FileManager = .default, defaults: UserDefaults = .standard) {
        self.folderName = folderName
        self.fileManager = fileManager
        self.defaults = defaults
    }

    public func resolveVisibleICloudURL() throws -> URL {
        if let override = storageOverrideURL() {
            return override
        }

        if let selected = TaskFolderPreferences.selectedFolderURL(defaults: defaults) {
            return selected
        }

        let configuredFolderName = defaults.string(forKey: TaskFolderPreferences.legacyFolderNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let configured = (configuredFolderName?.isEmpty == false) ? configuredFolderName : nil
        let documentsRoot = resolveICloudDocumentsRootURL()

        if let configured {
            return documentsRoot.appendingPathComponent(configured, isDirectory: true)
        }

        if let detectedFolderName = autoDetectedFolderName(in: documentsRoot) {
            return documentsRoot.appendingPathComponent(detectedFolderName, isDirectory: true)
        }

        return documentsRoot.appendingPathComponent(folderName, isDirectory: true)
    }

    public func ensureFolderExists() throws -> URL {
        let url = try resolveVisibleICloudURL()
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func resolveICloudDocumentsRootURL() -> URL {
        #if targetEnvironment(simulator)
        if let simulatorHostRoot = simulatorHostICloudDocumentsRootURL() {
            return simulatorHostRoot
        }
        #endif

        if let container = fileManager.url(forUbiquityContainerIdentifier: nil) {
            return container.appendingPathComponent("Documents", isDirectory: true)
        }

        // Local fallback for simulator/dev or when iCloud container is unavailable.
        #if os(iOS)
        let homeDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        #else
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        #endif

        return homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Mobile Documents", isDirectory: true)
            .appendingPathComponent("com~apple~CloudDocs", isDirectory: true)
    }

    private func autoDetectedFolderName(in documentsRoot: URL) -> String? {
        let alias = folderName.replacingOccurrences(of: ".", with: "")
        let orderedCandidates = uniqueNonEmptyNames([folderName, alias, "todo.md", "todomd"])

        var existing: [(name: String, url: URL)] = []
        for name in orderedCandidates {
            let url = documentsRoot.appendingPathComponent(name, isDirectory: true)
            if isExistingDirectory(url) {
                existing.append((name, url))
            }
        }

        guard !existing.isEmpty else { return nil }
        if existing.count == 1 { return existing[0].name }

        // Prefer directories that already contain task markdown files.
        if let directoryWithTasks = existing.first(where: { containsTaskMarkdownFiles(in: $0.url) }) {
            return directoryWithTasks.name
        }

        return existing[0].name
    }

    private func uniqueNonEmptyNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for raw in names {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                result.append(trimmed)
            }
        }
        return result
    }

    private func isExistingDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        return isDirectory.boolValue
    }

    private func containsTaskMarkdownFiles(in folder: URL) -> Bool {
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return false
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "md" else { continue }
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey])
            if values?.isHidden == true { continue }
            if values?.isRegularFile == true {
                return true
            }
        }
        return false
    }

    private func storageOverrideURL() -> URL? {
        guard let overrideValue = ProcessInfo.processInfo.environment["TODOMD_STORAGE_OVERRIDE_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !overrideValue.isEmpty else {
            return nil
        }

        let overrideURL: URL
        if overrideValue.hasPrefix("/") {
            overrideURL = URL(fileURLWithPath: overrideValue, isDirectory: true)
        } else {
            #if os(iOS)
            let homeDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            #else
            let homeDirectory = fileManager.homeDirectoryForCurrentUser
            #endif
            overrideURL = homeDirectory.appendingPathComponent(overrideValue, isDirectory: true)
        }

        return overrideURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    #if targetEnvironment(simulator)
    private func simulatorHostICloudDocumentsRootURL() -> URL? {
        guard let hostHome = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"], !hostHome.isEmpty else {
            return nil
        }

        let hostCloudDocs = URL(fileURLWithPath: hostHome, isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Mobile Documents", isDirectory: true)
            .appendingPathComponent("com~apple~CloudDocs", isDirectory: true)

        guard fileManager.fileExists(atPath: hostCloudDocs.path) else {
            return nil
        }

        return hostCloudDocs
    }
    #endif
}
