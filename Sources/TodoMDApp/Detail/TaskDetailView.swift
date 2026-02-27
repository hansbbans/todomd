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
        .onChange(of: container.locationFavorites.map(\.id), initial: false) { _, _ in
            syncSelectedLocationFavorite()
        }
        .fullScreenCover(isPresented: $showNotesEditor) {
            notesEditorView
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
                    detailRow(
                        "Due",
                        value: dueText(
                            date: binding(\.hasDue).wrappedValue ? binding(\.dueDate).wrappedValue : nil,
                            hasTime: binding(\.hasDue).wrappedValue && binding(\.hasDueTime).wrappedValue,
                            time: binding(\.dueTime).wrappedValue
                        )
                    )
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

                VStack(alignment: .leading, spacing: 6) {
                    Text("Metadata")
                        .font(.headline)
                    detailRow("Source", value: binding(\.source).wrappedValue)
                    detailRow("Created", value: DateCoding.encode(binding(\.createdAt).wrappedValue))
                    if let modified = binding(\.modifiedAt).wrappedValue {
                        detailRow("Modified", value: DateCoding.encode(modified))
                    }
                    if let completed = binding(\.completedAt).wrappedValue {
                        detailRow("Completed", value: DateCoding.encode(completed))
                    }
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
                TextField("Title", text: binding(\.title), axis: .vertical)
                    .font(.title2.weight(.semibold))
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
                            }
                        }
                    )
                )
                if binding(\.hasDue).wrappedValue {
                    DatePicker("Due date", selection: binding(\.dueDate), displayedComponents: .date)
                    Toggle("Specific due time", isOn: binding(\.hasDueTime))
                    if binding(\.hasDueTime).wrappedValue {
                        DatePicker("Due time", selection: binding(\.dueTime), displayedComponents: .hourAndMinute)
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
                    TextField("Longitude", text: binding(\.locationLongitude))
                        .keyboardType(.decimalPad)
                        .textInputAutocapitalization(.never)

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
                                .background(Capsule().fill(Color.secondary.opacity(0.2)))
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

            Section("Recurrence") {
                Picker("Pattern", selection: $recurrenceFrequency) {
                    ForEach(RecurrenceFrequencyOption.allCases, id: \.self) { option in
                        Text(option.rawValue.capitalized).tag(option)
                    }
                }

                if recurrenceFrequency != .none {
                    Stepper("Every \(recurrenceInterval)", value: $recurrenceInterval, in: 1...365)

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

                Button("Apply Pattern") {
                    applyRecurrenceBuilder()
                }
                .disabled(recurrenceFrequency == .weekly && recurrenceWeekdays.isEmpty)

                TextField("Recurrence RRULE", text: binding(\.recurrence))
                    .textInputAutocapitalization(.never)
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
                LabeledContent("Source", value: binding(\.source).wrappedValue)
                LabeledContent("Created", value: DateCoding.encode(binding(\.createdAt).wrappedValue))
                if let modified = binding(\.modifiedAt).wrappedValue {
                    LabeledContent("Modified", value: DateCoding.encode(modified))
                }
                if let completed = binding(\.completedAt).wrappedValue {
                    LabeledContent("Completed", value: DateCoding.encode(completed))
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
            fields.append("BYDAY=\(recurrenceWeekdays.sorted().joined(separator: ","))")
        }

        binding(\.recurrence).wrappedValue = fields.joined(separator: ";")
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
            .background(Capsule().fill(Color.secondary.opacity(0.18)))
    }

    private func dateText(_ value: Date?) -> String {
        guard let value else { return "" }
        return value.formatted(date: .abbreviated, time: .omitted)
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
