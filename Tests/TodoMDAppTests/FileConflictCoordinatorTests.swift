import Foundation
import Testing
@testable import TodoMDApp

struct FileConflictCoordinatorTests {
    @Test("Keeping a selected remote version replaces the local file with that version")
    func resolveConflictKeepRemotePrefersExplicitVersionID() {
        let url = URL(fileURLWithPath: "/tmp/conflicted-task.md")
        let newest = TestConflictVersion(
            id: "newest",
            displayName: "Newest",
            savingComputer: "MacBook Pro",
            modifiedAt: Date(timeIntervalSince1970: 200)
        )
        let preferred = TestConflictVersion(
            id: "preferred",
            displayName: "Preferred",
            savingComputer: "iPhone",
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        var removedOtherVersionsURL: URL?
        var loadedURLs: [URL] = []

        let coordinator = FileConflictCoordinator(
            loadConflictVersions: { loadedURL in
                loadedURLs.append(loadedURL)
                return [newest, preferred]
            },
            removeOtherVersions: { removedOtherVersionsURL = $0 },
            readContents: { _ in nil }
        )

        coordinator.resolveConflictKeepRemote(path: url.path, preferredVersionID: "preferred")

        #expect(loadedURLs == [url])
        #expect(preferred.replacedURLs == [url])
        #expect(newest.replacedURLs.isEmpty)
        #expect(preferred.isResolved)
        #expect(newest.isResolved)
        #expect(preferred.removeCallCount == 1)
        #expect(newest.removeCallCount == 1)
        #expect(removedOtherVersionsURL == url)
    }
}

private final class TestConflictVersion: FileConflictVersionRepresenting {
    let persistentIdentifierDescription: String
    let localizedName: String?
    let localizedNameOfSavingComputer: String?
    let modificationDate: Date?
    let versionURLPath: String?
    let hasLocalContents: Bool

    var isResolved = false
    var replacedURLs: [URL] = []
    var removeCallCount = 0

    init(
        id: String,
        displayName: String,
        savingComputer: String,
        modifiedAt: Date?,
        versionURLPath: String? = nil,
        hasLocalContents: Bool = false
    ) {
        self.persistentIdentifierDescription = id
        self.localizedName = displayName
        self.localizedNameOfSavingComputer = savingComputer
        self.modificationDate = modifiedAt
        self.versionURLPath = versionURLPath
        self.hasLocalContents = hasLocalContents
    }

    func replaceItem(at url: URL) throws {
        replacedURLs.append(url)
    }

    func remove() throws {
        removeCallCount += 1
    }
}
