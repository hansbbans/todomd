import Foundation

public struct ThemeTokens: Equatable, Sendable {
    public var colors: Colors
    public var spacing: Spacing
    public var shape: Shape
    public var motion: Motion

    public init(colors: Colors, spacing: Spacing, shape: Shape, motion: Motion) {
        self.colors = colors
        self.spacing = spacing
        self.shape = shape
        self.motion = motion
    }

    public struct Colors: Equatable, Sendable {
        public var backgroundPrimaryLight: String
        public var backgroundPrimaryDark: String
        public var surfaceLight: String
        public var surfaceDark: String
        public var textPrimaryLight: String
        public var textPrimaryDark: String
        public var textSecondary: String
        public var accentLight: String
        public var accentDark: String
        public var overdueLight: String
        public var overdueDark: String
        public var priorityMediumLight: String
        public var priorityMediumDark: String
        public var priorityLowLight: String
        public var priorityLowDark: String
        public var separatorLight: String
        public var separatorDark: String

        public init(
            backgroundPrimaryLight: String,
            backgroundPrimaryDark: String,
            surfaceLight: String,
            surfaceDark: String,
            textPrimaryLight: String,
            textPrimaryDark: String,
            textSecondary: String,
            accentLight: String,
            accentDark: String,
            overdueLight: String,
            overdueDark: String,
            priorityMediumLight: String,
            priorityMediumDark: String,
            priorityLowLight: String,
            priorityLowDark: String,
            separatorLight: String,
            separatorDark: String
        ) {
            self.backgroundPrimaryLight = backgroundPrimaryLight
            self.backgroundPrimaryDark = backgroundPrimaryDark
            self.surfaceLight = surfaceLight
            self.surfaceDark = surfaceDark
            self.textPrimaryLight = textPrimaryLight
            self.textPrimaryDark = textPrimaryDark
            self.textSecondary = textSecondary
            self.accentLight = accentLight
            self.accentDark = accentDark
            self.overdueLight = overdueLight
            self.overdueDark = overdueDark
            self.priorityMediumLight = priorityMediumLight
            self.priorityMediumDark = priorityMediumDark
            self.priorityLowLight = priorityLowLight
            self.priorityLowDark = priorityLowDark
            self.separatorLight = separatorLight
            self.separatorDark = separatorDark
        }
    }

    public struct Spacing: Equatable, Sendable {
        public var rowVertical: Double
        public var rowHorizontal: Double
        public var sectionGap: Double

        public init(rowVertical: Double, rowHorizontal: Double, sectionGap: Double) {
            self.rowVertical = rowVertical
            self.rowHorizontal = rowHorizontal
            self.sectionGap = sectionGap
        }
    }

    public struct Shape: Equatable, Sendable {
        public var cornerRadius: Double

        public init(cornerRadius: Double) {
            self.cornerRadius = cornerRadius
        }
    }

    public struct Motion: Equatable, Sendable {
        public var completionSpringResponse: Double
        public var completionSpringDamping: Double

        public init(completionSpringResponse: Double, completionSpringDamping: Double) {
            self.completionSpringResponse = completionSpringResponse
            self.completionSpringDamping = completionSpringDamping
        }
    }
}

public enum ThemePreset: String, CaseIterable, Sendable {
    case classic
}

public protocol ThemeTokenLoading {
    func loadPreset(_ preset: ThemePreset) -> ThemeTokens
}

public struct ThemeTokenStore: ThemeTokenLoading {
    public init() {}

    public func loadPreset(_ preset: ThemePreset) -> ThemeTokens {
        switch preset {
        case .classic:
            return ThemeTokens(
                colors: .init(
                    backgroundPrimaryLight: "#F2F2F7",
                    backgroundPrimaryDark: "#1C1C1E",
                    surfaceLight: "#FFFFFF",
                    surfaceDark: "#2C2C2E",
                    textPrimaryLight: "#1C1C1E",
                    textPrimaryDark: "#F2F2F7",
                    textSecondary: "#8E8E93",
                    accentLight: "#4A7FD4",
                    accentDark: "#5E9BF5",
                    overdueLight: "#D94F3D",
                    overdueDark: "#FF6B6B",
                    priorityMediumLight: "#F5A623",
                    priorityMediumDark: "#FFB84D",
                    priorityLowLight: "#7ED321",
                    priorityLowDark: "#98E44A",
                    separatorLight: "#E5E5EA",
                    separatorDark: "#38383A"
                ),
                spacing: .init(rowVertical: 14, rowHorizontal: 16, sectionGap: 28),
                shape: .init(cornerRadius: 12),
                motion: .init(completionSpringResponse: 0.28, completionSpringDamping: 0.78)
            )
        }
    }
}
