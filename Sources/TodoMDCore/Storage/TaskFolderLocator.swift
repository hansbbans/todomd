import Foundation

public struct TaskFolderLocator {
    public var folderName: String
    public var fileManager: FileManager
    public var defaults: UserDefaults
    public var documentsRootURL: URL?

    public init(
        folderName: String = "todo.md",
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        documentsRootURL: URL? = nil
    ) {
        self.folderName = folderName
        self.fileManager = fileManager
        self.defaults = defaults
        self.documentsRootURL = documentsRootURL
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

        if let detectedFolderURL = autoDetectedFolderURL(in: documentsRoot) {
            return detectedFolderURL
        }

        return documentsRoot.appendingPathComponent(folderName, isDirectory: true)
    }

    public func ensureFolderExists() throws -> URL {
        let url = try resolveVisibleICloudURL()
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func resolveICloudDocumentsRootURL() -> URL {
        if let documentsRootURL {
            return documentsRootURL.standardizedFileURL.resolvingSymlinksInPath()
        }

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

    private func autoDetectedFolderURL(in documentsRoot: URL) -> URL? {
        let alias = folderName.replacingOccurrences(of: ".", with: "")
        let preferredNames = uniqueNonEmptyNames([folderName, alias, "todo.md", "todomd"])
        let preferredNameSet = Set(preferredNames)

        var directories = candidateDirectories(in: documentsRoot, maxDepth: 4, maxDirectories: 200)
        for preferredName in preferredNames {
            let preferredURL = documentsRoot.appendingPathComponent(preferredName, isDirectory: true)
            if isExistingDirectory(preferredURL), !directories.contains(where: { $0.lastPathComponent == preferredName }) {
                directories.append(preferredURL)
            }
        }

        guard !directories.isEmpty else { return nil }

        var bestMatch: (url: URL, score: Int)?
        for directory in directories {
            let score = folderDetectionScore(url: directory, preferredNames: preferredNameSet)
            guard score > 0 else { continue }

            if let current = bestMatch {
                if score > current.score || (score == current.score && directory.pathComponents.count > current.url.pathComponents.count) {
                    bestMatch = (url: directory, score: score)
                }
            } else {
                bestMatch = (url: directory, score: score)
            }
        }

        return bestMatch?.url
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

    private func topLevelDirectories(in root: URL) -> [URL] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries.filter { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])
            return values?.isDirectory == true && values?.isHidden != true
        }
    }

    private func candidateDirectories(in root: URL, maxDepth: Int, maxDirectories: Int) -> [URL] {
        guard maxDepth >= 1, maxDirectories > 0 else { return [] }

        var results: [URL] = []
        var seen: Set<String> = []

        func appendIfNew(_ url: URL) {
            let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
            if seen.insert(normalized.path).inserted {
                results.append(normalized)
            }
        }

        for topLevel in topLevelDirectories(in: root) {
            appendIfNew(topLevel)
            if results.count >= maxDirectories {
                return results
            }
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return results
        }

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])
            guard values?.isHidden != true else {
                enumerator.skipDescendants()
                continue
            }

            guard values?.isDirectory == true else { continue }

            let depth = max(0, url.pathComponents.count - root.pathComponents.count)
            if depth == 0 { continue }
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            appendIfNew(url)
            if results.count >= maxDirectories {
                break
            }
        }

        return results
    }

    private func folderDetectionScore(url: URL, preferredNames: Set<String>) -> Int {
        var score = 0
        let name = url.lastPathComponent

        if preferredNames.contains(name) {
            score += 40
        }

        if fileManager.fileExists(atPath: url.appendingPathComponent(".order.json").path) {
            score += 260
        }

        if fileManager.fileExists(atPath: url.appendingPathComponent(".perspectives.json").path) {
            score += 220
        }

        let inspection = inspectMarkdownFiles(in: url, maxFiles: 40)
        if inspection.fileCount > 0 {
            score += min(inspection.fileCount, 20) * 10
        }
        if inspection.containsLikelyTask {
            score += 180
        } else if inspection.fileCount > 0 {
            score += 40
        }

        return score
    }

    private func inspectMarkdownFiles(in folder: URL, maxFiles: Int) -> (fileCount: Int, containsLikelyTask: Bool) {
        guard maxFiles > 0 else { return (0, false) }

        guard let entries = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (0, false)
        }

        var fileCount = 0
        for fileURL in entries {
            guard fileURL.pathExtension.lowercased() == "md" else { continue }
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey])
            if values?.isHidden == true { continue }
            guard values?.isRegularFile == true else { continue }

            fileCount += 1
            if fileCount > maxFiles {
                break
            }

            guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            if contents.contains("\nstatus:") && contents.contains("\ntitle:") {
                return (fileCount, true)
            }
            if contents.hasPrefix("---\n"), contents.contains("status:") && contents.contains("title:") {
                return (fileCount, true)
            }
        }

        return (fileCount, false)
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
