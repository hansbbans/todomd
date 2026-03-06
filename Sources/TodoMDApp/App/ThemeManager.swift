import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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

    var separatorColor: Color {
        dynamic(lightHex: tokens.colors.separatorLight, darkHex: tokens.colors.separatorDark)
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
        #if canImport(UIKit)
        Color(UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(hex: darkHex)
            }
            return UIColor(hex: lightHex)
        })
        #elseif canImport(AppKit)
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            if match == .darkAqua {
                return NSColor(hex: darkHex)
            }
            return NSColor(hex: lightHex)
        })
        #else
        Color(hex: lightHex)
        #endif
    }
}

private extension PlatformColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        var rgbValue: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgbValue)

        let red = CGFloat((rgbValue & 0xFF0000) >> 16) / 255
        let green = CGFloat((rgbValue & 0x00FF00) >> 8) / 255
        let blue = CGFloat(rgbValue & 0x0000FF) / 255

        #if canImport(UIKit)
        self.init(red: red, green: green, blue: blue, alpha: 1)
        #elseif canImport(AppKit)
        self.init(red: red, green: green, blue: blue, alpha: 1)
        #endif
    }
}

private extension Color {
    init(hex: String) {
        #if canImport(UIKit)
        self = Color(UIColor(hex: hex))
        #elseif canImport(AppKit)
        self = Color(nsColor: NSColor(hex: hex))
        #else
        self = .clear
        #endif
    }
}

#if canImport(UIKit)
private typealias PlatformColor = UIColor
#elseif canImport(AppKit)
private typealias PlatformColor = NSColor
#endif
