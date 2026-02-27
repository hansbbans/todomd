import SwiftUI
#if canImport(SwiftData)
import SwiftData
#endif

@main
struct TodoMDApp: App {
#if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
#endif
    @StateObject private var container = AppContainer()
    @StateObject private var theme = ThemeManager()
    @AppStorage("did_complete_onboarding") private var didCompleteOnboarding = false
    @AppStorage("settings_appearance_mode") private var appearanceMode = "system"
    @State private var forceOnboardingForUITest: Bool

    init() {
        _forceOnboardingForUITest = State(initialValue: ProcessInfo.processInfo.arguments.contains("-ui-testing-force-onboarding"))
        applyUITestConfigurationIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if didCompleteOnboarding && !forceOnboardingForUITest {
                    RootView()
                        .onOpenURL { url in
                            container.handleIncomingURL(url)
                        }
                } else {
                    OnboardingView {
                        didCompleteOnboarding = true
                        forceOnboardingForUITest = false
                    }
                }
            }
            .environmentObject(container)
            .environmentObject(theme)
            .tint(theme.accentColor)
            .preferredColorScheme(preferredColorScheme)
#if canImport(SwiftData)
            .modelContainer(container.modelContainer)
#endif
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }

    private func applyUITestConfigurationIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-ui-testing"),
              arguments.contains("-ui-testing-reset") else {
            return
        }

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "did_complete_onboarding")
        defaults.removeObject(forKey: TaskFolderPreferences.legacyFolderNameKey)
        TaskFolderPreferences.clearSelectedFolder(defaults: defaults)
    }
}
