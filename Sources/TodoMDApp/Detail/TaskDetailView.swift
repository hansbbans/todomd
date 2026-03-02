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
            return nil
        case .daily:
            return "DAILY"
        case .weekly:
            return "WEEKLY"
        case .monthly:
            return "MONTHLY"
        case .yearly:
            return "YEARLY"
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
    @State private var isEditing = false
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?
    @State private var showNotesEditor = false
    @State private var newTagText = ""
    @State private var locationPresetName = ""
    @State private var selectedLocationFavoriteID = ""

    @State private var recurrenceFrequency: RecurrenceFrequencyOption = .none
    @State private var recurrenceInterval = 1
    @State private var recurrenceWeekdays: Set<String> = []
    @State private var showingRepeatPresetMenu = false
    @State private var showingCustomRepeatEditor = false
    @State private var expandedRow: ExpandedRow?

    @AppStorage("taskDetail.expandedDependencies") private var expandedDependencies = false
    @AppStorage("taskDetail.expandedLocationReminder") private var expandedLocationReminder = false
    @AppStorage("taskDetail.expandedMetadata") private var expandedMetadata = false

    @State private var latitudeError: String?
    @State private var longitudeError: String?
    @State private var titleError: String?

    private let recurrenceWeekdayOptions = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

    var body: some View {
        Group {
            if editState != nil {
                if isEditing {
                    editForm
                } else {
                    readOnlyView
                }
            } else {
                ContentUnavailableView("Task Unavailable", systemImage: "exclamationmark.triangle")
            }
        }
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing {
                        isEditing = false
                    } else {
                        syncRecurrenceBuilderFromEditState()
                        isEditing = true
                    }
                }
                .keyboardShortcut(isEditing ? KeyEquivalent.return : KeyEquivalent("e"), modifiers: .command)
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
            autoSave()
        }
        .onChange(of: container.locationFavorites.map(\.id), initial: false) { _, _ in
            syncSelectedLocationFavorite()
        }
        .fullScreenCover(isPresented: $showNotesEditor) {
            notesEditorView
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
                    Text(editState?.priority == .none ? "—" : (editState?.priority.rawValue.capitalized ?? "—"))
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
            PropertyRow(
                icon: "calendar",
                label: "Due",
                valueText: editState.map { dueDateText($0) } ?? "",
                isExpanded: expandedRow == .due,
                onTap: { expandedRow = expandedRow == .due ? nil : .due }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Set due date", isOn: binding(\.hasDue))
                    if editState?.hasDue == true {
                        DatePicker("Date", selection: binding(\.dueDate), displayedComponents: .date)
                        Toggle("Include time", isOn: binding(\.hasDueTime))
                        if editState?.hasDueTime == true {
                            DatePicker("Time", selection: binding(\.dueTime), displayedComponents: .hourAndMinute)
                        }
                    }
                }
            }

            // Scheduled
            PropertyRow(
                icon: "calendar.badge.clock",
                label: "Scheduled",
                valueText: editState.map { scheduledDateText($0) } ?? "",
                isExpanded: expandedRow == .scheduled,
                onTap: { expandedRow = expandedRow == .scheduled ? nil : .scheduled }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Set scheduled date", isOn: binding(\.hasScheduled))
                    if editState?.hasScheduled == true {
                        DatePicker("Date", selection: binding(\.scheduledDate), displayedComponents: .date)
                    }
                }
            }
        }
    }

    private var readOnlyView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(binding(\.title).wrappedValue)
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .foregroundStyle(theme.textPrimaryColor)
                    .lineLimit(4)

                if !binding(\.subtitle).wrappedValue.isEmpty {
                    Text(binding(\.subtitle).wrappedValue)
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(theme.textSecondaryColor)
                }

                HStack(spacing: 10) {
                    statusChip(binding(\.status).wrappedValue.rawValue.capitalized)
                    if binding(\.priority).wrappedValue != .none {
                        statusChip(binding(\.priority).wrappedValue.rawValue.capitalized)
                    }
                    Button {
                        _ = container.toggleFlag(path: path)
                        editState = container.makeEditState(path: path)
                    } label: {
                        Image(systemName: binding(\.flagged).wrappedValue ? "flag.fill" : "flag")
                            .foregroundStyle(binding(\.flagged).wrappedValue ? .orange : .secondary)
                    }
                }

                Group {
                    detailRow("Ref", value: binding(\.ref).wrappedValue)
                    detailRow("Assignee", value: binding(\.assignee).wrappedValue)
                    detailRow("Blocked By", value: blockedBySummary())
                    detailRow(
                        "Due",
                        value: dueText(
                            date: binding(\.hasDue).wrappedValue ? binding(\.dueDate).wrappedValue : nil,
                            hasTime: binding(\.hasDue).wrappedValue && binding(\.hasDueTime).wrappedValue,
                            time: binding(\.dueTime).wrappedValue
                        )
                    )
                    detailRow("Persistent reminder", value: binding(\.persistentReminderEnabled).wrappedValue ? "On" : "Off")
                    detailRow("Scheduled", value: dateText(binding(\.hasScheduled).wrappedValue ? binding(\.scheduledDate).wrappedValue : nil))
                    detailRow("Defer", value: dateText(binding(\.hasDefer).wrappedValue ? binding(\.deferDate).wrappedValue : nil))
                    detailRow("Location", value: locationSummary())
                    detailRow("Area", value: binding(\.area).wrappedValue)
                    detailRow("Project", value: binding(\.project).wrappedValue)
                    detailRow("Tags", value: currentTags().joined(separator: ", "))
                    detailRow("Recurrence", value: binding(\.recurrence).wrappedValue)
                    detailRow("Estimated", value: binding(\.hasEstimatedMinutes).wrappedValue ? "\(binding(\.estimatedMinutes).wrappedValue) min" : "")
                }

                Button {
                    showNotesEditor = true
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(.headline)
                        Text(binding(\.body).wrappedValue.isEmpty ? "No notes" : binding(\.body).wrappedValue)
                            .font(.body)
                            .foregroundStyle(binding(\.body).wrappedValue.isEmpty ? .secondary : .primary)
                            .lineLimit(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)

                DisclosureGroup(isExpanded: $expandedMetadata) {
                    VStack(alignment: .leading, spacing: 6) {
                        detailRow("Source", value: binding(\.source).wrappedValue)
                        detailRow("Created", value: DateCoding.encode(binding(\.createdAt).wrappedValue))
                        if let modified = binding(\.modifiedAt).wrappedValue {
                            detailRow("Modified", value: DateCoding.encode(modified))
                        }
                        if let completed = binding(\.completedAt).wrappedValue {
                            detailRow("Completed", value: DateCoding.encode(completed))
                        }
                        if !binding(\.completedBy).wrappedValue.isEmpty {
                            detailRow("Completed By", value: binding(\.completedBy).wrappedValue)
                        }
                    }
                } label: {
                    Text("Metadata")
                        .font(.headline)
                }

                HStack {
                    Button("Edit") {
                        syncRecurrenceBuilderFromEditState()
                        isEditing = true
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Delete Task", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(20)
        }
        .background(theme.backgroundColor.ignoresSafeArea())
    }

    private var editForm: some View {
        Form {
            Section {
                DisclosureGroup(isExpanded: $expandedDependencies) {
                    TextField("Ref (t-xxxx)", text: binding(\.ref))
                        .textInputAutocapitalization(.never)
                    TextField("Assignee (blank = user)", text: binding(\.assignee))
                        .textInputAutocapitalization(.never)
                    Toggle("Blocked (no specific dependency)", isOn: binding(\.blockedByManual))
                    TextField("Blocked by refs (comma-separated)", text: binding(\.blockedByRefsText))
                        .textInputAutocapitalization(.never)
                        .disabled(binding(\.blockedByManual).wrappedValue)
                } label: {
                    Text("Assignment & Dependencies")
                        .font(.headline)
                }
            } footer: {
                Text("Use task refs like t-3f8a for dependency links.")
            }

            Section {
                TextField("Title", text: binding(\.title), axis: .vertical)
                    .font(.title2.weight(.semibold))
                    .onChange(of: binding(\.title).wrappedValue) { _, newValue in
                        if newValue.count > TaskValidation.maxTitleLength {
                            titleError = "Title must be \(TaskValidation.maxTitleLength) characters or fewer"
                        } else {
                            titleError = nil
                        }
                    }
                if let titleError {
                    Text(titleError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                TextField("Description", text: binding(\.subtitle), axis: .vertical)
                    .foregroundStyle(.secondary)
            }

            Section("Status") {
                Picker("Status", selection: binding(\.status)) {
                    ForEach(TaskStatus.allCases, id: \.self) { status in
                        Text(status.rawValue).tag(status)
                    }
                }

                Button {
                    binding(\.flagged).wrappedValue.toggle()
                } label: {
                    Label(
                        binding(\.flagged).wrappedValue ? "Flagged" : "Not Flagged",
                        systemImage: binding(\.flagged).wrappedValue ? "flag.fill" : "flag"
                    )
                    .foregroundStyle(binding(\.flagged).wrappedValue ? .orange : .primary)
                }

                Picker("Priority", selection: binding(\.priority)) {
                    ForEach(TaskPriority.allCases, id: \.self) { priority in
                        Text(priority.rawValue).tag(priority)
                    }
                }
            }

            Section("Dates") {
                Toggle(
                    "Due",
                    isOn: Binding(
                        get: { binding(\.hasDue).wrappedValue },
                        set: { isEnabled in
                            binding(\.hasDue).wrappedValue = isEnabled
                            if !isEnabled {
                                binding(\.hasDueTime).wrappedValue = false
                                binding(\.persistentReminderEnabled).wrappedValue = false
                            }
                        }
                    )
                )
                if binding(\.hasDue).wrappedValue {
                    DatePicker("Due date", selection: binding(\.dueDate), displayedComponents: .date)
                    Toggle(
                        "Specific due time",
                        isOn: Binding(
                            get: { binding(\.hasDueTime).wrappedValue },
                            set: { isEnabled in
                                binding(\.hasDueTime).wrappedValue = isEnabled
                                if !isEnabled {
                                    binding(\.persistentReminderEnabled).wrappedValue = false
                                }
                            }
                        )
                    )
                    if binding(\.hasDueTime).wrappedValue {
                        DatePicker("Due time", selection: binding(\.dueTime), displayedComponents: .hourAndMinute)
                    }

                    Toggle(
                        "Persistent reminder",
                        isOn: Binding(
                            get: {
                                let canEnable = binding(\.hasDue).wrappedValue && binding(\.hasDueTime).wrappedValue
                                return canEnable && binding(\.persistentReminderEnabled).wrappedValue
                            },
                            set: { isEnabled in
                                let canEnable = binding(\.hasDue).wrappedValue && binding(\.hasDueTime).wrappedValue
                                binding(\.persistentReminderEnabled).wrappedValue = canEnable && isEnabled
                            }
                        )
                    )
                    .disabled(!(binding(\.hasDue).wrappedValue && binding(\.hasDueTime).wrappedValue))

                    if !(binding(\.hasDue).wrappedValue && binding(\.hasDueTime).wrappedValue) {
                        Text("Set due date and specific due time to enable persistent reminders.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Defer", isOn: binding(\.hasDefer))
                if binding(\.hasDefer).wrappedValue {
                    DatePicker("Defer until", selection: binding(\.deferDate), displayedComponents: .date)
                }

                Toggle("Scheduled", isOn: binding(\.hasScheduled))
                if binding(\.hasScheduled).wrappedValue {
                    DatePicker("Scheduled date", selection: binding(\.scheduledDate), displayedComponents: .date)
                }
            }

            Section("Location Reminder") {
                DisclosureGroup(isExpanded: $expandedLocationReminder) {
                    Toggle("Enable location reminder", isOn: binding(\.hasLocationReminder))
                    if binding(\.hasLocationReminder).wrappedValue {
                        if container.locationFavorites.isEmpty {
                            Text("No saved presets yet.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Preset", selection: $selectedLocationFavoriteID) {
                                Text("Choose preset").tag("")
                                ForEach(container.locationFavorites) { favorite in
                                    Text(favorite.name).tag(favorite.id)
                                }
                            }

                            HStack {
                                Button("Use Preset") {
                                    applySelectedLocationFavorite()
                                }
                                .buttonStyle(.bordered)
                                .disabled(selectedLocationFavorite == nil)

                                Button("Delete Preset", role: .destructive) {
                                    deleteSelectedLocationFavorite()
                                }
                                .buttonStyle(.bordered)
                                .disabled(selectedLocationFavorite == nil)
                            }
                        }

                        TextField("Location name (optional)", text: binding(\.locationName))

                        TextField("Latitude", text: binding(\.locationLatitude))
                            .keyboardType(.decimalPad)
                            .textInputAutocapitalization(.never)
                            .onChange(of: binding(\.locationLatitude).wrappedValue) { _, newValue in
                                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                if trimmed.isEmpty {
                                    latitudeError = nil
                                } else if let lat = Double(trimmed), (-90.0...90.0).contains(lat) {
                                    latitudeError = nil
                                } else {
                                    latitudeError = "Latitude must be between -90 and 90"
                                }
                            }
                        if let latitudeError {
                            Text(latitudeError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        TextField("Longitude", text: binding(\.locationLongitude))
                            .keyboardType(.decimalPad)
                            .textInputAutocapitalization(.never)
                            .onChange(of: binding(\.locationLongitude).wrappedValue) { _, newValue in
                                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                if trimmed.isEmpty {
                                    longitudeError = nil
                                } else if let lon = Double(trimmed), (-180.0...180.0).contains(lon) {
                                    longitudeError = nil
                                } else {
                                    longitudeError = "Longitude must be between -180 and 180"
                                }
                            }
                        if let longitudeError {
                            Text(longitudeError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        Stepper(value: binding(\.locationRadiusMeters), in: 50...1_000, step: 25) {
                            Text("Radius: \(binding(\.locationRadiusMeters).wrappedValue) m")
                        }

                        Picker("Notify when", selection: binding(\.locationTrigger)) {
                            Text("Arriving").tag(TaskLocationReminderTrigger.onArrival)
                            Text("Leaving").tag(TaskLocationReminderTrigger.onDeparture)
                        }

                        HStack {
                            TextField("Preset name (Home, Work)", text: $locationPresetName)
                            Button("Save Preset") {
                                saveCurrentLocationAsPreset()
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Text("The app will ask for location permission when this reminder is saved.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text("Location Reminder")
                        .font(.headline)
                }
            }

            Section("Planning") {
                Toggle("Estimated minutes", isOn: binding(\.hasEstimatedMinutes))
                if binding(\.hasEstimatedMinutes).wrappedValue {
                    HStack {
                        ForEach([5, 15, 30, 60, 120], id: \.self) { preset in
                            Button("\(preset)m") {
                                binding(\.estimatedMinutes).wrappedValue = preset
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    Stepper(value: binding(\.estimatedMinutes), in: 1...720, step: 5) {
                        Text("\(binding(\.estimatedMinutes).wrappedValue) minutes")
                    }
                }

                Picker("Area", selection: binding(\.area)) {
                    Text("None").tag("")
                    ForEach(container.availableAreas(), id: \.self) { area in
                        Text(area).tag(area)
                    }
                }
                TextField("Custom area", text: binding(\.area))

                Picker("Project", selection: binding(\.project)) {
                    Text("None").tag("")
                    ForEach(container.availableProjects(inArea: binding(\.area).wrappedValue), id: \.self) { project in
                        Text(project).tag(project)
                    }
                }
                TextField("Custom project", text: binding(\.project))
            }

            Section("Tags") {
                let tags = currentTags()
                if tags.isEmpty {
                    Text("No tags")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            Button {
                                removeTag(tag)
                            } label: {
                                HStack(spacing: 4) {
                                    Text(tag)
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Rectangle().fill(Color.secondary.opacity(0.2)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack {
                    TextField("Add tag", text: $newTagText)
                        .textInputAutocapitalization(.never)
                    Button("Add") {
                        addTag(newTagText)
                        newTagText = ""
                    }
                    .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section("Repeating Task") {
                Button {
                    showingRepeatPresetMenu = true
                } label: {
                    HStack(spacing: 12) {
                        Text("Pattern")
                        Spacer(minLength: 12)
                        Text(recurrenceSummaryText())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)

                if !binding(\.recurrence).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Custom") {
                        syncRecurrenceBuilderFromEditState()
                        showingCustomRepeatEditor = true
                    }
                    Button("Clear Repeat", role: .destructive) {
                        clearRecurrence()
                    }
                }
            }

            Section("Notes") {
                Button("Open Full Screen Notes") {
                    showNotesEditor = true
                }
                Text(binding(\.body).wrappedValue.isEmpty ? "No notes" : binding(\.body).wrappedValue)
                    .lineLimit(3)
                    .foregroundStyle(.secondary)
            }

            Section("Metadata") {
                DisclosureGroup(isExpanded: $expandedMetadata) {
                    LabeledContent("Source", value: binding(\.source).wrappedValue)
                    LabeledContent("Created", value: DateCoding.encode(binding(\.createdAt).wrappedValue))
                    if let modified = binding(\.modifiedAt).wrappedValue {
                        LabeledContent("Modified", value: DateCoding.encode(modified))
                    }
                    if let completed = binding(\.completedAt).wrappedValue {
                        LabeledContent("Completed", value: DateCoding.encode(completed))
                    }
                } label: {
                    Text("Metadata")
                        .font(.headline)
                }
            }

            Section {
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)

                Button("Delete Task", role: .destructive) {
                    showDeleteConfirmation = true
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
                    ToolbarItem(placement: .topBarTrailing) {
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
                            in: 1...365
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingCustomRepeatEditor = false
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        applyRecurrenceBuilder()
                        showingCustomRepeatEditor = false
                    }
                    .disabled(recurrenceFrequency == .weekly && recurrenceWeekdays.isEmpty)
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
        if recurrenceFrequency == .weekly && !recurrenceWeekdays.isEmpty {
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
                "FR": "Fri", "SA": "Sat", "SU": "Sun"
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
        case 1: return "SU"
        case 2: return "MO"
        case 3: return "TU"
        case 4: return "WE"
        case 5: return "TH"
        case 6: return "FR"
        case 7: return "SA"
        default: return "MO"
        }
    }

    private func weekdayShortText(fromToken token: String) -> String? {
        switch token {
        case "MO": return "Mon"
        case "TU": return "Tue"
        case "WE": return "Wed"
        case "TH": return "Thu"
        case "FR": return "Fri"
        case "SA": return "Sat"
        case "SU": return "Sun"
        default: return nil
        }
    }

    private func ordinal(_ day: Int) -> String {
        let mod100 = day % 100
        let suffix: String
        if (11...13).contains(mod100) {
            suffix = "th"
        } else {
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
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

    private func save() {
        guard let editState else { return }
        if let locationError = validateLocationReminder(editState) {
            errorMessage = locationError
            return
        }
        let didSave = container.updateTask(path: path, editState: editState)
        if didSave {
            self.editState = container.makeEditState(path: path)
            isEditing = false
        } else {
            errorMessage = "Could not save this task. Please check required fields and try again."
        }
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
        guard (-90.0...90.0).contains(latitude) else {
            return "Latitude must be between -90 and 90."
        }
        guard (-180.0...180.0).contains(longitude) else {
            return "Longitude must be between -180 and 180."
        }
        guard (50...1_000).contains(editState.locationRadiusMeters) else {
            return "Location radius must be between 50 and 1000 meters."
        }

        let locationName = editState.locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if locationName.count > TaskValidation.maxLocationNameLength {
            return "Location name must be \(TaskValidation.maxLocationNameLength) characters or fewer."
        }

        return nil
    }

    private var selectedLocationFavorite: LocationFavorite? {
        guard !selectedLocationFavoriteID.isEmpty else { return nil }
        return container.locationFavorites.first(where: { $0.id == selectedLocationFavoriteID })
    }

    private func syncSelectedLocationFavorite() {
        if let selectedLocationFavorite,
           container.locationFavorites.contains(where: { $0.id == selectedLocationFavorite.id }) {
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
    let onTap: () -> Void
    @ViewBuilder let expandedContent: () -> Content

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
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

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
