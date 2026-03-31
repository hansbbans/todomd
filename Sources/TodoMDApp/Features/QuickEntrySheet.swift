import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct QuickEntrySheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var theme: ThemeManager
    @AppStorage("settings_quick_entry_default_view") private var quickEntryDefaultView = BuiltInView.inbox.rawValue
    @AppStorage(QuickEntrySettings.fieldsKey) private var quickEntryFieldsRawValue = QuickEntrySettings.defaultFieldsRawValue
    @AppStorage(QuickEntrySettings.defaultDateModeKey) private var quickEntryDefaultDateModeRawValue = QuickEntryDefaultDateMode.none.rawValue

    @State private var quickEntryText = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var hasDueTime = false
    @State private var dueTime = Date()
    @State private var recurrence = ""
    @State private var flagged = false
    @State private var priorityOverride: TaskPriority?
    @State private var tagsText = ""
    @State private var selectedArea: String?
    @State private var selectedProject: String?
    @State private var hasScheduledDate = false
    @State private var scheduledDate = Date()
    @State private var hasScheduledTime = false
    @State private var scheduledTime = Date()
    @State private var showingScheduledDateEditor = false
    @State private var showingDueDateEditor = false
    @State private var showingReminderEditor = false
    @State private var showingTagsEditor = false
    @State private var showingVoiceRamble = false
    @State private var reminderDraftDate = Date()
    @State private var didApplyDefaults = false
    @State private var showAllFields = false
    @State private var showingDetails = false
    @State private var focusTask: Task<Void, Never>?
    @State private var quickEntryParseTask: Task<Void, Never>?
    @State private var highlightedDatePhrase: String?

    @FocusState private var quickEntryTitleFocused: Bool

    private let descriptionInputHeight: CGFloat = 44

    private var selectedFields: [QuickEntryField] {
        QuickEntrySettings.decodeFields(quickEntryFieldsRawValue)
    }

    private var displayedFields: [QuickEntryField] {
        if showAllFields {
            let extraFields = QuickEntryField.allCases.filter { !selectedFields.contains($0) }
            return selectedFields + extraFields
        }
        return selectedFields
    }

    private var activeFieldSet: Set<QuickEntryField> {
        Set(displayedFields)
    }

    private var quickEntryDefaultDateMode: QuickEntryDefaultDateMode {
        QuickEntryDefaultDateMode(rawValue: quickEntryDefaultDateModeRawValue) ?? .none
    }

    private var supportsDueInputs: Bool {
        activeFieldSet.contains(.dueDate)
            || activeFieldSet.contains(.reminder)
            || hasDueDate
            || hasDueTime
            || quickEntryDefaultDateMode != .none
    }

    private var canSubmit: Bool {
        !quickEntryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var trimmedQuickEntryText: String {
        quickEntryText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasVisibleMetadata: Bool {
        hasDueDate
            || hasDueTime
            || hasScheduledDate
            || hasScheduledTime
            || !recurrence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || flagged
            || priorityOverride != nil
            || !parsedTags(from: tagsText).isEmpty
            || selectedArea != nil
            || selectedProject != nil
    }

    private var shouldShowDetails: Bool {
        showingDetails || (trimmedQuickEntryText.isEmpty && hasVisibleMetadata)
    }

    private var whenChipTitle: String {
        guard hasScheduledDate else { return "When" }
        let calendar = Calendar.current
        var text: String
        if calendar.isDateInToday(scheduledDate) {
            text = "Today"
        } else if calendar.isDateInTomorrow(scheduledDate) {
            text = "Tomorrow"
        } else {
            text = scheduledDate.formatted(date: .abbreviated, time: .omitted)
        }
        if hasScheduledTime {
            let comps = calendar.dateComponents([.hour, .minute], from: scheduledTime)
            if let t = try? LocalTime(isoTime: String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)),
               t >= container.eveningStartTime {
                text += ", Evening"
            }
        }
        return text
    }

    private var deadlineChipTitle: String {
        guard hasDueDate else { return "Deadline" }
        let calendar = Calendar.current
        if calendar.isDateInToday(dueDate) {
            return "Today"
        }
        return dueDate.formatted(date: .abbreviated, time: .omitted)
    }

    private var isDeadlineOverdue: Bool {
        guard hasDueDate else { return false }
        return Calendar.current.startOfDay(for: dueDate) <= Calendar.current.startOfDay(for: Date())
    }

    private var reminderChipTitle: String {
        guard hasDueDate, hasDueTime else { return "Reminders" }
        return dueTime.formatted(date: .omitted, time: .shortened)
    }

    private var priorityChipTitle: String {
        guard let priorityOverride else { return "Priority" }
        return priorityOverride.rawValue.capitalized
    }

    private var tagsChipTitle: String {
        let count = parsedTags(from: tagsText).count
        if count == 0 { return "Tags" }
        if count == 1 {
            return "#\(parsedTags(from: tagsText)[0])"
        }
        return "\(count) Tags"
    }

    private var destinationLabel: String {
        if let project = selectedProject {
            return project
        }
        if let area = selectedArea {
            return area
        }
        return "Inbox"
    }

    private var destinationSymbol: String {
        if selectedProject != nil {
            return "folder"
        }
        if selectedArea != nil {
            return "square.grid.2x2"
        }
        return "tray"
    }

    private var displayedDetailFields: [QuickEntryField] {
        displayedFields.filter { $0 != .project }
    }

    private var detailsAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.2)
    }

    private var detailsTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                descriptionField

                if shouldShowDetails {
                    detailsSection
                        .transition(detailsTransition)
                }

                Spacer(minLength: 0)
                actionRow
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(theme.backgroundColor.ignoresSafeArea())
            .navigationTitle("Quick Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                    .accessibilityIdentifier("quickEntry.cancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addTask()
                    }
                    .disabled(!canSubmit)
                    .accessibilityIdentifier("quickEntry.addButton")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        addTask()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                    }
                    .disabled(!canSubmit)
                    .accessibilityLabel("Add task")
                }
            }
        }
        .accessibilityIdentifier("quickEntry.form")
        .presentationDetents([.fraction(0.58), .large])
        .onAppear {
            applyInitialDefaultsIfNeeded()
            scheduleTitleFocus()
        }
        .onDisappear {
            focusTask?.cancel()
            focusTask = nil
            quickEntryParseTask?.cancel()
            quickEntryParseTask = nil
        }
        .sheet(isPresented: $showingDueDateEditor) {
            dueDateEditor
        }
        .sheet(isPresented: $showingReminderEditor) {
            reminderEditor
        }
        .sheet(isPresented: $showingTagsEditor) {
            tagsEditor
        }
        .sheet(isPresented: $showingVoiceRamble) {
            VoiceRambleSheet(
                fallbackDue: (supportsDueInputs && hasDueDate) ? localDate(from: dueDate) : nil,
                fallbackDueTime: (supportsDueInputs && hasDueDate && hasDueTime) ? localTime(from: dueTime) : nil,
                fallbackPriority: activeFieldSet.contains(.priority) ? priorityOverride : nil,
                fallbackFlagged: activeFieldSet.contains(.flag) ? flagged : false,
                fallbackTags: activeFieldSet.contains(.tags) ? parsedTags(from: tagsText) : [],
                fallbackArea: selectedArea,
                fallbackProject: selectedProject,
                defaultView: BuiltInView(rawValue: quickEntryDefaultView),
                onClose: {
                    showingVoiceRamble = false
                },
                onTasksCreated: {
                    dismiss()
                }
            )
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(theme.accentColor)
                    .frame(width: 4, height: descriptionInputHeight)

                QuickEntryTitleField(
                    placeholder: "New To-Do",
                    text: $quickEntryText,
                    highlightedPhrase: highlightedDatePhrase,
                    isFocused: Binding(
                        get: { quickEntryTitleFocused },
                        set: { quickEntryTitleFocused = $0 }
                    ),
                    textColor: theme.textPrimaryColor,
                    highlightColor: theme.accentColor,
                    onChange: handleQuickEntryTitleChanged,
                    onSubmit: {
                        if canSubmit {
                            addTask()
                        }
                    }
                )
                    .frame(maxWidth: CGFloat.infinity, minHeight: descriptionInputHeight, alignment: Alignment.leading)
            }
            .accessibilityIdentifier("quickEntry.titleField")

            if shouldShowDetails {
                Text("Optional details stay tucked underneath the task.")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondaryColor)
                    .fixedSize(horizontal: false, vertical: true)
            } else if hasVisibleMetadata || !trimmedQuickEntryText.isEmpty {
                collapsedQuickActionsRow
            } else {
                Text("Type the task. Everything else can wait.")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondaryColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            ThingsSurfaceBackdrop(
                kind: .elevatedCard,
                theme: theme,
                colorScheme: colorScheme
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: ThingsSurfaceKind.elevatedCard.cornerRadius, style: .continuous))
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("Optional Details")
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(theme.textSecondaryColor)
                    .textCase(.uppercase)

                Spacer()

                if !hasVisibleMetadata {
                    Button("Keep Simple") {
                        withAnimation(detailsAnimation) {
                            showingDetails = false
                            showAllFields = false
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(theme.textSecondaryColor)
                    .buttonStyle(.plain)
                }
            }

            configurableFieldsRow
            detailDestinationRow
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            ThingsSurfaceBackdrop(
                kind: .elevatedCard,
                theme: theme,
                colorScheme: colorScheme
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: ThingsSurfaceKind.elevatedCard.cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var configurableFieldsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(displayedDetailFields, id: \.self) { field in
                    fieldChip(field)
                }
                showAllFieldsButton
            }
            .padding(.vertical, 2)
        }
    }

    private var showAllFieldsButton: some View {
        Button {
            showAllFields.toggle()
        } label: {
            chipLabel(
                title: showAllFields ? "Fewer" : "More",
                systemImage: "slider.horizontal.3",
                isActive: showAllFields
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("quickEntry.showAllFieldsButton")
        .accessibilityLabel(showAllFields ? "Show fewer details" : "Show more details")
    }

    @ViewBuilder
    private func fieldChip(_ field: QuickEntryField) -> some View {
        switch field {
        case .scheduledDate:
            Button {
                showingScheduledDateEditor = true
            } label: {
                chipLabel(
                    title: whenChipTitle,
                    systemImage: field.systemImage,
                    isActive: hasScheduledDate
                )
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingScheduledDateEditor) {
                whenDateEditorView
            }
        case .dueDate:
            Button {
                showingDueDateEditor = true
            } label: {
                chipLabelDeadline(
                    title: deadlineChipTitle,
                    isActive: hasDueDate,
                    isOverdue: isDeadlineOverdue
                )
            }
            .buttonStyle(.plain)
        case .priority:
            Menu {
                Button("Use default") {
                    priorityOverride = nil
                }
                Divider()
                ForEach(TaskPriority.allCases, id: \.rawValue) { priority in
                    Button(priority.rawValue.capitalized) {
                        priorityOverride = priority
                    }
                }
            } label: {
                chipLabel(
                    title: priorityChipTitle,
                    systemImage: field.systemImage,
                    isActive: priorityOverride != nil
                )
            }
            .menuStyle(.button)
        case .reminder:
            Button {
                prepareReminderDraft()
                showingReminderEditor = true
            } label: {
                chipLabel(
                    title: reminderChipTitle,
                    systemImage: field.systemImage,
                    isActive: hasDueDate && hasDueTime
                )
            }
            .buttonStyle(.plain)
        case .flag:
            Button {
                flagged.toggle()
            } label: {
                chipLabel(
                    title: "Flag",
                    systemImage: field.systemImage,
                    isActive: flagged
                )
            }
            .buttonStyle(.plain)
        case .tags:
            Button {
                showingTagsEditor = true
            } label: {
                chipLabel(
                    title: tagsChipTitle,
                    systemImage: field.systemImage,
                    isActive: !parsedTags(from: tagsText).isEmpty
                )
            }
            .buttonStyle(.plain)
        case .project:
            Menu {
                destinationMenuActions
            } label: {
                chipLabel(
                    title: destinationLabel,
                    systemImage: field.systemImage,
                    isActive: selectedArea != nil || selectedProject != nil
                )
            }
        }
    }

    @ViewBuilder
    private var destinationMenuActions: some View {
        let pickerContent = container.projectPickerContent()
        let groupedAreas = pickerContent.groupedAreas
        let ungroupedProjects = pickerContent.ungroupedProjects

        Button("Inbox") {
            selectedArea = nil
            selectedProject = nil
        }

        if groupedAreas.isEmpty {
            ForEach(pickerContent.allProjects, id: \.self) { project in
                Button(project) {
                    selectedArea = nil
                    selectedProject = project
                }
            }
        } else {
            ForEach(groupedAreas, id: \.area) { group in
                Menu(group.area) {
                    Button("Area Only") {
                        selectedArea = group.area
                        selectedProject = nil
                    }
                    ForEach(group.projects, id: \.self) { project in
                        Button(project) {
                            selectedArea = group.area
                            selectedProject = project
                        }
                    }
                }
            }

            if !ungroupedProjects.isEmpty {
                Menu("No Area") {
                    ForEach(ungroupedProjects, id: \.self) { project in
                        Button(project) {
                            selectedArea = nil
                            selectedProject = project
                        }
                    }
                }
            }
        }
    }

    private var detailDestinationRow: some View {
        HStack(spacing: 12) {
            Text("Save To")
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(theme.textSecondaryColor)

            Spacer()

            Menu {
                destinationMenuActions
            } label: {
                Label(destinationLabel, systemImage: "tray")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(theme.textPrimaryColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(theme.surfaceColor.opacity(0.94))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(theme.textSecondaryColor.opacity(0.24), lineWidth: 1)
                    )
            }
        }
    }

    private var collapsedQuickActionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button {
                    showingDueDateEditor = true
                } label: {
                    chipLabelDeadline(
                        title: deadlineChipTitle,
                        isActive: hasDueDate,
                        isOverdue: isDeadlineOverdue
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("quickEntry.quickDateButton")

                Menu {
                    destinationMenuActions
                } label: {
                    chipLabel(
                        title: destinationLabel,
                        systemImage: destinationSymbol,
                        isActive: selectedArea != nil || selectedProject != nil
                    )
                }
                .accessibilityIdentifier("quickEntry.quickDestinationButton")

                Button {
                    withAnimation(detailsAnimation) {
                        showingDetails = true
                    }
                } label: {
                    chipLabel(
                        title: "More",
                        systemImage: "slider.horizontal.3",
                        isActive: false
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("quickEntry.revealDetailsButton")
            }
            .padding(.vertical, 2)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Spacer()

            HStack(spacing: 10) {
                Button {
                    showingVoiceRamble = true
                } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(theme.accentColor))
                }
                .accessibilityIdentifier("quickEntry.voiceRambleButton")
                .accessibilityLabel("Voice ramble")

                Button {
                    addTask()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(
                            Circle()
                                .fill(canSubmit ? theme.accentColor : theme.textSecondaryColor.opacity(0.5))
                        )
                }
                .disabled(!canSubmit)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityIdentifier("quickEntry.addButton")
                .accessibilityLabel("Add task")
            }
        }
    }

    private func chipLabel(title: String, systemImage: String, isActive: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(isActive ? theme.accentColor : theme.textPrimaryColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(theme.surfaceColor.opacity(0.94))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(isActive ? theme.accentColor.opacity(0.45) : theme.textSecondaryColor.opacity(0.32), lineWidth: 1)
        )
    }

    private func chipLabelDeadline(title: String, isActive: Bool, isOverdue: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "diamond.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isActive ? (isOverdue ? Color.red : Color.orange) : theme.textPrimaryColor)
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(isActive ? (isOverdue ? Color.red : Color.orange) : theme.textPrimaryColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(theme.surfaceColor.opacity(0.94))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(isActive ? (isOverdue ? Color.red.opacity(0.45) : Color.orange.opacity(0.45)) : theme.textSecondaryColor.opacity(0.32), lineWidth: 1)
        )
    }

    private var whenDateEditorView: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 0) {
                        Button("Today") {
                            hasScheduledDate = true
                            scheduledDate = Date()
                            hasScheduledTime = false
                            showingScheduledDateEditor = false
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        Divider()
                        Button("This Evening") {
                            hasScheduledDate = true
                            scheduledDate = Date()
                            hasScheduledTime = true
                            scheduledTime = container.eveningStartDate
                            showingScheduledDateEditor = false
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        Divider()
                        Button("Tomorrow") {
                            hasScheduledDate = true
                            scheduledDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                            hasScheduledTime = false
                            showingScheduledDateEditor = false
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        if hasScheduledDate {
                            Divider()
                            Button("Clear") {
                                hasScheduledDate = false
                                hasScheduledTime = false
                                showingScheduledDateEditor = false
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .foregroundStyle(.red)
                        }
                    }
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)

                    DatePicker("Date", selection: $scheduledDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .onChange(of: scheduledDate) { _, _ in hasScheduledDate = true }
                        .padding(.horizontal)

                    if hasScheduledDate {
                        HStack(spacing: 12) {
                            Button("Morning") {
                                hasScheduledTime = false
                            }
                            .buttonStyle(.bordered)
                            .tint(hasScheduledTime ? .secondary : .accentColor)

                            Button("Evening") {
                                hasScheduledTime = true
                                scheduledTime = container.eveningStartDate
                            }
                            .buttonStyle(.bordered)
                            .tint(hasScheduledTime ? .accentColor : .secondary)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("When")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingScheduledDateEditor = false }
                }
            }
        }
    }

    private var dueDateEditor: some View {
        NavigationStack {
            ScrollView {
                DateChooserView(
                    context: .due,
                    timeMode: .optional,
                    hasDate: $hasDueDate,
                    date: $dueDate,
                    hasTime: $hasDueTime,
                    time: $dueTime,
                    recurrence: $recurrence
                )
                .padding(16)
            }
            .navigationTitle("Date")
            .background(theme.backgroundColor.ignoresSafeArea())
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showingDueDateEditor = false
                    }
                }
            }
        }
    }

    private var reminderEditor: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "Reminder",
                    selection: $reminderDraftDate,
                    displayedComponents: [.date, .hourAndMinute]
                )

                Button("Clear Reminder", role: .destructive) {
                    hasDueTime = false
                    showingReminderEditor = false
                }
            }
            .navigationTitle("Reminders")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingReminderEditor = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        hasDueDate = true
                        hasDueTime = true
                        dueDate = reminderDraftDate
                        dueTime = reminderDraftDate
                        showingReminderEditor = false
                    }
                }
            }
        }
    }

    private var tagsEditor: some View {
        NavigationStack {
            Form {
                TextField("work, finance, errands", text: $tagsText)
                    .modifier(QuickEntryAutocapitalization(sentences: false))
                    .autocorrectionDisabled(true)
                Text("Use commas or spaces. #prefix is optional.")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondaryColor)
            }
            .navigationTitle("Tags")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showingTagsEditor = false
                    }
                }
            }
        }
    }

    private func applyInitialDefaultsIfNeeded() {
        guard !didApplyDefaults else { return }
        didApplyDefaults = true
        if selectedProject == nil,
           let inferredProject = container.inferredTaskProject(for: container.selectedView) {
            selectedProject = inferredProject
        }
        if supportsDueInputs {
            switch quickEntryDefaultDateMode {
            case .today:
                hasDueDate = true
                dueDate = Date()
            case .none:
                hasDueDate = false
            }
        } else {
            hasDueDate = false
        }
        hasDueTime = false
        showingDetails = hasVisibleMetadata
    }

    private func scheduleTitleFocus() {
        focusTask?.cancel()
        focusTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }
            quickEntryTitleFocused = true
            focusTask = nil
        }
    }

    private func prepareReminderDraft() {
        guard hasDueDate else {
            reminderDraftDate = Date()
            return
        }

        var components = Calendar.current.dateComponents([.year, .month, .day], from: dueDate)
        let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: hasDueTime ? dueTime : Date())
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        reminderDraftDate = Calendar.current.date(from: components) ?? Date()
    }

    private func handleQuickEntryTitleChanged(_ value: String) {
        quickEntryParseTask?.cancel()

        let capturedValue = value
        let availableProjects = container.allProjects()
        quickEntryParseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled,
                  quickEntryText == capturedValue else {
                return
            }

            let trimmedValue = capturedValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedValue.isEmpty else {
                highlightedDatePhrase = nil
                quickEntryParseTask = nil
                return
            }

            let parser = NaturalLanguageTaskParser(availableProjects: availableProjects)
            let parsed = parser.parse(trimmedValue)
            highlightedDatePhrase = parsed?.recognizedDatePhrase
            quickEntryParseTask = nil
        }
    }

    private func addTask() {
        let trimmedEntry = quickEntryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEntry.isEmpty else { return }

        let defaultView = BuiltInView(rawValue: quickEntryDefaultView)
        let explicitDue = (supportsDueInputs && hasDueDate) ? localDate(from: dueDate) : nil
        let explicitDueTime = (supportsDueInputs && hasDueDate && hasDueTime) ? localTime(from: dueTime) : nil
        let explicitRecurrence: String? = {
            let trimmed = recurrence.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()
        let explicitScheduled = hasScheduledDate ? localDate(from: scheduledDate) : nil
        let explicitScheduledTime = (hasScheduledDate && hasScheduledTime) ? localTime(from: scheduledTime) : nil
        let activeFields = activeFieldSet
        let created = container.createTask(
            fromQuickEntryText: trimmedEntry,
            explicitDue: explicitDue,
            explicitDueTime: explicitDueTime,
            explicitRecurrence: explicitRecurrence,
            explicitScheduled: explicitScheduled,
            explicitScheduledTime: explicitScheduledTime,
            priority: activeFields.contains(.priority) ? priorityOverride : nil,
            flagged: activeFields.contains(.flag) ? flagged : false,
            tags: activeFields.contains(.tags) ? parsedTags(from: tagsText) : [],
            area: selectedArea,
            project: selectedProject,
            defaultView: defaultView
        )
        guard created else { return }
#if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
        dismiss()
    }

    private func localDate(from date: Date) -> LocalDate {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (try? LocalDate(
            year: components.year ?? 1970,
            month: components.month ?? 1,
            day: components.day ?? 1
        )) ?? .epoch
    }

    private func localTime(from date: Date) -> LocalTime {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (try? LocalTime(
            hour: components.hour ?? 0,
            minute: components.minute ?? 0
        )) ?? .midnight
    }

    private func parsedTags(from raw: String) -> [String] {
        var seen = Set<String>()
        let delimiters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))
        let tokens = raw
            .split(whereSeparator: { scalar in
                scalar.unicodeScalars.contains { delimiters.contains($0) }
            })
            .map { token in
                let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("#") {
                    return String(trimmed.dropFirst())
                }
                return trimmed
            }
            .filter { !$0.isEmpty }

        return tokens.compactMap { token in
            let normalized = token.lowercased()
            guard !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return normalized
        }
    }
}

enum QuickEntryTextHighlighter {
    static func highlightedRange(in text: String, phrase: String?) -> Range<String.Index>? {
        let trimmedPhrase = phrase?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedPhrase.isEmpty else { return nil }
        return text.range(
            of: trimmedPhrase,
            options: [.caseInsensitive, .backwards, .diacriticInsensitive]
        )
    }

#if canImport(UIKit) || canImport(AppKit)
    fileprivate static func attributedText(
        for text: String,
        phrase: String?,
        font: QuickEntryPlatformFont,
        textColor: QuickEntryPlatformColor,
        highlightColor: QuickEntryPlatformColor
    ) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: textColor
            ]
        )

        if let range = highlightedRange(in: text, phrase: phrase) {
            attributed.addAttributes(
                [
                    .foregroundColor: highlightedTextColor,
                    .backgroundColor: highlightColor.withAlphaComponent(0.6)
                ],
                range: NSRange(range, in: text)
            )
        }

        return attributed
    }

    private static var highlightedTextColor: QuickEntryPlatformColor {
        #if canImport(UIKit)
        .white
        #elseif canImport(AppKit)
        .white
        #endif
    }
#endif
}

#if canImport(UIKit)
typealias QuickEntryPlatformColor = UIColor
typealias QuickEntryPlatformFont = UIFont
#elseif canImport(AppKit)
typealias QuickEntryPlatformColor = NSColor
typealias QuickEntryPlatformFont = NSFont
#endif

#if canImport(UIKit)
private struct QuickEntryTitleField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let highlightedPhrase: String?
    let isFocused: Binding<Bool>
    let textColor: Color
    let highlightColor: Color
    let onChange: (String) -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.adjustsFontForContentSizeCategory = true
        textField.autocorrectionType = .yes
        textField.autocapitalizationType = .sentences
        textField.returnKeyType = .done
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.accessibilityIdentifier = "quickEntry.titleField"
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        applyAppearance(to: textField, coordinator: context.coordinator)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        applyAppearance(to: uiView, coordinator: context.coordinator)

        if context.coordinator.lastRenderedText != text
            || context.coordinator.lastHighlightedPhrase != highlightedPhrase
            || context.coordinator.lastTextColor != UIColor(textColor)
            || context.coordinator.lastHighlightColor != UIColor(highlightColor) {
            let selection = context.coordinator.selectionOffsets(in: uiView)
            context.coordinator.isApplyingUpdate = true
            uiView.attributedText = attributedText()
            context.coordinator.isApplyingUpdate = false
            context.coordinator.restoreSelection(selection, in: uiView)
            context.coordinator.lastRenderedText = text
            context.coordinator.lastHighlightedPhrase = highlightedPhrase
            context.coordinator.lastTextColor = UIColor(textColor)
            context.coordinator.lastHighlightColor = UIColor(highlightColor)
        }

        if isFocused.wrappedValue, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFocused.wrappedValue, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    private func applyAppearance(to textField: UITextField, coordinator: Coordinator) {
        let font = roundedTitleFont()
        textField.font = font
        textField.textColor = UIColor(textColor)
        textField.tintColor = UIColor(textColor)
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .font: font,
                .foregroundColor: UIColor(textColor).withAlphaComponent(0.45)
            ]
        )
        if coordinator.lastRenderedText.isEmpty && text.isEmpty {
            textField.attributedText = attributedText()
        }
    }

    private func attributedText() -> NSAttributedString {
        QuickEntryTextHighlighter.attributedText(
            for: text,
            phrase: highlightedPhrase,
            font: roundedTitleFont(),
            textColor: UIColor(textColor),
            highlightColor: UIColor(highlightColor)
        )
    }

    private func roundedTitleFont() -> UIFont {
        let textStyle = UIFont.TextStyle.title2
        let baseFont = UIFont.preferredFont(forTextStyle: textStyle)
        let descriptor = baseFont.fontDescriptor.withDesign(.rounded) ?? baseFont.fontDescriptor
        let rounded = UIFont(descriptor: descriptor, size: 0)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: rounded)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: QuickEntryTitleField
        var isApplyingUpdate = false
        var lastRenderedText = ""
        var lastHighlightedPhrase: String?
        var lastTextColor: UIColor?
        var lastHighlightColor: UIColor?

        init(parent: QuickEntryTitleField) {
            self.parent = parent
        }

        @objc func textDidChange(_ textField: UITextField) {
            guard !isApplyingUpdate else { return }
            let newValue = textField.text ?? ""
            parent.text = newValue
            parent.onChange(newValue)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.isFocused.wrappedValue = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.isFocused.wrappedValue = false
        }

        func selectionOffsets(in textField: UITextField) -> (start: Int, end: Int)? {
            guard let start = textField.selectedTextRange?.start,
                  let end = textField.selectedTextRange?.end else {
                return nil
            }
            return (
                textField.offset(from: textField.beginningOfDocument, to: start),
                textField.offset(from: textField.beginningOfDocument, to: end)
            )
        }

        func restoreSelection(_ offsets: (start: Int, end: Int)?, in textField: UITextField) {
            guard let offsets else { return }
            let textLength = textField.text?.utf16.count ?? 0
            let startOffset = max(0, min(offsets.start, textLength))
            let endOffset = max(startOffset, min(offsets.end, textLength))
            guard let start = textField.position(from: textField.beginningOfDocument, offset: startOffset),
                  let end = textField.position(from: textField.beginningOfDocument, offset: endOffset) else {
                return
            }
            textField.selectedTextRange = textField.textRange(from: start, to: end)
        }
    }
}
#elseif canImport(AppKit)
private struct QuickEntryTitleField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let highlightedPhrase: String?
    let isFocused: Binding<Bool>
    let textColor: Color
    let highlightColor: Color
    let onChange: (String) -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(string: text)
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.isBezeled = false
        textField.font = roundedTitleFont()
        textField.delegate = context.coordinator
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.usesSingleLineMode = true
        textField.cell?.wraps = false
        applyAppearance(to: textField)
        updateAttributedText(for: textField)
        if context.coordinator.lastRenderedText.isEmpty && text.isEmpty {
            textField.attributedStringValue = attributedText()
        }
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self
        applyAppearance(to: textField)
        let textColor = NSColor(self.textColor)
        let highlightColor = NSColor(self.highlightColor)
        let shouldRefreshText = textField.stringValue != text
            || context.coordinator.lastRenderedText != text
            || context.coordinator.lastHighlightedPhrase != highlightedPhrase
            || context.coordinator.lastTextColor?.isEqual(textColor) != true
            || context.coordinator.lastHighlightColor?.isEqual(highlightColor) != true
        if shouldRefreshText {
            let selection = context.coordinator.selectionRange(in: textField)
            context.coordinator.isApplyingUpdate = true
            updateAttributedText(for: textField)
            context.coordinator.restoreSelection(selection, in: textField)
            context.coordinator.isApplyingUpdate = false
            context.coordinator.lastRenderedText = text
            context.coordinator.lastHighlightedPhrase = highlightedPhrase
            context.coordinator.lastTextColor = textColor
            context.coordinator.lastHighlightColor = highlightColor
        }

        if isFocused.wrappedValue {
            if textField.window?.firstResponder !== textField.currentEditor() {
                textField.window?.makeFirstResponder(textField)
            }
        } else if textField.window?.firstResponder === textField.currentEditor() {
            textField.window?.makeFirstResponder(nil)
        }
    }

    private func applyAppearance(to textField: NSTextField) {
        let font = roundedTitleFont()
        let platformTextColor = NSColor(textColor)
        textField.font = font
        textField.textColor = platformTextColor
        textField.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .font: font,
                .foregroundColor: platformTextColor.withAlphaComponent(0.45)
            ]
        )
    }

    private func updateAttributedText(for textField: NSTextField) {
        let attributed = attributedText()
        textField.attributedStringValue = attributed
        if let editor = textField.currentEditor() as? NSTextView {
            editor.textStorage?.setAttributedString(attributed)
            editor.insertionPointColor = NSColor(textColor)
        }
    }

    private func attributedText() -> NSAttributedString {
        QuickEntryTextHighlighter.attributedText(
            for: text,
            phrase: highlightedPhrase,
            font: roundedTitleFont(),
            textColor: NSColor(textColor),
            highlightColor: NSColor(highlightColor)
        )
    }

    private func roundedTitleFont() -> NSFont {
        let textStyle = NSFont.TextStyle.title2
        let baseFont = NSFont.preferredFont(forTextStyle: textStyle)
        let descriptor = baseFont.fontDescriptor.withDesign(.rounded) ?? baseFont.fontDescriptor
        return NSFont(descriptor: descriptor, size: 0) ?? baseFont
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: QuickEntryTitleField
        var isApplyingUpdate = false
        var lastRenderedText = ""
        var lastHighlightedPhrase: String?
        var lastTextColor: NSColor?
        var lastHighlightColor: NSColor?

        init(parent: QuickEntryTitleField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard !isApplyingUpdate,
                  let textField = notification.object as? NSTextField else { return }
            let newValue = textField.stringValue
            parent.text = newValue
            parent.onChange(newValue)
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.isFocused.wrappedValue = true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isFocused.wrappedValue = false
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }

        @MainActor
        func selectionRange(in textField: NSTextField) -> NSRange? {
            textField.currentEditor()?.selectedRange
        }

        @MainActor
        func restoreSelection(_ range: NSRange?, in textField: NSTextField) {
            guard let range,
                  let editor = textField.currentEditor() else { return }
            let textLength = textField.stringValue.utf16.count
            let location = max(0, min(range.location, textLength))
            let maxLength = max(0, textLength - location)
            editor.selectedRange = NSRange(location: location, length: min(range.length, maxLength))
        }
    }
}
#else
private struct QuickEntryTitleField: View {
    let placeholder: String
    @Binding var text: String
    let highlightedPhrase: String?
    let isFocused: Binding<Bool>
    let textColor: Color
    let highlightColor: Color
    let onChange: (String) -> Void
    let onSubmit: () -> Void

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.system(.title2, design: .rounded).weight(.regular))
            .modifier(QuickEntryAutocapitalization(sentences: true))
            .autocorrectionDisabled(false)
            .onChange(of: text) { _, newValue in
                onChange(newValue)
            }
            .onSubmit(onSubmit)
            .accessibilityIdentifier("quickEntry.titleField")
    }
}
#endif

private struct QuickEntryAutocapitalization: ViewModifier {
    let sentences: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        content.textInputAutocapitalization(sentences ? .sentences : .never)
        #else
        content
        #endif
    }
}
