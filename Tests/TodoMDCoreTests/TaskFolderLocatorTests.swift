import XCTest
@testable import TodoMDCore

final class TaskFolderLocatorTests: XCTestCase {
    func testLocatorUsesSelectedFolderBookmarkWhenAvailable() throws {
        let selectedFolder = try TestSupport.tempDirectory(prefix: "SelectedFolder")
        let suiteName = "TaskFolderLocatorTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(try bookmarkData(for: selectedFolder), forKey: TaskFolderPreferences.selectedFolderBookmarkKey)
        defaults.set(selectedFolder.path, forKey: TaskFolderPreferences.selectedFolderPathKey)
        defaults.set("legacy-folder", forKey: TaskFolderPreferences.legacyFolderNameKey)

        let locator = TaskFolderLocator(folderName: "todo.md", defaults: defaults)
        let resolved = try locator.resolveVisibleICloudURL()

        XCTAssertEqual(
            resolved.standardizedFileURL.resolvingSymlinksInPath().path,
            selectedFolder.standardizedFileURL.resolvingSymlinksInPath().path
        )
    }

    func testLocatorUsesLegacyFolderNameWhenNoSelectedFolder() throws {
        let suiteName = "TaskFolderLocatorTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("my-notes", forKey: TaskFolderPreferences.legacyFolderNameKey)
        let locator = TaskFolderLocator(folderName: "todo.md", defaults: defaults)
        let resolved = try locator.resolveVisibleICloudURL()

        XCTAssertEqual(resolved.lastPathComponent, "my-notes")
    }

    func testLocatorFallsBackToDefaultFolderNameWhenLegacyIsBlank() throws {
        let suiteName = "TaskFolderLocatorTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("   ", forKey: TaskFolderPreferences.legacyFolderNameKey)
        let locator = TaskFolderLocator(folderName: "todo.md", defaults: defaults)
        let resolved = try locator.resolveVisibleICloudURL()

        XCTAssertEqual(resolved.lastPathComponent, "todo.md")
    }

    func testInvalidSelectedFolderBookmarkIsCleared() {
        let suiteName = "TaskFolderLocatorTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(Data([0x00, 0x01]), forKey: TaskFolderPreferences.selectedFolderBookmarkKey)
        defaults.set("/tmp/invalid", forKey: TaskFolderPreferences.selectedFolderPathKey)

        XCTAssertNil(TaskFolderPreferences.selectedFolderURL(defaults: defaults))
        XCTAssertNil(defaults.data(forKey: TaskFolderPreferences.selectedFolderBookmarkKey))
        XCTAssertNil(defaults.string(forKey: TaskFolderPreferences.selectedFolderPathKey))
    }

    func testLocatorAutoDetectsNestedFolderWithTasksOverEmptyPreferredFolder() throws {
        let root = try TestSupport.tempDirectory(prefix: "TaskFolderLocatorRoot")
        let emptyPreferred = root.appendingPathComponent("todo.md", isDirectory: true)
        let nestedTaskFolder = root
            .appendingPathComponent("Projects", isDirectory: true)
            .appendingPathComponent("WorkTasks", isDirectory: true)

        try FileManager.default.createDirectory(at: emptyPreferred, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nestedTaskFolder, withIntermediateDirectories: true)

        let taskFile = nestedTaskFolder.appendingPathComponent("today-task.md")
        try """
        ---
        title: "Ship widget fix"
        status: "todo"
        due: "2026-02-28"
        ---
        """.write(to: taskFile, atomically: true, encoding: .utf8)

        let suiteName = "TaskFolderLocatorTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let locator = TaskFolderLocator(
            folderName: "todo.md",
            defaults: defaults,
            documentsRootURL: root
        )
        let resolved = try locator.resolveVisibleICloudURL()

        XCTAssertEqual(
            resolved.standardizedFileURL.resolvingSymlinksInPath().path,
            nestedTaskFolder.standardizedFileURL.resolvingSymlinksInPath().path
        )
    }

    private func bookmarkData(for url: URL) throws -> Data {
        #if os(macOS)
        return try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }
}
