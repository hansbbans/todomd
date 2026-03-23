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
    @State private var activeIntegrationPrimer: OnboardingIntegrationPrimer?
    @State private var isRequestingIntegrationAccess = false

    var body: some View {
        NavigationStack {
            ZStack {
                onboardingBackdrop

                VStack(spacing: 0) {
                    TabView(selection: $page) {
                        pageWelcome
                            .tag(0)
                        pageWorkflow
                            .tag(1)
                        pageICloud
                            .tag(2)
                    }
                    .modifier(OnboardingTabViewStyle())

                    VStack(spacing: 14) {
                        onboardingPageIndicator

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
                                Button(nextButtonTitle) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        page = min(2, page + 1)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("onboarding.nextButton")
                            } else {
                                Button(finishButtonTitle) {
                                    beginCompletionFlow()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(selectedFolderChoice == nil || isRequestingIntegrationAccess)
                                .accessibilityIdentifier("onboarding.getStartedButton")
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(.thinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(Color.white.opacity(0.34), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 18, y: 8)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .allowsHitTesting(activeIntegrationPrimer == nil)

                if let activeIntegrationPrimer {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()

                    OnboardingIntegrationPrimerCard(
                        primer: activeIntegrationPrimer,
                        isBusy: isRequestingIntegrationAccess,
                        onSkip: {
                            skipIntegrationPrimer(activeIntegrationPrimer)
                        },
                        onContinue: {
                            continueIntegrationPrimer(activeIntegrationPrimer)
                        }
                    )
                }
            }
            .navigationTitle("")
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

    private var onboardingBackdrop: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.96, blue: 0.93),
                    Color(red: 0.93, green: 0.95, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.white.opacity(0.6))
                .frame(width: 300, height: 300)
                .blur(radius: 10)
                .offset(x: 140, y: -240)

            Circle()
                .fill(Color(red: 0.83, green: 0.9, blue: 0.99).opacity(0.45))
                .frame(width: 260, height: 260)
                .blur(radius: 20)
                .offset(x: -150, y: 260)
        }
    }

    private var onboardingPageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == page ? Color.accentColor : Color.primary.opacity(0.12))
                    .frame(width: index == page ? 28 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.18), value: page)
            }
        }
    }

    private var nextButtonTitle: String {
        switch page {
        case 0:
            return "See How It Works"
        case 1:
            return "Choose Folder"
        default:
            return "Next"
        }
    }

    private var finishButtonTitle: String {
        selectedFolderChoice == nil ? "Choose a Folder" : "Open Inbox"
    }

    private var pageWelcome: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                Text("todo.md")
                    .font(.system(size: 42, weight: .bold, design: .rounded))

                Text("Plain markdown tasks, with the calm speed of Things.")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                welcomePreviewCard

                VStack(alignment: .leading, spacing: 14) {
                    onboardingBenefitRow(
                        title: "Files stay yours",
                        body: "Every task is a real markdown file in iCloud Drive.",
                        icon: "doc.text"
                    )
                    onboardingBenefitRow(
                        title: "Fast by default",
                        body: "Capture first, organize later, and keep the app out of your way.",
                        icon: "bolt"
                    )
                    onboardingBenefitRow(
                        title: "Easy to trust",
                        body: "No lock-in, no hidden database, no mystery about where things live.",
                        icon: "lock.open"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 18)
        }
    }

    private var pageWorkflow: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                Text("How it works")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))

                Text("Three quick habits keep the app feeling light.")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                workflowStepCard(
                    step: "1",
                    title: "Capture in a line",
                    body: "Use the plus button and type naturally. Dates like tomorrow are understood as you go.",
                    icon: "plus.circle"
                )

                workflowStepCard(
                    step: "2",
                    title: "Sort only when needed",
                    body: "Start in Inbox, then add a project, tag, or date when it actually helps.",
                    icon: "tray"
                )

                workflowStepCard(
                    step: "3",
                    title: "Move through the day",
                    body: "Review Today, Upcoming, and Someday without giving up the simplicity of plain files.",
                    icon: "checkmark.circle"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 18)
        }
    }

    private var pageICloud: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Open to Inbox")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))

                Text("Choose where your tasks live. The default setup is the fastest path, and you can change it later.")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("After this, you will land in Inbox ready to add your first task.")
                            .font(.headline)
                        Text("Keep setup light now. You can fine-tune folders and integrations afterward.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.58))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.34), lineWidth: 1)
                )

                Button {
                    useDefaultFolder()
                } label: {
                    folderChoiceRow(
                        title: "Use Default",
                        subtitle: "Create iCloud Drive/todomd and start there.",
                        icon: "folder.badge.plus",
                        badge: "Recommended",
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
                        subtitle: "Use a folder you already keep in iCloud Drive.",
                        icon: "folder",
                        badge: nil,
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

                if let selectedFolderChoice,
                   let resolvedFolderPath
                {
                    selectedFolderSummaryCard(
                        choice: selectedFolderChoice,
                        path: resolvedFolderPath
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 18)
        }
    }

    private var welcomePreviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Inbox")
                    .font(.headline)
                Spacer()
                Text("Today")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            previewTaskRow(title: "Draft launch note", detail: "Today")
            previewTaskRow(title: "Buy coffee filters", detail: "Inbox")
            previewTaskRow(title: "Plan trip due Friday", detail: "Upcoming")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.34), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 16, y: 8)
    }

    private func previewTaskRow(title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Circle()
                .stroke(Color.primary.opacity(0.18), lineWidth: 1.5)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.72))
        )
    }

    private func onboardingBenefitRow(title: String, body: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func workflowStepCard(step: String, title: String, body: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 8) {
                Text(step)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.72))
                    )

                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.34), lineWidth: 1)
        )
    }

    private func selectedFolderSummaryCard(choice: OnboardingFolderChoice, path: String) -> some View {
        let url = URL(fileURLWithPath: path)
        let folderName = url.lastPathComponent
        let summaryTitle = choice == .useDefault ? "Ready to open Inbox" : "Ready to use \(folderName)"
        let summaryBody = choice == .useDefault
            ? "Your tasks will live in iCloud Drive/todomd so you can start immediately."
            : "Your tasks will stay in the folder you picked, and the app will open straight to Inbox."

        return VStack(alignment: .leading, spacing: 8) {
            Text(summaryTitle)
                .font(.headline)
            Text(summaryBody)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.34), lineWidth: 1)
        )
    }

    private func folderChoiceRow(
        title: String,
        subtitle: String,
        icon: String,
        badge: String?,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.white.opacity(0.22) : Color.white.opacity(0.72))
                    .frame(width: 42, height: 42)

                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(isSelected ? .white : .primary)

                    if let badge {
                        Text(badge)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isSelected ? Color.white.opacity(0.18) : Color.accentColor.opacity(0.12))
                            )
                            .foregroundStyle(isSelected ? .white : Color.accentColor)
                    }
                }

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? .white.opacity(0.88) : .secondary)
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? .white : Color.primary.opacity(0.18))
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    isSelected
                        ? LinearGradient(
                            colors: [
                                Color.accentColor,
                                Color.accentColor.opacity(0.84)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        : LinearGradient(
                            colors: [
                                Color.white.opacity(0.72),
                                Color.white.opacity(0.54)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(isSelected ? Color.white.opacity(0.14) : Color.white.opacity(0.34), lineWidth: 1)
        )
        .shadow(color: isSelected ? Color.accentColor.opacity(0.16) : Color.black.opacity(0.04), radius: 12, y: 6)
    }

    private func useDefaultFolder() {
        TaskFolderPreferences.setLegacyFolderName("todomd")
        TaskFolderPreferences.clearSelectedFolder()
        selectedFolderChoice = .useDefault
        folderError = nil
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

    private func beginCompletionFlow() {
        guard !isRequestingIntegrationAccess else { return }

        if let primer = onboardingPrimerCoordinator.initialPrimer() {
            activeIntegrationPrimer = primer
        } else {
            onDone()
        }
    }

    private func skipIntegrationPrimer(_ primer: OnboardingIntegrationPrimer) {
        persistIntegrationEnabled(false, for: primer)
        activeIntegrationPrimer = nil
        proceedAfterHandlingIntegrationPrimer(primer)
    }

    private func continueIntegrationPrimer(_ primer: OnboardingIntegrationPrimer) {
        guard !isRequestingIntegrationAccess else { return }

        activeIntegrationPrimer = nil
        isRequestingIntegrationAccess = true
        persistIntegrationEnabled(true, for: primer)

        Task { @MainActor in
            switch primer {
            case .reminders:
                _ = await container.requestRemindersAccess()
                await container.setRemindersIntegrationEnabled(container.isRemindersAccessGranted)
            case .calendar:
                await container.connectCalendar()
                persistIntegrationEnabled(container.isCalendarConnected, for: primer)
            }

            isRequestingIntegrationAccess = false
            proceedAfterHandlingIntegrationPrimer(primer)
        }
    }

    private func proceedAfterHandlingIntegrationPrimer(_ primer: OnboardingIntegrationPrimer) {
        if let nextPrimer = onboardingPrimerCoordinator.nextPrimer(after: primer) {
            activeIntegrationPrimer = nextPrimer
        } else {
            onDone()
        }
    }

    private func persistIntegrationEnabled(_ isEnabled: Bool, for primer: OnboardingIntegrationPrimer) {
        UserDefaults.standard.set(isEnabled, forKey: primer.settingsKey)
    }

    private var onboardingPrimerCoordinator: OnboardingIntegrationPrimerCoordinator {
        OnboardingIntegrationPrimerCoordinator(
            remindersNeedsExplanation: container.remindersAccessNeedsExplanationBeforeRequest,
            calendarNeedsExplanation: container.calendarAccessNeedsExplanationBeforeRequest
        )
    }
}

private struct OnboardingTabViewStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.tabViewStyle(.page(indexDisplayMode: .never))
        #else
        content
        #endif
    }
}

private struct OnboardingIntegrationPrimerCard: View {
    let primer: OnboardingIntegrationPrimer
    let isBusy: Bool
    let onSkip: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(primer.title)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .accessibilityIdentifier("onboarding.accessPrimer.title")

            Text(primer.message)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("onboarding.accessPrimer.message")

            HStack(spacing: 12) {
                Button("Not Now", role: .cancel) {
                    onSkip()
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)
                .accessibilityIdentifier("onboarding.accessPrimer.skipButton")

                Spacer(minLength: 0)

                Button("Continue") {
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)
                .accessibilityIdentifier("onboarding.accessPrimer.continueButton")
            }
        }
        .padding(24)
        .frame(maxWidth: 360, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(24)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.accessPrimer.modal")
    }
}
