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
        if let selected = TaskFolderPreferences.selectedFolderURL(defaults: defaults) {
            return selected
        }

        let configuredFolderName = defaults.string(forKey: TaskFolderPreferences.legacyFolderNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveFolderName = (configuredFolderName?.isEmpty == false) ? configuredFolderName! : folderName

        if let container = fileManager.url(forUbiquityContainerIdentifier: nil) {
            let documents = container.appendingPathComponent("Documents", isDirectory: true)
            return documents.appendingPathComponent(effectiveFolderName, isDirectory: true)
        }

        // Local fallback for simulator/dev or when iCloud container is unavailable.
        #if os(iOS)
        let homeDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        #else
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        #endif

        let fallback = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Mobile Documents", isDirectory: true)
            .appendingPathComponent("com~apple~CloudDocs", isDirectory: true)
            .appendingPathComponent(effectiveFolderName, isDirectory: true)
        return fallback
    }

    public func ensureFolderExists() throws -> URL {
        let url = try resolveVisibleICloudURL()
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
