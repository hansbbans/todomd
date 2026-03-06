import SwiftUI

private enum InboxTriageField: Hashable {
    case project
    case tags
}

struct InboxTriageView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var theme: ThemeManager

    let records: [TaskRecord]
    @Binding var skippedPaths: Set<String>
    @Binding var pinnedPath: String?
    let onExit: () -> Void
    let onOpenDetail: (String) -> Void

    @State private var projectDraft = ""
    @State private var tagsDraft = ""
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

    private var currentTags: [String] {
        currentRecord?.document.frontmatter.tags ?? []
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

    private var tagSuggestions: [String] {
        let query = tagsDraft
            .split(separator: ",")
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "") ?? ""
        let existing = Set(currentTags)
        let base = container.availableTags().filter { !existing.contains($0) }
        let filtered = query.isEmpty
            ? base
            : base.filter { tag in
                tag.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        return Array(filtered.prefix(8))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard

                if let record = currentRecord {
                    taskCard(record)
                    quickActionCard(record)
                    projectCard(record)
                    tagsCard(record)
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
                Text("Inbox Triage")
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

            Text("Keyboard: P project, T tags, D today, M tomorrow, W next week, X clear date, 0-3 priority, Return next.")
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

    private func quickActionCard(_ record: TaskRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Fast Assign")
                .font(.headline)
                .foregroundStyle(theme.textPrimaryColor)

            VStack(alignment: .leading, spacing: 10) {
                Text("Priority")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textSecondaryColor)

                HStack(spacing: 8) {
                    priorityButton(title: "0 None", priority: .none, shortcut: "0", current: record.document.frontmatter.priority)
                    priorityButton(title: "1 High", priority: .high, shortcut: "1", current: record.document.frontmatter.priority)
                    priorityButton(title: "2 Medium", priority: .medium, shortcut: "2", current: record.document.frontmatter.priority)
                    priorityButton(title: "3 Low", priority: .low, shortcut: "3", current: record.document.frontmatter.priority)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Due Date")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textSecondaryColor)

                HStack(spacing: 8) {
                    dueButton(title: "D Today", shortcut: "d", date: Date())
                    dueButton(title: "M Tomorrow", shortcut: "m", date: Calendar.current.date(byAdding: .day, value: 1, to: Date()))
                    dueButton(title: "W Next Week", shortcut: "w", date: Calendar.current.date(byAdding: .day, value: 7, to: Date()))
                    Button("X Clear") {
                        applyDue(nil)
                    }
                    .keyboardShortcut("x", modifiers: [])
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func projectCard(_ record: TaskRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Project")
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

            if let currentProject = record.document.frontmatter.project,
               !currentProject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Current: \(currentProject)")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondaryColor)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func tagsCard(_ record: TaskRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tags")
                .font(.headline)
                .foregroundStyle(theme.textPrimaryColor)

            HStack(spacing: 10) {
                TextField("Add tags (comma-separated)", text: $tagsDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .tags)
                    .submitLabel(.done)
                    .onSubmit {
                        applyTagsDraft()
                    }
                    .accessibilityIdentifier("triage.tagsField")

                Button("Focus T") {
                    focusedField = .tags
                }
                .keyboardShortcut("t", modifiers: [])
                .buttonStyle(.bordered)

                Button("Apply") {
                    applyTagsDraft()
                }
                .buttonStyle(.borderedProminent)
                .disabled(normalizedTagTokens(from: tagsDraft).isEmpty)
                .accessibilityIdentifier("triage.tagsApplyButton")
            }

            if !currentTags.isEmpty {
                FlowRow(items: currentTags) { tag in
                    HStack(spacing: 6) {
                        Text("#\(tag)")
                            .font(.caption)
                        Button {
                            removeTag(tag)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(theme.backgroundColor)
                    .clipShape(Capsule())
                }
            }

            if !tagSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tagSuggestions, id: \.self) { tag in
                            Button("#\(tag)") {
                                applyTags(currentTags + [tag])
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            let dueText = dueSummary(for: record.document.frontmatter)
            if !dueText.isEmpty {
                Text("Due: \(dueText)")
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

    private func priorityButton(title: String, priority: TaskPriority, shortcut: KeyEquivalent, current: TaskPriority) -> some View {
        Button(title) {
            guard let currentPath else { return }
            _ = container.setPriority(path: currentPath, priority: priority)
        }
        .keyboardShortcut(shortcut, modifiers: [])
        .buttonStyle(.borderedProminent)
        .tint(current == priority ? theme.accentColor : theme.textSecondaryColor.opacity(0.28))
    }

    private func dueButton(title: String, shortcut: KeyEquivalent, date: Date?) -> some View {
        Button(title) {
            applyDue(date)
        }
        .keyboardShortcut(shortcut, modifiers: [])
        .buttonStyle(.bordered)
    }

    private func syncQueueState() {
        let validPaths = Set(records.map(\.identity.path))
        skippedPaths = skippedPaths.intersection(validPaths)
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
            tagsDraft = ""
            return
        }
        projectDraft = currentRecord.document.frontmatter.project ?? ""
        tagsDraft = ""
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

    private func applyDue(_ date: Date?) {
        guard let currentPath else { return }
        _ = container.setDue(path: currentPath, date: date)
    }

    private func applyProjectDraft() {
        let trimmed = projectDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        applyProject(trimmed)
    }

    private func applyProject(_ project: String) {
        guard let currentPath else { return }
        if container.addToProject(path: currentPath, project: project) {
            projectDraft = ""
            pinnedPath = nil
            focusedField = nil
        }
    }

    private func applyTagsDraft() {
        let additions = normalizedTagTokens(from: tagsDraft)
        guard !additions.isEmpty else { return }
        applyTags(currentTags + additions)
        tagsDraft = ""
        focusedField = nil
    }

    private func applyTags(_ tags: [String]) {
        guard let currentPath else { return }
        _ = container.setTags(path: currentPath, tags: tags)
    }

    private func removeTag(_ tag: String) {
        applyTags(currentTags.filter { $0 != tag })
    }

    private func normalizedTagTokens(from raw: String) -> [String] {
        var seen = Set<String>()
        return raw
            .split(separator: ",")
            .map { token in
                token.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                    .replacingOccurrences(of: "#", with: "")
            }
            .filter { token in
                guard !token.isEmpty, !seen.contains(token) else { return false }
                seen.insert(token)
                return true
            }
    }

    private func metadataSummary(for frontmatter: TaskFrontmatterV1) -> String {
        var parts: [String] = []
        if frontmatter.priority != .none {
            parts.append(frontmatter.priority.rawValue.capitalized)
        }
        let due = dueSummary(for: frontmatter)
        if !due.isEmpty {
            parts.append(due)
        }
        if let project = frontmatter.project?.trimmingCharacters(in: .whitespacesAndNewlines),
           !project.isEmpty {
            parts.append(project)
        }
        parts.append(contentsOf: frontmatter.tags.prefix(3).map { "#\($0)" })
        return parts.joined(separator: "  ·  ")
    }

    private func dueSummary(for frontmatter: TaskFrontmatterV1) -> String {
        guard let due = frontmatter.due else { return "" }
        var components = DateComponents()
        components.year = due.year
        components.month = due.month
        components.day = due.day
        let calendar = Calendar.current
        guard let date = calendar.date(from: components) else { return due.isoString }
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }
}

private struct FlowRow<Content: View, Item: Hashable>: View {
    let items: [Item]
    let content: (Item) -> Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}
