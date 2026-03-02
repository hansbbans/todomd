import Foundation

public enum TaskFolderPreferences {
    public static let selectedFolderBookmarkKey = "settings_notes_folder_bookmark"
    public static let selectedFolderPathKey = "settings_notes_folder_path"
    public static let legacyFolderNameKey = "settings_icloud_folder_name"
    public static let appGroupIdentifier = "group.com.hans.todomd"
    public static var shared: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    private static let securityScopeQueue = DispatchQueue(label: "TaskFolderPreferences.SecurityScope")
    nonisolated(unsafe) private static var activeSecurityScopedURL: URL?

    public static func saveSelectedFolder(_ url: URL, defaults: UserDefaults = TaskFolderPreferences.shared) throws {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let bookmarkData = try url.bookmarkData(
            options: bookmarkCreationOptions(),
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(bookmarkData, forKey: selectedFolderBookmarkKey)
        defaults.set(url.path, forKey: selectedFolderPathKey)
    }

    public static func clearSelectedFolder(defaults: UserDefaults = TaskFolderPreferences.shared) {
        endSecurityScopedAccess()
        defaults.removeObject(forKey: selectedFolderBookmarkKey)
        defaults.removeObject(forKey: selectedFolderPathKey)
    }

    public static func selectedFolderURL(defaults: UserDefaults = TaskFolderPreferences.shared) -> URL? {
        guard let data = defaults.data(forKey: selectedFolderBookmarkKey) else {
            // Migration: if the shared defaults has no bookmark, check .standard (written by older versions)
            if defaults !== UserDefaults.standard,
               let legacyData = UserDefaults.standard.data(forKey: selectedFolderBookmarkKey),
               let url = resolveBookmarkData(legacyData, savingStaleBookmarkTo: defaults) {
                try? saveSelectedFolder(url, defaults: defaults)
                return url
            }
            return fallbackPathURL(defaults: defaults)
        }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: bookmarkResolutionOptions(),
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                try saveSelectedFolder(url, defaults: defaults)
            }

            let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
            beginSecurityScopedAccessIfNeeded(for: normalized)
            return normalized
        } catch {
            if let fallback = fallbackPathURL(defaults: defaults) {
                return fallback
            }

            clearSelectedFolder(defaults: defaults)
            return nil
        }
    }

    private static func resolveBookmarkData(_ data: Data, savingStaleBookmarkTo _: UserDefaults) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: bookmarkResolutionOptions(),
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
        beginSecurityScopedAccessIfNeeded(for: normalized)
        return normalized
    }

    private static func fallbackPathURL(defaults: UserDefaults) -> URL? {
        guard let path = defaults.string(forKey: selectedFolderPathKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return nil
        }

        let normalized = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalized.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        beginSecurityScopedAccessIfNeeded(for: normalized)
        return normalized
    }

    private static func beginSecurityScopedAccessIfNeeded(for url: URL) {
        securityScopeQueue.sync {
            if let active = activeSecurityScopedURL, active == url {
                return
            }

            if let active = activeSecurityScopedURL {
                active.stopAccessingSecurityScopedResource()
                activeSecurityScopedURL = nil
            }

            if url.startAccessingSecurityScopedResource() {
                activeSecurityScopedURL = url
            }
        }
    }

    private static func endSecurityScopedAccess() {
        securityScopeQueue.sync {
            if let active = activeSecurityScopedURL {
                active.stopAccessingSecurityScopedResource()
                activeSecurityScopedURL = nil
            }
        }
    }

    private static func bookmarkCreationOptions() -> URL.BookmarkCreationOptions {
        #if os(macOS)
        return [.withSecurityScope]
        #else
        return []
        #endif
    }

    private static func bookmarkResolutionOptions() -> URL.BookmarkResolutionOptions {
        #if os(macOS)
        return [.withSecurityScope]
        #else
        return []
        #endif
    }
}
