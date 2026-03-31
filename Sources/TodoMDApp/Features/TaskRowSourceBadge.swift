import SwiftUI

struct TaskRowSourceBadge: View {
    let badge: TaskSourceAttribution.Badge
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Label(badge.label, systemImage: badge.systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(theme.accentColor)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(theme.accentColor.opacity(0.12))
            )
            .accessibilityLabel(badge.accessibilityLabel)
    }
}
