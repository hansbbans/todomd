import SwiftUI

struct QuickEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var theme: ThemeManager
    @AppStorage("settings_quick_entry_default_view") private var quickEntryDefaultView = BuiltInView.inbox.rawValue
    @AppStorage(QuickEntrySettings.fieldsKey) private var quickEntryFieldsRawValue = QuickEntrySettings.defaultFieldsRawValue
    @AppStorage(QuickEntrySettings.defaultDateModeKey) private var quickEntryDefaultDateModeRawValue = QuickEntryDefaultDateMode.today.rawValue

    @State private var quickEntryText = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var hasDueTime = false
    @State private var dueTime = Date()
    @State private var flagged = false
    @State private var priorityOverride: TaskPriority?
    @State private var tagsText = ""
    @State private var selectedArea: String?
    @State private var selectedProject: String?
    @State private var showingDueDateEditor = false
    @State private var showingReminderEditor = false
    @State private var showingTagsEditor = false
    @State private var reminderDraftDate = Date()
    @State private var didApplyDefaults = false

    private var selectedFields: [QuickEntryField] {
        QuickEntrySettings.decodeFields(quickEntryFieldsRawValue)
    }

    private var quickEntryDefaultDateMode: QuickEntryDefaultDateMode {
        QuickEntryDefaultDateMode(rawValue: quickEntryDefaultDateModeRawValue) ?? .today
    }

    private var supportsDueInputs: Bool {
        selectedFields.contains(.dueDate) || selectedFields.contains(.reminder)
    }

    private var canSubmit: Bool {
        !quickEntryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var dateChipTitle: String {
        guard hasDueDate else { return "No Date" }
        let calendar = Calendar.current
        if calendar.isDateInToday(dueDate) {
            return "Today"
        }
        return dueDate.formatted(date: .abbreviated, time: .omitted)
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

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                descriptionField
                configurableFieldsRow
                Spacer(minLength: 0)
                destinationRow
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .navigationTitle("Quick Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("quickEntry.cancelButton")
                }
            }
        }
        .accessibilityIdentifier("quickEntry.form")
        .presentationDetents([.fraction(0.58), .large])
        .onAppear {
            applyInitialDefaultsIfNeeded()
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
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(theme.accentColor)
                    .frame(width: 4, height: 56)

                TextField("Description", text: $quickEntryText)
                    .font(.system(.title2, design: .rounded).weight(.regular))
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .bottomLeading)
                    .accessibilityIdentifier("quickEntry.titleField")
            }
            .accessibilityIdentifier("quickEntry.titleField")
            .padding(18)
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(theme.surfaceColor.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.textSecondaryColor.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var configurableFieldsRow: some View {
        if selectedFields.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(selectedFields, id: \.self) { field in
                        fieldChip(field)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func fieldChip(_ field: QuickEntryField) -> some View {
        switch field {
        case .dueDate:
            Button {
                showingDueDateEditor = true
            } label: {
                chipLabel(
                    title: dateChipTitle,
                    systemImage: field.systemImage,
                    isActive: hasDueDate
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
        Button("Inbox") {
            selectedArea = nil
            selectedProject = nil
        }

        ForEach(container.projectsByArea(), id: \.area) { group in
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
    }

    private var destinationRow: some View {
        HStack(spacing: 12) {
            Menu {
                destinationMenuActions
            } label: {
                Label(destinationLabel, systemImage: "tray")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(theme.textPrimaryColor)
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    // Placeholder button for future voice capture.
                } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(theme.accentColor))
                }
                .disabled(true)
                .opacity(0.7)

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

    private var dueDateEditor: some View {
        NavigationStack {
            Form {
                Toggle("Set due date", isOn: $hasDueDate)

                if hasDueDate {
                    DatePicker(
                        "Due date",
                        selection: $dueDate,
                        displayedComponents: .date
                    )

                    Toggle("Set time", isOn: $hasDueTime)

                    if hasDueTime {
                        DatePicker(
                            "Time",
                            selection: $dueTime,
                            displayedComponents: .hourAndMinute
                        )
                    }

                    Button("Clear Date", role: .destructive) {
                        hasDueDate = false
                        hasDueTime = false
                    }
                }
            }
            .navigationTitle("Date")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showingDueDateEditor = false
                    }
                }
            }
        }
        .onChange(of: hasDueDate) { _, isOn in
            if !isOn {
                hasDueTime = false
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
                    .textInputAutocapitalization(.never)
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

    private func addTask() {
        let trimmedEntry = quickEntryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEntry.isEmpty else { return }

        let defaultView = BuiltInView(rawValue: quickEntryDefaultView)
        let explicitDue = (supportsDueInputs && hasDueDate) ? localDate(from: dueDate) : nil
        let explicitDueTime = (supportsDueInputs && hasDueDate && hasDueTime) ? localTime(from: dueTime) : nil
        let created = container.createTask(
            fromQuickEntryText: trimmedEntry,
            explicitDue: explicitDue,
            explicitDueTime: explicitDueTime,
            priority: selectedFields.contains(.priority) ? priorityOverride : nil,
            flagged: selectedFields.contains(.flag) ? flagged : false,
            tags: selectedFields.contains(.tags) ? parsedTags(from: tagsText) : [],
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
