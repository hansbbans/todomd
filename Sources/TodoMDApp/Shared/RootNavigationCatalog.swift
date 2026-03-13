import Foundation

struct RootNavigationEntry: Identifiable, Hashable {
    let view: ViewIdentifier
    let label: String
    let icon: String

    var id: String { view.rawValue }
}

enum BrowseDiscoverySection: Int, CaseIterable, Identifiable {
    case perspectives
    case workflows

    var id: Int { rawValue }
}

enum RootWorkflowEntry: String, CaseIterable, Identifiable {
    case inboxTriage
    case review

    var id: String { rawValue }

    var label: String {
        switch self {
        case .inboxTriage:
            return "Inbox Triage"
        case .review:
            return "Review"
        }
    }

    var icon: String {
        switch self {
        case .inboxTriage:
            return "rectangle.stack"
        case .review:
            return "checklist"
        }
    }

    var accessibilityIdentifier: String {
        "root.workflow.\(rawValue)"
    }

    var searchAccessibilityIdentifier: String {
        "root.search.workflow.\(rawValue)"
    }

    var destinationView: ViewIdentifier? {
        switch self {
        case .inboxTriage:
            return nil
        case .review:
            return .builtIn(.review)
        }
    }
}

enum RootNavigationCatalog {
    static let browseDiscoverySectionOrder: [BrowseDiscoverySection] = [
        .perspectives,
        .workflows
    ]

    static func browseBuiltInEntries(pomodoroEnabled: Bool) -> [RootNavigationEntry] {
        var entries = builtInEntries([
            .myTasks,
            .delegated,
            .anytime,
            .someday,
            .flagged
        ])
        if pomodoroEnabled {
            entries.append(entry(for: .builtIn(.pomodoro)))
        }
        return entries
    }

    static func searchableBuiltInEntries(pomodoroEnabled: Bool) -> [RootNavigationEntry] {
        var entries = [
            RootNavigationEntry(view: .browse, label: "Browse", icon: "square.grid.2x2")
        ]
        entries.append(
            contentsOf: builtInEntries([
                .inbox,
                .myTasks,
                .delegated,
                .today,
                .upcoming,
                .logbook,
                .anytime,
                .someday,
                .flagged
            ])
        )
        if pomodoroEnabled {
            entries.append(entry(for: .builtIn(.pomodoro)))
        }
        return entries
    }

    private static func builtInEntries(_ views: [BuiltInView]) -> [RootNavigationEntry] {
        views.map { entry(for: .builtIn($0)) }
    }

    private static func entry(for view: ViewIdentifier) -> RootNavigationEntry {
        switch view {
        case .builtIn(let builtInView):
            return RootNavigationEntry(
                view: view,
                label: builtInView.displayTitle,
                icon: builtInView.displaySystemImage
            )
        case .custom(let rawValue) where rawValue == ViewIdentifier.browseRawValue:
            return RootNavigationEntry(
                view: view,
                label: "Browse",
                icon: "square.grid.2x2"
            )
        case .area(let area):
            return RootNavigationEntry(
                view: view,
                label: area,
                icon: "square.grid.2x2"
            )
        case .project(let project):
            return RootNavigationEntry(
                view: view,
                label: project,
                icon: "folder"
            )
        case .tag(let tag):
            return RootNavigationEntry(
                view: view,
                label: "#\(tag)",
                icon: "number"
            )
        case .custom(let rawValue):
            return RootNavigationEntry(
                view: view,
                label: rawValue,
                icon: "list.bullet"
            )
        }
    }
}
