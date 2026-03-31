import SwiftUI

private enum InboxTriageField: Hashable {
    case project
}

struct InboxTriageView: View {
    @Environment(AppContainer.self) private var container
    @Environment(ThemeManager.self) private var theme

    let records: [TaskRecord]
    @Binding var skippedPaths: Set<String>
    @Binding var pinnedPath: String?
    let onExit: () -> Void
    let onOpenDetail: (String) -> Void

    @State private var projectDraft = ""
    @State private var rejectedPaths: Set<String> = []
    @FocusState private var focusedField: InboxTriageField?

    private var activeRecords: [TaskRecord] {
        records.filter { !skippedPaths.contains($0.identity.path) }
    }

    private var currentRecord: TaskRecord? {
        if let pinnedPath,
           let matched = activeRecords.first(where: { $0.identity.path == pinnedPath }) {
            return matched
        }
        return activeRecords.first
    }

    private var currentPath: String? {
        currentRecord?.identity.path
    }

    private var processedCount: Int {
        max(0, records.count - activeRecords.count)
    }

    private var currentSuggestion: ProjectTriageSuggestion? {
        guard let currentPath, !rejectedPaths.contains(currentPath) else { return nil }
        return container.inboxProjectSuggestion(path: currentPath)
    }

    private var projectSuggestions: [String] {
        let query = projectDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let allProjects = container.allProjects()
        let base = query.isEmpty
            ? container.recentProjects(limit: 6)
            : allProjects.filter { project in
                project.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        return Array(base.prefix(6))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard

                if let record = currentRecord {
                    taskCard(record)
                    suggestionCard(record)
                    manualCorrectionCard(record)
                    footerActions(record)
                } else {
                    emptyStateCard
                }
            }
            .padding(20)
        }
        .background(theme.backgroundColor.ignoresSafeArea())
        .onAppear(perform: syncQueueState)
        .onChange(of: records.map(\.identity.path), initial: true) { _, _ in
            syncQueueState()
        }
        .onChange(of: currentPath, initial: true) { _, _ in
            syncDraftsFromCurrentRecord()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Inbox Smart Triage")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(theme.textPrimaryColor)

                Spacer()

                Button("Exit") {
                    onExit()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityIdentifier("triage.exitButton")
            }

            Text(queueSummaryText)
                .font(.callout)
                .foregroundStyle(theme.textSecondaryColor)

            Text("Keyboard: A accept suggestion, R reject, P project field, Return next.")
                .font(.caption)
                .foregroundStyle(theme.textSecondaryColor)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func taskCard(_ record: TaskRecord) -> some View {
        let frontmatter = record.document.frontmatter
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(frontmatter.title)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(theme.textPrimaryColor)
                        .accessibilityIdentifier("triage.currentTitle")

                    if let ref = frontmatter.ref, !ref.isEmpty {
                        Text(ref)
                            .font(.caption)
                            .foregroundStyle(theme.textSecondaryColor)
                    }
                }

                Spacer()

                Button("Open Detail") {
                    onOpenDetail(record.identity.path)
                }
                .keyboardShortcut("o", modifiers: [])
                .accessibilityIdentifier("triage.openDetailButton")
            }

            let summary = metadataSummary(for: frontmatter)
            if !summary.isEmpty {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(theme.textSecondaryColor)
            }

            let body = record.document.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                Text(body)
                    .font(.body)
                    .foregroundStyle(theme.textPrimaryColor)
                    .lineLimit(5)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .accessibilityIdentifier("triage.card")
    }

    private func suggestionCard(_ record: TaskRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Suggested Project")
                .font(.headline)
                .foregroundStyle(theme.textPrimaryColor)

            if let suggestion = currentSuggestion {
                Text(suggestion.project)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.textPrimaryColor)
                    .accessibilityIdentifier("triage.suggestedProject")

                let keywordText = suggestion.matchedKeywords.map { "\($0.keyword) (\($0.weight))" }.joined(separator: ", ")
                if !keywordText.isEmpty {
                    Text("Reason: matched keywords \(keywordText)")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondaryColor)
                        .accessibilityIdentifier("triage.suggestionReason")
                }

                HStack(spacing: 10) {
                    Button("Accept") {
                        acceptSuggestion(suggestion)
                    }
                    .keyboardShortcut("a", modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("triage.acceptButton")

                    Button("Reject") {
                        rejectSuggestion(record)
                    }
                    .keyboardShortcut("r", modifiers: [])
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("triage.rejectButton")
                }
            } else {
                Text("No suggestion yet. Choose a project manually to train future suggestions.")
                    .font(.callout)
                    .foregroundStyle(theme.textSecondaryColor)

                Button("Reject") {
                    rejectSuggestion(record)
                }
                .keyboardShortcut("r", modifiers: [])
                .buttonStyle(.bordered)
                .accessibilityIdentifier("triage.rejectButton")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func manualCorrectionCard(_ record: TaskRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Manual Correction")
                .font(.headline)
                .foregroundStyle(theme.textPrimaryColor)

            HStack(spacing: 10) {
                TextField("Assign project", text: $projectDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .project)
                    .submitLabel(.done)
                    .onSubmit {
                        applyProjectDraft()
                    }
                    .accessibilityIdentifier("triage.projectField")

                Button("Focus P") {
                    focusedField = .project
                }
                .keyboardShortcut("p", modifiers: [])
                .buttonStyle(.bordered)

                Button("Apply") {
                    applyProjectDraft()
                }
                .buttonStyle(.borderedProminent)
                .disabled(projectDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("triage.projectApplyButton")
            }

            if !projectSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(projectSuggestions, id: \.self) { project in
                            Button(project) {
                                applyProject(project)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            if rejectedPaths.contains(record.identity.path) {
                Text("Suggestion rejected for this task.")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondaryColor)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func footerActions(_ record: TaskRecord) -> some View {
        HStack(spacing: 12) {
            Button("Complete C") {
                completeCurrent()
            }
            .keyboardShortcut("c", modifiers: [])
            .buttonStyle(.bordered)
            .accessibilityIdentifier("triage.completeButton")

            Button("Next") {
                advanceQueue()
            }
            .keyboardShortcut(.return, modifiers: [])
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("triage.nextButton")

            Spacer()

            Text(URL(fileURLWithPath: record.identity.path).lastPathComponent)
                .font(.caption2)
                .foregroundStyle(theme.textSecondaryColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 4)
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ContentUnavailableView(
                activeRecords.isEmpty && !records.isEmpty ? "Queue Complete" : "Inbox Cleared",
                systemImage: "tray.full",
                description: Text(activeRecords.isEmpty && !records.isEmpty
                                  ? "You processed the current inbox queue."
                                  : "There are no inbox tasks left to triage.")
            )

            if !records.isEmpty {
                Button("Restart Queue") {
                    skippedPaths.removeAll()
                    rejectedPaths.removeAll()
                    pinnedPath = records.first?.identity.path
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("triage.restartButton")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .accessibilityIdentifier("triage.emptyState")
    }

    private var queueSummaryText: String {
        if records.isEmpty {
            return "Inbox is empty."
        }
        if activeRecords.isEmpty {
            return "Processed \(processedCount) of \(records.count) tasks in this pass."
        }
        return "\(activeRecords.count) tasks left in queue. \(processedCount) processed."
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(theme.surfaceColor)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(theme.textSecondaryColor.opacity(0.08), lineWidth: 1)
            )
    }

    private func syncQueueState() {
        let validPaths = Set(records.map(\.identity.path))
        skippedPaths = skippedPaths.intersection(validPaths)
        rejectedPaths = rejectedPaths.intersection(validPaths)
        if let pinnedPath,
           (!validPaths.contains(pinnedPath) || skippedPaths.contains(pinnedPath)) {
            self.pinnedPath = nil
        }
        if self.pinnedPath == nil {
            self.pinnedPath = activeRecords.first?.identity.path
        }
    }

    private func syncDraftsFromCurrentRecord() {
        guard let currentRecord else {
            projectDraft = ""
            return
        }
        projectDraft = currentRecord.document.frontmatter.project ?? ""
    }

    private func advanceQueue() {
        guard let currentPath else { return }
        skippedPaths.insert(currentPath)
        pinnedPath = activeRecords.first(where: { $0.identity.path != currentPath })?.identity.path
        focusedField = nil
    }

    private func completeCurrent() {
        guard let currentPath else { return }
        container.complete(path: currentPath)
        pinnedPath = nil
    }

    private func acceptSuggestion(_ suggestion: ProjectTriageSuggestion) {
        guard let currentPath else { return }
        if container.applyInboxTriageProject(path: currentPath, project: suggestion.project, weight: 2) {
            rejectedPaths.remove(currentPath)
            projectDraft = ""
            advanceQueue()
        }
    }

    private func rejectSuggestion(_ record: TaskRecord) {
        rejectedPaths.insert(record.identity.path)
        focusedField = .project
    }

    private func applyProjectDraft() {
        let trimmed = projectDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        applyProject(trimmed)
    }

    private func applyProject(_ project: String) {
        guard let currentPath else { return }
        if container.applyInboxTriageProject(path: currentPath, project: project, weight: 1) {
            rejectedPaths.remove(currentPath)
            projectDraft = ""
            focusedField = nil
            advanceQueue()
        }
    }

    private func metadataSummary(for frontmatter: TaskFrontmatterV1) -> String {
        var parts: [String] = []
        if frontmatter.priority != .none {
            parts.append(frontmatter.priority.rawValue.capitalized)
        }
        if let project = frontmatter.project?.trimmingCharacters(in: .whitespacesAndNewlines),
           !project.isEmpty {
            parts.append(project)
        }
        parts.append(contentsOf: frontmatter.tags.prefix(3).map { "#\($0)" })
        return parts.joined(separator: "  ·  ")
    }
}
