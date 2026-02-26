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
        public var backgroundPrimary: String
        public var surface: String
        public var textPrimary: String
        public var textSecondary: String
        public var accent: String
        public var overdue: String

        public init(
            backgroundPrimary: String,
            surface: String,
            textPrimary: String,
            textSecondary: String,
            accent: String,
            overdue: String
        ) {
            self.backgroundPrimary = backgroundPrimary
            self.surface = surface
            self.textPrimary = textPrimary
            self.textSecondary = textSecondary
            self.accent = accent
            self.overdue = overdue
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
                    backgroundPrimary: "#FFFFFF",
                    surface: "#F8F8F8",
                    textPrimary: "#000000",
                    textSecondary: "#8E8E93",
                    accent: "#4A90D9",
                    overdue: "#E74C3C"
                ),
                spacing: .init(rowVertical: 10, rowHorizontal: 14, sectionGap: 18),
                shape: .init(cornerRadius: 10),
                motion: .init(completionSpringResponse: 0.34, completionSpringDamping: 0.82)
            )
        }
    }
}
