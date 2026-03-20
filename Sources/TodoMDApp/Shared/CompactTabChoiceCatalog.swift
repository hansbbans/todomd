import SwiftUI

struct CompactTabChoice: Identifiable, Hashable {
    let view: ViewIdentifier
    let title: String
    let iconToken: AppIconToken

    var id: String {
        view.rawValue
    }

    var accessibilityIdentifier: String {
        "root.tab.\(view.rawValue)"
    }
}

enum CompactTabChoiceCatalog {
    static func availableViews(
        pomodoroEnabled: Bool,
        perspectives: [PerspectiveDefinition],
        projects: [String]
    ) -> [ViewIdentifier] {
        CompactTabSettings.availableCustomViews(
            pomodoroEnabled: pomodoroEnabled,
            additionalViews: perspectives.map { .custom("perspective:\($0.id)") }
                + projects.map(ViewIdentifier.project)
        )
    }

    static func choice(
        for view: ViewIdentifier,
        perspectives: [PerspectiveDefinition]
    ) -> CompactTabChoice {
        switch view {
        case .builtIn(let builtInView):
            return CompactTabChoice(
                view: view,
                title: builtInView.displayTitle,
                iconToken: AppIconToken(
                    builtInView.displaySystemImage,
                    fallbackSymbol: builtInView.displaySystemImage
                )
            )
        case .area(let area):
            return CompactTabChoice(
                view: view,
                title: area,
                iconToken: AppIconToken("square.stack.3d.up", fallbackSymbol: "square.stack.3d.up")
            )
        case .project(let project):
            return CompactTabChoice(
                view: view,
                title: project,
                iconToken: AppIconToken("folder", fallbackSymbol: "folder")
            )
        case .tag(let tag):
            return CompactTabChoice(
                view: view,
                title: "#\(tag)",
                iconToken: AppIconToken("tag", fallbackSymbol: "tag")
            )
        case .custom(let rawValue):
            if ViewIdentifier.custom(rawValue).isBrowse {
                return CompactTabChoice(
                    view: view,
                    title: "Browse",
                    iconToken: AppIconToken("square.grid.2x2", fallbackSymbol: "square.grid.2x2")
                )
            }

            if let perspective = perspective(rawValue: rawValue, perspectives: perspectives) {
                return CompactTabChoice(
                    view: view,
                    title: perspective.name,
                    iconToken: AppIconToken(perspective.icon, fallbackSymbol: "list.bullet")
                )
            }

            return CompactTabChoice(
                view: view,
                title: rawValue,
                iconToken: AppIconToken("list.bullet", fallbackSymbol: "list.bullet")
            )
        }
    }

    static func compactTabBarSymbolName(for choice: CompactTabChoice) -> String {
        if choice.view.isBrowse {
            return "square.grid.3x3.fill"
        }
        return choice.iconToken.symbolName
    }

    private static func perspective(
        rawValue: String,
        perspectives: [PerspectiveDefinition]
    ) -> PerspectiveDefinition? {
        let prefix = "perspective:"
        guard rawValue.hasPrefix(prefix) else { return nil }
        let id = String(rawValue.dropFirst(prefix.count))
        guard !id.isEmpty else { return nil }
        return perspectives.first(where: { $0.id == id })
    }
}

struct CompactTabChoiceLabel: View {
    let choice: CompactTabChoice

    var body: some View {
        if choice.iconToken.isEmoji {
            Label {
                Text(choice.title)
            } icon: {
                Text(choice.iconToken.storageValue)
            }
        } else {
            Label(choice.title, systemImage: choice.iconToken.symbolName)
        }
    }
}
