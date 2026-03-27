import XCTest
@testable import TodoMDCore

final class TaskFolderSupportFilesInstallerTests: XCTestCase {
    func testInstallWritesSchemaPromptAndInboxArtifacts() throws {
        let rootURL = try TestSupport.tempDirectory(prefix: "TaskFolderSupportFiles")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let installer = TaskFolderSupportFilesInstaller()

        try installer.install(at: rootURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: installer.inboxURL(rootURL: rootURL).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installer.schemaURL(rootURL: rootURL).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installer.promptURL(rootURL: rootURL).path))

        let schemaData = try Data(contentsOf: installer.schemaURL(rootURL: rootURL))
        XCTAssertEqual(schemaData, TaskSchemaExporter.exportJSONSchema())

        let prompt = try XCTUnwrap(String(contentsOf: installer.promptURL(rootURL: rootURL), encoding: .utf8))
        XCTAssertTrue(prompt.contains("# todo.md"))
        XCTAssertTrue(prompt.contains(".inbox/"))
        XCTAssertTrue(prompt.contains(".schema.json"))
        XCTAssertTrue(prompt.contains("source"))
    }

    func testInstallOverwritesStaleSchemaAndPromptContent() throws {
        let rootURL = try TestSupport.tempDirectory(prefix: "TaskFolderSupportFiles")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let installer = TaskFolderSupportFilesInstaller()
        try "stale schema".write(to: installer.schemaURL(rootURL: rootURL), atomically: true, encoding: .utf8)
        try "stale prompt".write(to: installer.promptURL(rootURL: rootURL), atomically: true, encoding: .utf8)

        try installer.install(at: rootURL)

        let schemaData = try Data(contentsOf: installer.schemaURL(rootURL: rootURL))
        XCTAssertEqual(schemaData, TaskSchemaExporter.exportJSONSchema())

        let prompt = try XCTUnwrap(String(contentsOf: installer.promptURL(rootURL: rootURL), encoding: .utf8))
        XCTAssertEqual(prompt, TaskFolderSupportFilesInstaller.promptMarkdown)
    }

    func testPromptIncludesWorkspaceSafetyGuidance() {
        let prompt = TaskFolderSupportFilesInstaller.promptMarkdown

        XCTAssertTrue(prompt.contains("Quick Start: Drop a file into .inbox/"))
        XCTAssertTrue(prompt.contains("Do NOT modify `.order.json`"))
        XCTAssertTrue(prompt.contains("Do NOT delete task files"))
        XCTAssertTrue(prompt.contains("Check your files against `.schema.json`"))
    }
}
