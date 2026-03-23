import SwiftUI

enum ThingsSurfaceKind {
    case floatingPanel
    case elevatedCard
    case compactOverlay
    case inset

    var cornerRadius: CGFloat {
        switch self {
        case .floatingPanel:
            return 20
        case .elevatedCard, .compactOverlay:
            return 24
        case .inset:
            return 18
        }
    }
}

enum ThingsSurfaceEmphasis {
    case standard
    case warning
}

enum ThingsSurfaceLayout {
    static let heroHorizontalPadding: CGFloat = 24
    static let heroTopPadding: CGFloat = 68
    static let heroBottomPadding: CGFloat = 10
    static let supportingCardTopPadding: CGFloat = 4
    static let supportingCardBottomPadding: CGFloat = 18
    static let emptyStateTopPadding: CGFloat = 22
    static let emptyStateBottomPadding: CGFloat = 44
    static let floatingCardHorizontalInset: CGFloat = 10
    static let floatingCardVerticalInset: CGFloat = 7
    static let quickFindTopPadding: CGFloat = 58
    static let upcomingBottomPadding: CGFloat = 104
}

enum ThingsSurfaceMotion {
    static let overlayOpen: Animation = .spring(response: 0.3, dampingFraction: 0.86, blendDuration: 0.12)
    static let overlayClose: Animation = .spring(response: 0.23, dampingFraction: 0.95, blendDuration: 0.1)
}

private struct ThingsSurfaceShadowLayer {
    let color: Color
    let radius: CGFloat
    let y: CGFloat
}

struct ThingsSurfaceBackdrop: View {
    let kind: ThingsSurfaceKind
    let theme: ThemeManager
    let colorScheme: ColorScheme
    var emphasis: ThingsSurfaceEmphasis = .standard

    var body: some View {
        RoundedRectangle(cornerRadius: kind.cornerRadius, style: .continuous)
            .fill(fillGradient)
            .overlay {
                RoundedRectangle(cornerRadius: kind.cornerRadius, style: .continuous)
                    .fill(highlightGradient)
            }
            .overlay {
                RoundedRectangle(cornerRadius: kind.cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .modifier(ThingsSurfaceShadowModifier(layers: shadowLayers))
    }

    private var fillGradient: LinearGradient {
        switch kind {
        case .floatingPanel:
            if colorScheme == .dark {
                return LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.13, blue: 0.16),
                        Color(red: 0.09, green: 0.10, blue: 0.13)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            return LinearGradient(
                colors: [
                    theme.surfaceColor.opacity(0.99),
                    theme.backgroundColor.opacity(0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

        case .elevatedCard:
            if colorScheme == .dark {
                return LinearGradient(
                    colors: [
                        Color(red: 0.115, green: 0.12, blue: 0.15),
                        Color(red: 0.09, green: 0.095, blue: 0.118)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            return LinearGradient(
                colors: [
                    theme.surfaceColor.opacity(0.985),
                    theme.backgroundColor.opacity(0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

        case .compactOverlay:
            return LinearGradient(
                colors: [
                    Color(.sRGB, red: 0.128, green: 0.149, blue: 0.182, opacity: 0.985),
                    Color(.sRGB, red: 0.095, green: 0.109, blue: 0.132, opacity: 0.995)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

        case .inset:
            if colorScheme == .dark {
                return LinearGradient(
                    colors: [
                        theme.backgroundColor.opacity(0.92),
                        theme.surfaceColor.opacity(0.84)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            return LinearGradient(
                colors: [
                    theme.backgroundColor.opacity(0.98),
                    theme.surfaceColor.opacity(0.9)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var highlightGradient: LinearGradient {
        switch kind {
        case .compactOverlay:
            return LinearGradient(
                colors: [
                    .white.opacity(0.055),
                    .clear,
                    .black.opacity(0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

        case .inset:
            return LinearGradient(
                colors: [
                    .white.opacity(colorScheme == .dark ? 0.025 : 0.08),
                    .clear,
                    .black.opacity(colorScheme == .dark ? 0.04 : 0.01)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

        case .floatingPanel, .elevatedCard:
            return LinearGradient(
                colors: [
                    .white.opacity(colorScheme == .dark ? 0.03 : 0.12),
                    .clear,
                    .black.opacity(colorScheme == .dark ? 0.06 : 0.015)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var borderColor: Color {
        if emphasis == .warning {
            return Color.orange.opacity(colorScheme == .dark ? 0.45 : 0.4)
        }

        switch kind {
        case .compactOverlay:
            return .white.opacity(0.065)
        case .inset:
            return colorScheme == .dark ? .white.opacity(0.08) : theme.textSecondaryColor.opacity(0.12)
        case .floatingPanel:
            return colorScheme == .dark ? .white.opacity(0.08) : theme.textSecondaryColor.opacity(0.15)
        case .elevatedCard:
            return colorScheme == .dark ? .white.opacity(0.07) : theme.textSecondaryColor.opacity(0.14)
        }
    }

    private var shadowLayers: [ThingsSurfaceShadowLayer] {
        switch kind {
        case .inset:
            return []
        case .floatingPanel:
            if colorScheme == .dark {
                return [
                    ThingsSurfaceShadowLayer(color: .black.opacity(0.32), radius: 24, y: 12),
                    ThingsSurfaceShadowLayer(color: .black.opacity(0.14), radius: 8, y: 3)
                ]
            }

            return [
                ThingsSurfaceShadowLayer(color: .black.opacity(0.11), radius: 20, y: 10),
                ThingsSurfaceShadowLayer(color: .black.opacity(0.04), radius: 8, y: 2)
            ]

        case .elevatedCard:
            if colorScheme == .dark {
                return [
                    ThingsSurfaceShadowLayer(color: .black.opacity(0.28), radius: 18, y: 10),
                    ThingsSurfaceShadowLayer(color: .black.opacity(0.10), radius: 6, y: 2)
                ]
            }

            return [
                ThingsSurfaceShadowLayer(color: .black.opacity(0.09), radius: 18, y: 9),
                ThingsSurfaceShadowLayer(color: .black.opacity(0.03), radius: 6, y: 2)
            ]

        case .compactOverlay:
            return [
                ThingsSurfaceShadowLayer(color: .black.opacity(0.3), radius: 24, y: 14),
                ThingsSurfaceShadowLayer(color: .black.opacity(0.14), radius: 8, y: 3)
            ]
        }
    }
}

private struct ThingsSurfaceShadowModifier: ViewModifier {
    let layers: [ThingsSurfaceShadowLayer]

    func body(content: Content) -> some View {
        if let first = layers.first {
            content
                .shadow(color: first.color, radius: first.radius, y: first.y)
                .modifier(ThingsSurfaceSecondaryShadowModifier(layers: Array(layers.dropFirst())))
        } else {
            content
        }
    }
}

private struct ThingsSurfaceSecondaryShadowModifier: ViewModifier {
    let layers: [ThingsSurfaceShadowLayer]

    func body(content: Content) -> some View {
        if let first = layers.first {
            content
                .shadow(color: first.color, radius: first.radius, y: first.y)
                .modifier(ThingsSurfaceSecondaryShadowModifier(layers: Array(layers.dropFirst())))
        } else {
            content
        }
    }
}
