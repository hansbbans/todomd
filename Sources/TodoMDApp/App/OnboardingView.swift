import SwiftUI
import UniformTypeIdentifiers

private enum OnboardingFolderChoice {
    case useDefault
    case chooseExisting
}

struct OnboardingView: View {
    let onDone: () -> Void

    @EnvironmentObject private var container: AppContainer

    @State private var page = 0
    @State private var resolvedFolderPath: String?
    @State private var selectedFolderChoice: OnboardingFolderChoice?
    @State private var showingFolderPicker = false
    @State private var folderError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    pageWelcome
                        .tag(0)
                    pageWorkflow
                        .tag(1)
                    pageICloud
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                HStack {
                    if page > 0 {
                        Button("Back") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                page = max(0, page - 1)
                            }
                        }
                        .accessibilityIdentifier("onboarding.backButton")
                    }

                    Spacer()

                    if page < 2 {
                        Button("Next") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                page = min(2, page + 1)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("onboarding.nextButton")
                    } else {
                        Button("Get Started") {
                            onDone()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedFolderChoice == nil)
                        .accessibilityIdentifier("onboarding.getStartedButton")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("Welcome")
            .navigationBarBackButtonHidden(true)
            .fileImporter(
                isPresented: $showingFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleFolderSelection(result: result)
            }
            .onAppear {
                refreshResolvedFolder()
            }
        }
    }

    private var pageWelcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Welcome to todo.md")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))

            Text("A Things-inspired task app powered by plain markdown files.")
                .font(.title3)
                .foregroundStyle(.secondary)

            Label("Your data stays in iCloud Drive", systemImage: "icloud")
            Label("Every task is a real .md file", systemImage: "doc.text")
            Label("No proprietary database lock-in", systemImage: "lock.open")

            Spacer()
        }
        .padding(24)
    }

    private var pageWorkflow: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Quick Tour")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))

            Label("Inbox, Today, Upcoming, Anytime, Someday", systemImage: "list.bullet.rectangle")
            Label("Swipe to complete or defer tasks", systemImage: "hand.draw")
            Label("Use + for quick capture with natural language dates", systemImage: "plus.circle")
            Label("Open a task for full details and notes", systemImage: "square.and.pencil")

            Spacer()
        }
        .padding(24)
    }

    private var pageICloud: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Storage Location")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))

            Text("Where should your default task folder live?")
                .foregroundStyle(.secondary)

            Button {
                useDefaultFolder()
            } label: {
                folderChoiceRow(
                    title: "Use Default",
                    subtitle: "Creates iCloud Drive/todomd",
                    icon: "folder.badge.plus",
                    isSelected: selectedFolderChoice == .useDefault
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.useDefaultButton")

            Button {
                showingFolderPicker = true
            } label: {
                folderChoiceRow(
                    title: "Choose Existing",
                    subtitle: "Select an existing folder in iCloud Drive",
                    icon: "folder",
                    isSelected: selectedFolderChoice == .chooseExisting
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.chooseExistingButton")

            if let folderError {
                Text(folderError)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            if let resolvedFolderPath {
                Text("Selected folder path")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(resolvedFolderPath)
                    .font(.callout.monospaced())
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.12)))
            }

            Spacer()
        }
        .padding(24)
    }

    private func folderChoiceRow(title: String, subtitle: String, icon: String, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(isSelected ? .white : .accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(isSelected ? .white : .primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
        )
    }

    private func useDefaultFolder() {
        let defaults = UserDefaults.standard
        defaults.set("todomd", forKey: TaskFolderPreferences.legacyFolderNameKey)
        TaskFolderPreferences.clearSelectedFolder(defaults: defaults)
        selectedFolderChoice = .useDefault
        refreshResolvedFolder()
        container.reloadStorageLocation()
    }

    private func handleFolderSelection(result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls):
            guard let selectedURL = urls.first else { return }
            guard isLikelyICloudFolder(selectedURL) else {
                folderError = "Please choose a folder inside iCloud Drive."
                return
            }
            do {
                try TaskFolderPreferences.saveSelectedFolder(selectedURL)
                selectedFolderChoice = .chooseExisting
                folderError = nil
                refreshResolvedFolder()
                container.reloadStorageLocation()
            } catch {
                folderError = error.localizedDescription
            }
        case .failure(let error):
            folderError = error.localizedDescription
        }
    }

    private func refreshResolvedFolder() {
        do {
            let url = try TaskFolderLocator().ensureFolderExists()
            resolvedFolderPath = url.path
            folderError = nil
        } catch {
            folderError = error.localizedDescription
        }
    }

    private func isLikelyICloudFolder(_ url: URL) -> Bool {
        let normalizedPath = url.standardizedFileURL.path.lowercased()
        if normalizedPath.contains("/mobile documents/com~apple~clouddocs") {
            return true
        }

        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey])
        return values?.isUbiquitousItem == true
    }
}
