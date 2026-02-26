import Foundation

public enum TaskFolderPreferences {
    public static let selectedFolderBookmarkKey = "settings_notes_folder_bookmark"
    public static let selectedFolderPathKey = "settings_notes_folder_path"
    public static let legacyFolderNameKey = "settings_icloud_folder_name"

    public static func saveSelectedFolder(_ url: URL, defaults: UserDefaults = .standard) throws {
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

    public static func clearSelectedFolder(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: selectedFolderBookmarkKey)
        defaults.removeObject(forKey: selectedFolderPathKey)
    }

    public static func selectedFolderURL(defaults: UserDefaults = .standard) -> URL? {
        guard let data = defaults.data(forKey: selectedFolderBookmarkKey) else {
            return nil
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

            _ = url.startAccessingSecurityScopedResource()
            return url.standardizedFileURL.resolvingSymlinksInPath()
        } catch {
            clearSelectedFolder(defaults: defaults)
            return nil
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
