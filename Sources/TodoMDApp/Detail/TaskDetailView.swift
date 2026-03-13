import SwiftUI

private enum RecurrenceFrequencyOption: String, CaseIterable {
    case none
    case daily
    case weekly
    case monthly
    case yearly

    var rruleValue: String? {
        switch self {
        case .none:
            nil
        case .daily:
            "DAILY"
        case .weekly:
            "WEEKLY"
        case .monthly:
            "MONTHLY"
        case .yearly:
            "YEARLY"
        }
    }
}

private enum ExpandedRow: Equatable {
    case due
    case scheduled
    case tags
    case estimate
    case assignee
    case blockedBy
}

struct TaskDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var theme: ThemeManager

    let path: String

    @State private var editState: TaskEditState?
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?
    @State private var showNotesEditor = false
    @State private var pendingProjectPersistenceTask: Task<Void, Never>?
    @State private var newTagText = ""
    @State private var locationPresetName = ""
    @State private var selectedLocationFavoriteID = ""

    @State private var recurrenceFrequency: RecurrenceFrequencyOption = .none
    @State private var recurrenceInterval = 1
    @State private var recurrenceWeekdays: Set<String> = []
    @State private var showingRepeatPresetMenu = false
    @State private var showingDueDateEditor = false
    @State private var showingScheduledDateEditor = false
    @State private var expandedRow: ExpandedRow?

    @AppStorage("taskDetail.expandedDependencies") private var expandedDependencies = false
    @AppStorage("taskDetail.expandedMetadata") private var expandedMetadata = false
    @State private var expandedLocationReminder = false
    @State private var showingCustomRepeatEditor = false

    @State private var latitudeError: String?
    @State private var longitudeError: String?
    @State private var titleError: String?

    private let recurrenceWeekdayOptions = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

    var body: some View {
        Group {
            if editState != nil {
                unifiedView
            } else {
                ContentUnavailableView("Task not found", systemImage: "doc.questionmark")
            }
        }
        .navigationTitle("Task")
        .modifier(TaskDetailInlineTitleDisplay())
        .toolbar {
            ToolbarItem(placement: .appTrailingAction) {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .onAppear {
            editState = container.makeEditState(path: path)
            syncRecurrenceBuilderFromEditState()
            if let editState {
                locationPresetName = editState.locationName
            }
            syncSelectedLocationFavorite()
        }
        .onDisappear {
            pendingProjectPersistenceTask?.cancel()
            autoSave()
        }
        .onChange(of: container.locationFavorites.map(\.id), initial: false) { _, _ in
            syncSelectedLocationFavorite()
        }
        .modifier(TaskDetailNotesPresentation(isPresented: $showNotesEditor) {
            notesEditorView
        })
        .sheet(isPresented: $expandedLocationReminder) {
            locationEditorView
        }
        .sheet(isPresented: $showingCustomRepeatEditor) {
            customRepeatView
        }
        .alert(
            "Delete Task",
            isPresented: $showDeleteConfirmation,
            actions: {
                Button("Delete", role: .destructive) {
                    if container.deleteTask(path: path) {
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            },
            message: {
                Text("This permanently deletes the task file.")
            }
        )
        .alert(
            "Save Failed",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
            actions: { Button("OK", role: .cancel) { errorMessage = nil } },
            message: { Text(errorMessage ?? "") }
        )
        .confirmationDialog(
            "Repeating Task",
            isPresented: $showingRepeatPresetMenu,
            titleVisibility: .visible
        ) {
            let anchorDate = recurrenceAnchorDate()
            Button("Every day") {
                applyRecurrencePreset(rule: "FREQ=DAILY")
            }
            Button("Every week on \(weekdayShortText(for: anchorDate))") {
                applyRecurrencePreset(rule: "FREQ=WEEKLY;BYDAY=\(weekdayToken(for: anchorDate))")
            }
            Button("Every weekday (Mon - Fri)") {
                applyRecurrencePreset(rule: "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR")
            }
            Button("Every month on the \(ordinal(dayOfMonth(from: anchorDate)))") {
                applyRecurrencePreset(rule: "FREQ=MONTHLY")
            }
            Button("Every year on \(monthDayText(for: anchorDate))") {
                applyRecurrencePreset(rule: "FREQ=YEARLY")
            }
            Button("Custom") {
                syncRecurrenceBuilderFromEditState()
                showingCustomRepeatEditor = true
            }
            if !(editState?.recurrence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                Button("Never", role: .destructive) {
                    clearRecurrence()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                guard var s = editState else { return }
                s.status = s.status == .done ? .todo : .done
                editState = s
            } label: {
                Image(systemName: editState?.status == .done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(editState?.status == .done ? theme.accentColor : theme.textSecondaryColor)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                TextField("Title", text: binding(\.title), axis: .vertical)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(theme.textPrimaryColor)

                if let ref = editState?.ref, !ref.isEmpty {
                    Text(ref)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondaryColor)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var notesSection: some View {
        ZStack(alignment: .topLeading) {
            if editState?.body.isEmpty ?? true {
                Text("Add notes...")
                    .font(.body)
                    .foregroundStyle(theme.textSecondaryColor)
                    .padding(.top, 8)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
            }
            TextEditor(text: binding(\.body))
                .font(.body)
                .foregroundStyle(theme.textPrimaryColor)
                .frame(minHeight: 72)
                .scrollContentBackground(.hidden)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var corePropertiesSection: some View {
        VStack(spacing: 0) {
            // Status
            Button(action: cycleStatus) {
                HStack(spacing: 12) {
                    Image(systemName: "circle.badge.checkmark")
                        .frame(width: 20)
                        .foregroundStyle(.secondary)
                    Text("Status")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(editState?.status.rawValue.capitalized ?? "—")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 52)

            // Priority
            Button(action: cyclePriority) {
                HStack(spacing: 12) {
                    Image(systemName: "flag")
                        .frame(width: 20)
                        .foregroundStyle(.secondary)
                    Text("Priority")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(editState?.priority == TaskPriority
                        .none ? "—" : (editState?.priority.rawValue.capitalized ?? "—"))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 52)

            // Flag
            Button {
                guard var s = editState else { return }
                s.flagged.toggle()
                editState = s
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: editState?.flagged == true ? "star.fill" : "star")
                        .frame(width: 20)
                        .foregroundStyle(editState?.flagged == true ? .yellow : .secondary)
                    Text("Flagged")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(editState?.flagged == true ? "Yes" : "—")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 52)

            // Due
            Button {
                showingDueDateEditor = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .frame(width: 20)
                        .foregroundStyle(.secondary)
                    Text("Due")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(editState.map { dueDateText($0) } ?? "")
                        .foregroundStyle((editState.map { dueDateText($0) } ?? "").isEmpty ? .tertiary : .secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .taskDetailAccessibilityIdentifier("taskDetail.row.due")
            .sheet(isPresented: $showingDueDateEditor) {
                dueDateEditorSheet
            }
            Divider().padding(.leading, 52)

            // Scheduled
            Button {
                showingScheduledDateEditor = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .frame(width: 20)
                        .foregroundStyle(.secondary)
                    Text("Scheduled")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(editState.map { scheduledDateText($0) } ?? "")
                        .foregroundStyle((editState.map { scheduledDateText($0) } ?? "").isEmpty ? .tertiary : .secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .taskDetailAccessibilityIdentifier("taskDetail.row.scheduled")
            .sheet(isPresented: $showingScheduledDateEditor) {
                scheduledDateEditorSheet
            }

            // Repeat
            Divider().padding(.leading, 52)
            Button {
                showingRepeatPresetMenu = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 20)
                        .foregroundStyle(.secondary)
                    Text("Repeat")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(editState?.recurrence.isEmpty == false ? recurrenceSummaryText() : "—")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 52)

            // Tags
            PropertyRow(
                icon: "tag",
                label: "Tags",
                valueText: editState?.tagsText ?? "",
                isExpanded: expandedRow == .tags,
                onTap: { expandedRow = expandedRow == .tags ? nil : .tags }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    let tags = (editState?.tagsText ?? "").split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    if !tags.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                HStack(spacing: 4) {
                                    Text(tag).font(.caption)
                                    Button { removeTag(tag) } label: {
                                        Image(systemName: "xmark").font(.caption2)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(theme.surfaceColor)
                                .clipShape(Capsule())
                            }
                        }
                    }
                    HStack {
                        TextField("Add tag", text: $newTagText)
                            .onSubmit { addTag() }
                        Button("Add", action: addTag)
                            .disabled(newTagText.isEmpty)
                    }
                }
            }
        }
    }

    private var moreDetailsSection: some View {
        DisclosureGroup(isExpanded: $expandedMetadata) {
            VStack(spacing: 0) {
                // Assignee
                PropertyRow(
                    icon: "person",
                    label: "Assignee",
                    valueText: editState?.assignee ?? "",
                    isExpanded: expandedRow == .assignee,
                    onTap: { expandedRow = expandedRow == .assignee ? nil : .assignee }
                ) {
                    TextField("Assignee", text: binding(\.assignee))
                        .textFieldStyle(.roundedBorder)
                }

                // Blocked by
                PropertyRow(
                    icon: "link",
                    label: "Blocked by",
                    valueText: editState?.blockedByRefsText ?? "",
                    isExpanded: expandedRow == .blockedBy,
                    onTap: { expandedRow = expandedRow == .blockedBy ? nil : .blockedBy }
                ) {
                    TextField("Refs (comma-separated)", text: binding(\.blockedByRefsText))
                        .textFieldStyle(.roundedBorder)
                }

                // Project — always-expanded inline text field
                PropertyRow(
                    icon: "folder",
                    label: "Project",
                    valueText: editState?.project ?? "",
                    isExpanded: true,
                    onTap: {}
                ) {
                    TextField("Project", text: projectBinding)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("taskDetail.field.project")
                }

                // Estimate
                PropertyRow(
                    icon: "timer",
                    label: "Estimate",
                    valueText: editState?.hasEstimatedMinutes == true ? "\(editState!.estimatedMinutes) min" : "",
                    isExpanded: expandedRow == .estimate,
                    onTap: { expandedRow = expandedRow == .estimate ? nil : .estimate }
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Set estimate", isOn: binding(\.hasEstimatedMinutes))
                        if editState?.hasEstimatedMinutes == true {
                            Stepper(
                                "\(editState?.estimatedMinutes ?? 15) minutes",
                                value: binding(\.estimatedMinutes),
                                in: 5 ... 480,
                                step: 5
                            )
                        }
                    }
                }

                // Location
                Button {
                    expandedLocationReminder = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "location")
                            .frame(width: 20)
                            .foregroundStyle(.secondary)
                        Text("Location")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(editState?.hasLocationReminder == true ? locationSummary() : "—")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 52)

                // Read-only metadata
                if let s = editState {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle")
                            .frame(width: 20)
                            .foregroundStyle(.secondary)
                        Text("Created")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(s.createdAt, style: .date)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    Divider().padding(.leading, 52)

                    if let modified = s.modifiedAt {
                        HStack(spacing: 12) {
                            Image(systemName: "pencil.circle")
                                .frame(width: 20)
                                .foregroundStyle(.secondary)
                            Text("Updated")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(modified, style: .date)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        Divider().padding(.leading, 52)
                    }
                }
            }
        } label: {
            Text("More details")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.textSecondaryColor)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
    }

    private var unifiedView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                Divider()
                notesSection
                Divider()
                corePropertiesSection
                moreDetailsSection
            }
            .padding(.bottom, 40)
        }
        .background(theme.backgroundColor.ignoresSafeArea())
    }

    private var dueDateEditorSheet: some View {
        NavigationStack {
            ScrollView {
                DateChooserView(
                    context: .due,
                    timeMode: .optional,
                    hasDate: binding(\.hasDue),
                    date: binding(\.dueDate),
                    hasTime: binding(\.hasDueTime),
                    time: binding(\.dueTime)
                )
                .padding(16)
            }
            .navigationTitle("Due")
            .background(theme.backgroundColor.ignoresSafeArea())
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingDueDateEditor = false }
                }
            }
        }
    }

    private var scheduledDateEditorSheet: some View {
        NavigationStack {
            ScrollView {
                DateChooserView(
                    context: .scheduled,
                    timeMode: .hidden,
                    hasDate: binding(\.hasScheduled),
                    date: binding(\.scheduledDate),
                    hasTime: constantFalseBinding,
                    time: constantDateBinding
                )
                .padding(16)
            }
            .navigationTitle("Scheduled")
            .background(theme.backgroundColor.ignoresSafeArea())
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

    private var notesEditorView: some View {
        NavigationStack {
            TextEditor(text: binding(\.body))
                .padding(12)
                .background(theme.backgroundColor.ignoresSafeArea())
                .navigationTitle("Notes")
                .toolbar {
                    ToolbarItem(placement: .appTrailingAction) {
                        Button("Done") { showNotesEditor = false }
                    }
                }
        }
    }

    private var customRepeatView: some View {
        NavigationStack {
            Form {
                Section("Pattern") {
                    Picker("Frequency", selection: $recurrenceFrequency) {
                        ForEach(RecurrenceFrequencyOption.allCases, id: \.self) { option in
                            Text(option.rawValue.capitalized).tag(option)
                        }
                    }

                    if recurrenceFrequency != .none {
                        Stepper(
                            "Every \(recurrenceInterval) \(recurrenceUnitText())",
                            value: $recurrenceInterval,
                            in: 1 ... 365
                        )

                        if recurrenceFrequency == .weekly {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                                ForEach(recurrenceWeekdayOptions, id: \.self) { day in
                                    Button(day) {
                                        if recurrenceWeekdays.contains(day) {
                                            recurrenceWeekdays.remove(day)
                                        } else {
                                            recurrenceWeekdays.insert(day)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(recurrenceWeekdays.contains(day) ? .accentColor : .secondary)
                                }
                            }
                        }
                    }
                }

                Section("Preview") {
                    Text(recurrenceBuilderPreview() ?? "Never")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Custom Repeat")
            .modifier(TaskDetailInlineTitleDisplay())
            .toolbar {
                ToolbarItem(placement: .appLeadingAction) {
                    Button {
                        showingCustomRepeatEditor = false
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
                ToolbarItem(placement: .appTrailingAction) {
                    Button("Save") {
                        applyRecurrenceBuilder()
                        showingCustomRepeatEditor = false
                    }
                    .disabled(recurrenceFrequency == .weekly && recurrenceWeekdays.isEmpty)
                }
            }
        }
    }

    private var locationEditorView: some View {
        NavigationStack {
            Form {
                Section("Location Reminder") {
                    Toggle("Enable", isOn: binding(\.hasLocationReminder))

                    if editState?.hasLocationReminder == true {
                        Picker("Trigger", selection: binding(\.locationTrigger)) {
                            Text("On Arrival").tag(TaskLocationReminderTrigger.onArrival)
                            Text("On Departure").tag(TaskLocationReminderTrigger.onDeparture)
                        }
                        .pickerStyle(.segmented)

                        TextField("Name", text: binding(\.locationName))
                        TextField("Latitude", text: binding(\.locationLatitude))
                            .modifier(TaskDetailDecimalKeyboard())
                        TextField("Longitude", text: binding(\.locationLongitude))
                            .modifier(TaskDetailDecimalKeyboard())
                        Stepper(
                            "Radius: \(editState?.locationRadiusMeters ?? 100) m",
                            value: binding(\.locationRadiusMeters),
                            in: 50 ... 1000,
                            step: 50
                        )
                    }
                }

                if !container.locationFavorites.isEmpty {
                    Section("Saved Locations") {
                        Picker("Favorite", selection: $selectedLocationFavoriteID) {
                            ForEach(container.locationFavorites) { fav in
                                Text(fav.name).tag(fav.id)
                            }
                        }
                        .pickerStyle(.menu)

                        HStack {
                            Button("Apply") { applySelectedLocationFavorite() }
                            Spacer()
                            Button("Delete", role: .destructive) { deleteSelectedLocationFavorite() }
                        }
                    }
                }

                if editState?.hasLocationReminder == true {
                    Section("Save as Preset") {
                        TextField("Preset name", text: $locationPresetName)
                        Button("Save Preset") { saveCurrentLocationAsPreset() }
                            .disabled(locationPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                                (editState?.locationName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    .isEmpty ?? true))
                    }
                }
            }
            .navigationTitle("Location")
            .modifier(TaskDetailInlineTitleDisplay())
            .toolbar {
                ToolbarItem(placement: .appTrailingAction) {
                    Button("Done") { expandedLocationReminder = false }
                }
            }
        }
    }

    private func cycleStatus() {
        guard var s = editState else { return }
        let order: [TaskStatus] = [.todo, .inProgress, .done, .cancelled]
        let current = order.firstIndex(of: s.status) ?? 0
        s.status = order[(current + 1) % order.count]
        editState = s
    }

    private func cyclePriority() {
        guard var s = editState else { return }
        let order: [TaskPriority] = [.none, .low, .medium, .high]
        let current = order.firstIndex(of: s.priority) ?? 0
        s.priority = order[(current + 1) % order.count]
        editState = s
    }

    private func dueDateText(_ s: TaskEditState) -> String {
        guard s.hasDue else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = s.hasDueTime ? .short : .none
        return formatter.string(from: s.dueDate)
    }

    private func scheduledDateText(_ s: TaskEditState) -> String {
        guard s.hasScheduled else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: s.scheduledDate)
    }

    private func currentTags() -> [String] {
        let value = binding(\.tagsText).wrappedValue
        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func addTag(_ tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var tags = currentTags()
        if !tags.contains(trimmed) {
            tags.append(trimmed)
            binding(\.tagsText).wrappedValue = tags.joined(separator: ", ")
        }
    }

    private func addTag() {
        addTag(newTagText)
        newTagText = ""
    }

    private func removeTag(_ tag: String) {
        let tags = currentTags().filter { $0 != tag }
        binding(\.tagsText).wrappedValue = tags.joined(separator: ", ")
    }

    private func applyRecurrenceBuilder() {
        guard let freq = recurrenceFrequency.rruleValue else {
            binding(\.recurrence).wrappedValue = ""
            return
        }

        var fields = ["FREQ=\(freq)"]
        if recurrenceInterval > 1 {
            fields.append("INTERVAL=\(recurrenceInterval)")
        }
        if recurrenceFrequency == .weekly, !recurrenceWeekdays.isEmpty {
            let ordered = recurrenceWeekdayOptions.filter { recurrenceWeekdays.contains($0) }
            fields.append("BYDAY=\(ordered.joined(separator: ","))")
        }

        binding(\.recurrence).wrappedValue = fields.joined(separator: ";")
    }

    private func recurrenceBuilderPreview() -> String? {
        switch recurrenceFrequency {
        case .none:
            return nil
        case .daily:
            return recurrenceInterval == 1 ? "Every day" : "Every \(recurrenceInterval) days"
        case .weekly:
            if recurrenceWeekdays.isEmpty {
                return recurrenceInterval == 1 ? "Every week" : "Every \(recurrenceInterval) weeks"
            }
            let dayMap: [String: String] = [
                "MO": "Mon", "TU": "Tue", "WE": "Wed", "TH": "Thu",
                "FR": "Fri", "SA": "Sat", "SU": "Sun",
            ]
            let orderedDays = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
            let dayNames = orderedDays
                .filter { recurrenceWeekdays.contains($0) }
                .compactMap { dayMap[$0] }
                .joined(separator: ", ")
            let weekPart = recurrenceInterval == 1 ? "week" : "\(recurrenceInterval) weeks"
            return "Every \(weekPart) on \(dayNames)"
        case .monthly:
            return recurrenceInterval == 1 ? "Every month" : "Every \(recurrenceInterval) months"
        case .yearly:
            return recurrenceInterval == 1 ? "Every year" : "Every \(recurrenceInterval) years"
        }
    }

    private func syncRecurrenceBuilderFromEditState() {
        guard let recurrence = editState?.recurrence, !recurrence.isEmpty else {
            recurrenceFrequency = .none
            recurrenceInterval = 1
            recurrenceWeekdays = []
            return
        }

        do {
            let parsed = try RecurrenceRule.parse(recurrence)
            recurrenceInterval = max(1, parsed.interval)
            recurrenceWeekdays = Set(parsed.byDay)
            switch parsed.frequency {
            case .daily:
                recurrenceFrequency = .daily
            case .weekly:
                recurrenceFrequency = .weekly
            case .monthly:
                recurrenceFrequency = .monthly
            case .yearly:
                recurrenceFrequency = .yearly
            }
        } catch {
            recurrenceFrequency = .none
            recurrenceInterval = 1
            recurrenceWeekdays = []
        }
    }

    private func applyRecurrencePreset(rule: String) {
        binding(\.recurrence).wrappedValue = rule
        syncRecurrenceBuilderFromEditState()
    }

    private func clearRecurrence() {
        binding(\.recurrence).wrappedValue = ""
        recurrenceFrequency = .none
        recurrenceInterval = 1
        recurrenceWeekdays = []
    }

    private func recurrenceSummaryText() -> String {
        let rule = editState?.recurrence.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rule.isEmpty else { return "Never" }
        guard let parsed = try? RecurrenceRule.parse(rule) else { return rule }

        let anchorDate = recurrenceAnchorDate()
        switch parsed.frequency {
        case .daily:
            return parsed.interval == 1 ? "Every day" : "Every \(parsed.interval) days"
        case .weekly:
            if parsed.byDay.isEmpty {
                return parsed.interval == 1 ? "Every week" : "Every \(parsed.interval) weeks"
            }
            let dayNames = parsed.byDay
                .compactMap(weekdayShortText(fromToken:))
                .joined(separator: ", ")
            if parsed.interval == 1 {
                return dayNames.isEmpty ? "Every week" : "Every week on \(dayNames)"
            }
            return dayNames.isEmpty ? "Every \(parsed.interval) weeks" : "Every \(parsed.interval) weeks on \(dayNames)"
        case .monthly:
            let dayText = ordinal(dayOfMonth(from: anchorDate))
            return parsed.interval == 1 ? "Every month on the \(dayText)" : "Every \(parsed.interval) months on the \(dayText)"
        case .yearly:
            let dateText = monthDayText(for: anchorDate)
            return parsed.interval == 1 ? "Every year on \(dateText)" : "Every \(parsed.interval) years on \(dateText)"
        }
    }

    private func recurrenceAnchorDate() -> Date {
        guard let editState else { return Date() }
        if editState.hasScheduled {
            return editState.scheduledDate
        }
        if editState.hasDue {
            return editState.dueDate
        }
        return Date()
    }

    private func recurrenceUnitText() -> String {
        let singular: String
        let plural: String
        switch recurrenceFrequency {
        case .none, .daily:
            singular = "day"
            plural = "days"
        case .weekly:
            singular = "week"
            plural = "weeks"
        case .monthly:
            singular = "month"
            plural = "months"
        case .yearly:
            singular = "year"
            plural = "years"
        }
        return recurrenceInterval == 1 ? singular : plural
    }

    private func dayOfMonth(from date: Date) -> Int {
        Calendar.current.component(.day, from: date)
    }

    private func monthDayText(for date: Date) -> String {
        date.formatted(Date.FormatStyle().month(.abbreviated).day())
    }

    private func weekdayShortText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }

    private func weekdayToken(for date: Date) -> String {
        switch Calendar.current.component(.weekday, from: date) {
        case 1: "SU"
        case 2: "MO"
        case 3: "TU"
        case 4: "WE"
        case 5: "TH"
        case 6: "FR"
        case 7: "SA"
        default: "MO"
        }
    }

    private func weekdayShortText(fromToken token: String) -> String? {
        switch token {
        case "MO": "Mon"
        case "TU": "Tue"
        case "WE": "Wed"
        case "TH": "Thu"
        case "FR": "Fri"
        case "SA": "Sat"
        case "SU": "Sun"
        default: nil
        }
    }

    private func ordinal(_ day: Int) -> String {
        let mod100 = day % 100
        let suffix = if (11 ... 13).contains(mod100) {
            "th"
        } else {
            switch day % 10 {
            case 1: "st"
            case 2: "nd"
            case 3: "rd"
            default: "th"
            }
        }
        return "\(day)\(suffix)"
    }

    private func detailRow(_ title: String, value: String?) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text((value ?? "").isEmpty ? "-" : (value ?? ""))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
    }

    private func statusChip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Rectangle().fill(Color.secondary.opacity(0.18)))
    }

    private func dateText(_ value: Date?) -> String {
        guard let value else { return "" }
        return value.formatted(date: .abbreviated, time: .omitted)
    }

    private func blockedBySummary() -> String {
        if binding(\.blockedByManual).wrappedValue {
            return "Blocked (manual)"
        }
        let refs = binding(\.blockedByRefsText).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return refs.isEmpty ? "" : refs
    }

    private func dueText(date: Date?, hasTime: Bool, time: Date) -> String {
        guard let date else { return "" }
        if !hasTime {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        return "\(date.formatted(date: .abbreviated, time: .omitted)) at \(time.formatted(date: .omitted, time: .shortened))"
    }

    private var constantFalseBinding: Binding<Bool> {
        Binding(get: { false }, set: { _ in })
    }

    private var constantDateBinding: Binding<Date> {
        Binding(get: { editState?.scheduledDate ?? Date() }, set: { _ in })
    }

    private var projectBinding: Binding<String> {
        Binding(
            get: { editState?.project ?? "" },
            set: { newValue in
                guard var editState else { return }
                editState.project = newValue
                self.editState = editState
                scheduleProjectPersistence()
            }
        )
    }

    private func autoSave() {
        guard let editState else { return }
        if let locationError = validateLocationReminder(editState) {
            errorMessage = locationError
            return
        }
        container.updateTask(path: path, editState: editState)
    }

    private func locationSummary() -> String {
        guard binding(\.hasLocationReminder).wrappedValue else { return "" }
        let trigger = binding(\.locationTrigger).wrappedValue == .onArrival ? "Arrive" : "Leave"
        let latitude = binding(\.locationLatitude).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let longitude = binding(\.locationLongitude).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let locationName = binding(\.locationName).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let radius = binding(\.locationRadiusMeters).wrappedValue

        let namePrefix = locationName.isEmpty ? "" : "\(locationName) • "
        return "\(namePrefix)\(trigger) (\(latitude), \(longitude), \(radius)m)"
    }

    private func validateLocationReminder(_ editState: TaskEditState) -> String? {
        guard editState.hasLocationReminder else { return nil }

        let latitudeText = editState.locationLatitude.trimmingCharacters(in: .whitespacesAndNewlines)
        let longitudeText = editState.locationLongitude.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let latitude = Double(latitudeText), let longitude = Double(longitudeText) else {
            return "Location reminder requires numeric latitude and longitude."
        }
        guard (-90.0 ... 90.0).contains(latitude) else {
            return "Latitude must be between -90 and 90."
        }
        guard (-180.0 ... 180.0).contains(longitude) else {
            return "Longitude must be between -180 and 180."
        }
        guard (50 ... 1000).contains(editState.locationRadiusMeters) else {
            return "Location radius must be between 50 and 1000 meters."
        }

        let locationName = editState.locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if locationName.count > TaskValidation.maxLocationNameLength {
            return "Location name must be \(TaskValidation.maxLocationNameLength) characters or fewer."
        }

        return nil
    }

    private func scheduleProjectPersistence() {
        pendingProjectPersistenceTask?.cancel()
        pendingProjectPersistenceTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            persistProjectRoutingIfNeeded()
        }
    }

    private func persistProjectRoutingIfNeeded() {
        guard let persistedFrontmatter = container.record(for: path)?.document.frontmatter else { return }

        let persistedArea = normalizedRoutingValue(persistedFrontmatter.area)
        let persistedProject = normalizedRoutingValue(persistedFrontmatter.project)
        guard let editState else { return }

        let currentArea = normalizedRoutingValue(editState.area)
        let currentProject = normalizedRoutingValue(editState.project)
        guard persistedArea != currentArea || persistedProject != currentProject else { return }

        let didSave: Bool
        if let currentProject, currentArea == nil {
            didSave = container.addToProject(path: path, project: currentProject)
        } else {
            didSave = container.moveTask(path: path, area: currentArea, project: currentProject)
        }

        guard didSave,
              let updatedFrontmatter = container.record(for: path)?.document.frontmatter,
              var syncedEditState = self.editState
        else {
            return
        }

        syncedEditState.area = updatedFrontmatter.area ?? ""
        syncedEditState.project = updatedFrontmatter.project ?? ""
        self.editState = syncedEditState
    }

    private func normalizedRoutingValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var selectedLocationFavorite: LocationFavorite? {
        guard !selectedLocationFavoriteID.isEmpty else { return nil }
        return container.locationFavorites.first(where: { $0.id == selectedLocationFavoriteID })
    }

    private func syncSelectedLocationFavorite() {
        if let selectedLocationFavorite,
           container.locationFavorites.contains(where: { $0.id == selectedLocationFavorite.id })
        {
            return
        }
        selectedLocationFavoriteID = container.locationFavorites.first?.id ?? ""
    }

    private func applySelectedLocationFavorite() {
        guard let favorite = selectedLocationFavorite else { return }
        binding(\.hasLocationReminder).wrappedValue = true
        binding(\.locationName).wrappedValue = favorite.name
        binding(\.locationLatitude).wrappedValue = String(format: "%.6f", favorite.latitude)
        binding(\.locationLongitude).wrappedValue = String(format: "%.6f", favorite.longitude)
        binding(\.locationRadiusMeters).wrappedValue = favorite.radiusMeters
    }

    private func deleteSelectedLocationFavorite() {
        guard let favorite = selectedLocationFavorite else { return }
        container.deleteLocationFavorite(id: favorite.id)
        selectedLocationFavoriteID = container.locationFavorites.first?.id ?? ""
    }

    private func saveCurrentLocationAsPreset() {
        let preferredName = locationPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let locationName = binding(\.locationName).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameToSave = preferredName.isEmpty ? locationName : preferredName
        guard !nameToSave.isEmpty else {
            errorMessage = "Preset name is required."
            return
        }

        let latitudeText = binding(\.locationLatitude).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let longitudeText = binding(\.locationLongitude).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let latitude = Double(latitudeText), let longitude = Double(longitudeText) else {
            errorMessage = "Enter valid latitude and longitude before saving a preset."
            return
        }

        let radius = binding(\.locationRadiusMeters).wrappedValue
        guard let saved = container.saveLocationFavorite(
            name: nameToSave,
            latitude: latitude,
            longitude: longitude,
            radiusMeters: radius
        ) else {
            errorMessage = "Could not save location preset. Check name and coordinates."
            return
        }

        selectedLocationFavoriteID = saved.id
        locationPresetName = saved.name
    }

    private func binding<T>(_ keyPath: WritableKeyPath<TaskEditState, T>) -> Binding<T> {
        Binding(
            get: {
                guard let editState else {
                    fatalError("TaskEditState missing")
                }
                return editState[keyPath: keyPath]
            },
            set: { newValue in
                guard var editState else { return }
                editState[keyPath: keyPath] = newValue
                self.editState = editState
            }
        )
    }
}

private struct PropertyRow<Content: View>: View {
    let icon: String
    let label: String
    let valueText: String
    let isExpanded: Bool
    let accessibilityIdentifier: String?
    let onTap: () -> Void
    @ViewBuilder let expandedContent: () -> Content

    init(
        icon: String,
        label: String,
        valueText: String,
        isExpanded: Bool,
        accessibilityIdentifier: String? = nil,
        onTap: @escaping () -> Void,
        @ViewBuilder expandedContent: @escaping () -> Content
    ) {
        self.icon = icon
        self.label = label
        self.valueText = valueText
        self.isExpanded = isExpanded
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onTap = onTap
        self.expandedContent = expandedContent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .frame(width: 20)
                        .foregroundStyle(.secondary)
                    Text(label)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(valueText.isEmpty ? "—" : valueText)
                        .foregroundStyle(valueText.isEmpty ? .tertiary : .secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .taskDetailAccessibilityIdentifier(accessibilityIdentifier)

            if isExpanded {
                expandedContent()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }

            Divider()
                .padding(.leading, 52)
        }
    }
}

private struct TaskDetailInlineTitleDisplay: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
            content.navigationBarTitleDisplayMode(.inline)
        #else
            content
        #endif
    }
}

private struct TaskDetailDecimalKeyboard: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
            content.keyboardType(.decimalPad)
        #else
            content
        #endif
    }
}

private struct TaskDetailNotesPresentation<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let presentedContent: () -> SheetContent

    func body(content: Content) -> some View {
        #if os(iOS)
            content.fullScreenCover(isPresented: $isPresented, content: presentedContent)
        #else
            content.sheet(isPresented: $isPresented, content: presentedContent)
        #endif
    }
}

private extension View {
    @ViewBuilder
    func taskDetailAccessibilityIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}
