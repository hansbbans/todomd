import XCTest
@testable import TodoMDCore

final class ProjectMetadataRepositoryTests: XCTestCase {
    func testSaveAndLoadProjectMetadataDocument() throws {
        let root = try TestSupport.tempDirectory(prefix: "ProjectMetadataRepo")
        let repository = ProjectMetadataRepository()

        var document = ProjectMetadataDocument(
            version: 1,
            projects: ["Work", "Home"],
            colors: ["Work": "#1E88E5"],
            icons: ["Home": "house.fill"]
        )
        document.unknownTopLevel["custom"] = .string("keep-me")

        try repository.save(document, rootURL: root)
        let loaded = try repository.load(rootURL: root)

        XCTAssertEqual(loaded.version, 1)
        XCTAssertEqual(loaded.projects, ["Work", "Home"])
        XCTAssertEqual(loaded.colors["Work"], "#1E88E5")
        XCTAssertEqual(loaded.icons["Home"], "house.fill")
        XCTAssertEqual(loaded.unknownTopLevel["custom"], .string("keep-me"))
    }

    func testLoadMissingFileReturnsEmptyDocument() throws {
        let root = try TestSupport.tempDirectory(prefix: "ProjectMetadataRepoMissing")
        let repository = ProjectMetadataRepository()

        let loaded = try repository.load(rootURL: root)

        XCTAssertEqual(loaded.version, 1)
        XCTAssertTrue(loaded.projects.isEmpty)
        XCTAssertTrue(loaded.colors.isEmpty)
        XCTAssertTrue(loaded.icons.isEmpty)
    }
}
