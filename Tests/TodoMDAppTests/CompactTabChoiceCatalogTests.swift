import Testing
@testable import TodoMDApp
#if canImport(UIKit)
import UIKit
#endif

struct CompactTabChoiceCatalogTests {
    @Test("Available compact tab choices include custom perspectives")
    func availableChoicesIncludeCustomPerspectives() {
        let perspective = PerspectiveDefinition(
            id: "focus",
            name: "Focus",
            icon: "sparkles"
        )

        let views = CompactTabChoiceCatalog.availableViews(
            pomodoroEnabled: false,
            perspectives: [perspective],
            projects: []
        )

        #expect(views.contains(.custom("perspective:focus")))
    }

    @Test("Available compact tab choices include projects")
    func availableChoicesIncludeProjects() {
        let views = CompactTabChoiceCatalog.availableViews(
            pomodoroEnabled: false,
            perspectives: [],
            projects: ["Work"]
        )

        #expect(views.contains(.project("Work")))
    }

    @Test("Custom perspective choices use perspective metadata")
    func customPerspectiveChoiceUsesPerspectiveMetadata() {
        let perspective = PerspectiveDefinition(
            id: "deep-work",
            name: "Deep Work",
            icon: "bolt.fill"
        )

        let choice = CompactTabChoiceCatalog.choice(
            for: .custom("perspective:deep-work"),
            perspectives: [perspective]
        )

        #expect(choice.title == "Deep Work")
        #expect(choice.iconToken.storageValue == "bolt.fill")
        #expect(choice.accessibilityIdentifier == "root.tab.perspective:deep-work")
    }

    @Test("Custom perspective choices keep SF Symbols with digits as symbols")
    func customPerspectiveChoiceKeepsDigitSymbols() {
        let perspective = PerspectiveDefinition(
            id: "delegated-focus",
            name: "Delegated Focus",
            icon: "person.2"
        )

        let choice = CompactTabChoiceCatalog.choice(
            for: .custom("perspective:delegated-focus"),
            perspectives: [perspective]
        )

        #expect(choice.iconToken.isEmoji == false)
        #expect(choice.iconToken.symbolName == "person.2")
    }

    @Test("Browse choice keeps its browse tab symbol")
    func browseChoiceKeepsBrowseSymbol() {
        let choice = CompactTabChoiceCatalog.choice(
            for: .browse,
            perspectives: []
        )

        #expect(choice.title == "Browse")
        #expect(choice.iconToken.isEmoji == false)
        #expect(choice.iconToken.symbolName == "square.grid.2x2")
        #expect(choice.accessibilityIdentifier == "root.tab.browse")
        #expect(CompactTabChoiceCatalog.compactTabBarSymbolName(for: choice) == "square.grid.3x3.fill")
    }

#if canImport(UIKit)
    @Test("Browse compact tab symbol resolves to a renderable UIKit image")
    func browseCompactTabSymbolResolvesToUIKitImage() {
        let choice = CompactTabChoiceCatalog.choice(
            for: .browse,
            perspectives: []
        )

        let symbolNames = [
            CompactTabChoiceCatalog.compactTabBarSymbolName(for: choice),
            "square.grid.2x2.fill",
            "square.grid.3x3.fill",
            "square.grid.2x2",
            "square.grid.3x3",
            "list.bullet"
        ]

        #expect(symbolNames.contains { UIImage(systemName: $0) != nil })
    }
#endif
}
