import SwiftUI

final class ThemeManager: ObservableObject {
    @Published private(set) var tokens: ThemeTokens

    init(loader: ThemeTokenLoading = ThemeTokenStore()) {
        self.tokens = loader.loadPreset(.classic)
    }

    var backgroundColor: Color {
        dynamic(lightHex: tokens.colors.backgroundPrimaryLight, darkHex: tokens.colors.backgroundPrimaryDark)
    }

    var surfaceColor: Color {
        dynamic(lightHex: tokens.colors.surfaceLight, darkHex: tokens.colors.surfaceDark)
    }

    var textPrimaryColor: Color {
        dynamic(lightHex: tokens.colors.textPrimaryLight, darkHex: tokens.colors.textPrimaryDark)
    }

    var textSecondaryColor: Color {
        Color(hex: tokens.colors.textSecondary)
    }

    var accentColor: Color {
        dynamic(lightHex: tokens.colors.accentLight, darkHex: tokens.colors.accentDark)
    }

    var overdueColor: Color {
        dynamic(lightHex: tokens.colors.overdueLight, darkHex: tokens.colors.overdueDark)
    }

    func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .none:
            return textSecondaryColor
        case .low:
            return dynamic(lightHex: tokens.colors.priorityLowLight, darkHex: tokens.colors.priorityLowDark)
        case .medium:
            return dynamic(lightHex: tokens.colors.priorityMediumLight, darkHex: tokens.colors.priorityMediumDark)
        case .high:
            return overdueColor
        }
    }

    private func dynamic(lightHex: String, darkHex: String) -> Color {
        Color(UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(hex: darkHex)
            }
            return UIColor(hex: lightHex)
        })
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        var rgbValue: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgbValue)

        let red = CGFloat((rgbValue & 0xFF0000) >> 16) / 255
        let green = CGFloat((rgbValue & 0x00FF00) >> 8) / 255
        let blue = CGFloat(rgbValue & 0x0000FF) / 255

        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}

private extension Color {
    init(hex: String) {
        self = Color(UIColor(hex: hex))
    }
}
