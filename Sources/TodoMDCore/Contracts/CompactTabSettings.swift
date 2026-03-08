import Foundation

public enum CompactTabSettings {
    public static let leadingViewKey = "settings_compact_tab_primary_view"
    public static let trailingViewKey = "settings_compact_tab_secondary_view"
    public static let defaultLeadingView: BuiltInView = .upcoming
    public static let defaultTrailingView: BuiltInView = .logbook

    private static let baseCustomViews: [BuiltInView] = [
        .upcoming,
        .logbook,
        .myTasks,
        .delegated,
        .anytime,
        .someday,
        .flagged,
        .review
    ]

    public static func availableCustomViews(pomodoroEnabled: Bool) -> [BuiltInView] {
        var views = baseCustomViews
        if pomodoroEnabled {
            views.append(.pomodoro)
        }
        return views
    }

    public static func normalizedCustomViews(
        leadingRawValue: String,
        trailingRawValue: String,
        pomodoroEnabled: Bool
    ) -> (primary: BuiltInView, secondary: BuiltInView) {
        let available = availableCustomViews(pomodoroEnabled: pomodoroEnabled)
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

    private static func resolveCustomView(
        rawValue: String,
        available: [BuiltInView],
        fallbackOrder: [BuiltInView],
        excluding: [BuiltInView]
    ) -> BuiltInView {
        let excluded = Set(excluding)
        if let candidate = BuiltInView(rawValue: rawValue),
           available.contains(candidate),
           !excluded.contains(candidate) {
            return candidate
        }

        for candidate in fallbackOrder where available.contains(candidate) && !excluded.contains(candidate) {
            return candidate
        }

        return available.first(where: { !excluded.contains($0) }) ?? defaultLeadingView
    }
}
