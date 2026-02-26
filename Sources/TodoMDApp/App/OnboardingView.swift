import SwiftUI

struct OnboardingView: View {
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text("Welcome to todo.md")
                    .font(.largeTitle.bold())

                VStack(alignment: .leading, spacing: 12) {
                    Label("Your task files are plain markdown in iCloud Drive", systemImage: "doc.text")
                    Label("External tools can create/update tasks by writing .md files", systemImage: "externaldrive")
                    Label("The app keeps a local SwiftData index for fast filtering", systemImage: "speedometer")
                    Label("Conflicts and malformed files are surfaced in-app", systemImage: "shield.lefthalf.filled")
                }
                .font(.subheadline)

                Spacer()

                Button("Get Started") {
                    onDone()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .navigationBarBackButtonHidden(true)
        }
    }
}
