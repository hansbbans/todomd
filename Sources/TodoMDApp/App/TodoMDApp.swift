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
    @AppStorage("did_complete_onboarding") private var didCompleteOnboarding = false

    var body: some Scene {
        WindowGroup {
            Group {
                if didCompleteOnboarding {
                    RootView()
                        .onOpenURL { url in
                            container.handleIncomingURL(url)
                        }
                } else {
                    OnboardingView {
                        didCompleteOnboarding = true
                    }
                }
            }
            .environmentObject(container)
#if canImport(SwiftData)
            .modelContainer(container.modelContainer)
#endif
        }
    }
}
