import Foundation

public enum CompactTabSettings {
    public static let leadingViewKey = "settings_compact_tab_primary_view"
    public static let trailingViewKey = "settings_compact_tab_secondary_view"
    public static let leadingDisplayNameKey = "settings_compact_tab_primary_display_name"
    public static let trailingDisplayNameKey = "settings_compact_tab_secondary_display_name"
    public static let defaultLeadingView: ViewIdentifier = .builtIn(.upcoming)
    public static let defaultTrailingView: ViewIdentifier = .builtIn(.logbook)
    public static let maxPerspectiveDisplayNameLength = 10

    private static let baseCustomViews: [ViewIdentifier] = [
        .builtIn(.upcoming),
        .builtIn(.logbook),
        .builtIn(.myTasks),
        .builtIn(.delegated),
        .builtIn(.anytime),
        .builtIn(.someday),
        .builtIn(.flagged),
        .builtIn(.review)
    ]

    public static func availableCustomViews(
        pomodoroEnabled: Bool,
        additionalViews: [ViewIdentifier] = []
    ) -> [ViewIdentifier] {
        var views = baseCustomViews
        if pomodoroEnabled {
            views.append(.builtIn(.pomodoro))
        }
        for view in additionalViews where isSupportedCustomView(view) && !views.contains(view) {
            views.append(view)
        }
        return views
    }

    public static func normalizedCustomViews(
        leadingRawValue: String,
        trailingRawValue: String,
        pomodoroEnabled: Bool,
        additionalViews: [ViewIdentifier] = []
    ) -> (primary: ViewIdentifier, secondary: ViewIdentifier) {
        let available = availableCustomViews(
            pomodoroEnabled: pomodoroEnabled,
            additionalViews: additionalViews
        )
        let primary = resolveCustomView(
            rawValue: leadingRawValue,
            available: available,
            fallbackOrder: [defaultLeadingView, defaultTrailingView] + available,
            excluding: []
        )
        let secondary = resolveCustomView(
            rawValue: trailingRawValue,
            available: available,
            fallbackOrder: [defaultTrailingView, defaultLeadingView] + available,
            excluding: [primary]
        )
        return (primary, secondary)
    }

    public static func isPerspectiveCustomView(_ view: ViewIdentifier) -> Bool {
        switch view {
        case .custom(let rawValue):
            return rawValue.hasPrefix("perspective:") && !ViewIdentifier.custom(rawValue).isBrowse
        case .builtIn, .area, .project, .tag:
            return false
        }
    }

    public static func defaultPerspectiveDisplayName(_ perspectiveName: String) -> String {
        limitedDisplayName(perspectiveName)
    }

    public static func normalizedPerspectiveDisplayName(
        _ rawValue: String,
        perspectiveName: String
    ) -> String {
        let limited = limitedDisplayName(rawValue)
        if limited.isEmpty {
            return defaultPerspectiveDisplayName(perspectiveName)
        }
        return limited
    }

    private static func resolveCustomView(
        rawValue: String,
        available: [ViewIdentifier],
        fallbackOrder: [ViewIdentifier],
        excluding: [ViewIdentifier]
    ) -> ViewIdentifier {
        let excluded = Set(excluding)
        let candidate = ViewIdentifier(rawValue: rawValue)
        if available.contains(candidate),
           !excluded.contains(candidate) {
            return candidate
        }

        for candidate in fallbackOrder where available.contains(candidate) && !excluded.contains(candidate) {
            return candidate
        }

        return available.first(where: { !excluded.contains($0) }) ?? defaultLeadingView
    }

    private static func isSupportedCustomView(_ view: ViewIdentifier) -> Bool {
        switch view {
        case .builtIn(let builtInView):
            return baseCustomViews.contains(.builtIn(builtInView)) || builtInView == .pomodoro
        case .custom:
            return isPerspectiveCustomView(view)
        case .project:
            return true
        case .area, .tag:
            return false
        }
    }

    private static func limitedDisplayName(_ rawValue: String) -> String {
        let collapsedWhitespace = rawValue
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(collapsedWhitespace.prefix(maxPerspectiveDisplayNameLength))
    }
}
