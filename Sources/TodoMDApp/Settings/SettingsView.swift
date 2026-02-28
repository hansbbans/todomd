import SwiftUI
import UniformTypeIdentifiers

private struct BottomNavigationOption: Identifiable, Hashable {
    let id: String
    let label: String
    let icon: String
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case calendar
    case remindersImport
    case appearance
    case notifications
    case taskBehavior
    case bottomNavigation
    case storage
    case maintenance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar:
            return "Calendar"
        case .remindersImport:
            return "Reminders Import"
        case .appearance:
            return "Appearance"
        case .notifications:
            return "Notifications"
        case .taskBehavior:
            return "Task Behavior"
        case .bottomNavigation:
            return "Bottom Navigation"
        case .storage:
            return "Storage"
        case .maintenance:
            return "Maintenance"
        }
    }

    var systemImage: String {
        switch self {
        case .calendar:
            return "calendar"
        case .remindersImport:
            return "checklist"
        case .appearance:
            return "paintpalette"
        case .notifications:
            return "bell.badge"
        case .taskBehavior:
            return "checkmark.circle"
        case .bottomNavigation:
            return "dock.rectangle"
        case .storage:
            return "externaldrive"
        case .maintenance:
            return "wrench.and.screwdriver"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var container: AppContainer

    @AppStorage("settings_notification_hour") private var notificationHour = 9
    @AppStorage("settings_notification_minute") private var notificationMinute = 0
    @AppStorage("settings_notify_auto_unblocked") private var notifyAutoUnblocked = true
    @AppStorage("settings_persistent_reminders_enabled") private var persistentRemindersEnabled = false
    @AppStorage("settings_persistent_reminder_interval_minutes") private var persistentReminderIntervalMinutes = 1
    @AppStorage("settings_google_calendar_enabled") private var calendarEnabled = true
    @AppStorage("settings_appearance_mode") private var appearanceMode = "system"
    @AppStorage("settings_archive_completed") private var archiveCompleted = false
    @AppStorage("settings_completed_retention") private var completedRetention = "forever"
    @AppStorage("settings_default_priority") private var defaultPriority = TaskPriority.none.rawValue
    @AppStorage("settings_quick_entry_default_view") private var quickEntryDefaultView = BuiltInView.inbox.rawValue
    @AppStorage(QuickEntrySettings.fieldsKey) private var quickEntryFieldsRawValue = QuickEntrySettings.defaultFieldsRawValue
    @AppStorage(QuickEntrySettings.defaultDateModeKey) private var quickEntryDefaultDateModeRawValue = QuickEntryDefaultDateMode.today.rawValue
    @AppStorage(BottomNavigationSettings.sectionsKey) private var bottomNavigationSectionsRawValue = BottomNavigationSettings.defaultSectionsRawValue
    @AppStorage("settings_icloud_folder_name") private var iCloudFolderName = "todo.md"
    @State private var selectedFolderPath = UserDefaults.standard.string(forKey: TaskFolderPreferences.selectedFolderPathKey)
    @State private var showingFolderPicker = false
    @State private var folderSelectionErrorMessage: String?

    var body: some View {
        List {
            NavigationLink {
                calendarSettingsView
            } label: {
                Label(SettingsSection.calendar.title, systemImage: SettingsSection.calendar.systemImage)
            }
            .accessibilityIdentifier("settings.section.\(SettingsSection.calendar.rawValue)")

            NavigationLink {
                remindersImportSettingsView
            } label: {
                Label(SettingsSection.remindersImport.title, systemImage: SettingsSection.remindersImport.systemImage)
            }
            .accessibilityIdentifier("settings.section.\(SettingsSection.remindersImport.rawValue)")

            NavigationLink {
                appearanceSettingsView
            } label: {
                Label(SettingsSection.appearance.title, systemImage: SettingsSection.appearance.systemImage)
            }
            .accessibilityIdentifier("settings.section.\(SettingsSection.appearance.rawValue)")

            NavigationLink {
                notificationsSettingsView
            } label: {
                Label(SettingsSection.notifications.title, systemImage: SettingsSection.notifications.systemImage)
            }
            .accessibilityIdentifier("settings.section.\(SettingsSection.notifications.rawValue)")

            NavigationLink {
                taskBehaviorSettingsView
            } label: {
                Label(SettingsSection.taskBehavior.title, systemImage: SettingsSection.taskBehavior.systemImage)
            }
            .accessibilityIdentifier("settings.section.\(SettingsSection.taskBehavior.rawValue)")

            NavigationLink {
                bottomNavigationSettingsView
            } label: {
                Label(SettingsSection.bottomNavigation.title, systemImage: SettingsSection.bottomNavigation.systemImage)
            }
            .accessibilityIdentifier("settings.section.\(SettingsSection.bottomNavigation.rawValue)")

            NavigationLink {
                storageSettingsView
            } label: {
                Label(SettingsSection.storage.title, systemImage: SettingsSection.storage.systemImage)
            }
            .accessibilityIdentifier("settings.section.\(SettingsSection.storage.rawValue)")

            NavigationLink {
                maintenanceSettingsView
            } label: {
                Label(SettingsSection.maintenance.title, systemImage: SettingsSection.maintenance.systemImage)
            }
            .accessibilityIdentifier("settings.section.\(SettingsSection.maintenance.rawValue)")
        }
        .navigationTitle("Settings")
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderSelection(result: result)
        }
        .alert(
            "Folder Selection Error",
            isPresented: Binding(
                get: { folderSelectionErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        folderSelectionErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                folderSelectionErrorMessage = nil
            }
        } message: {
            Text(folderSelectionErrorMessage ?? "")
        }
    }

    private var calendarSettingsView: some View {
        Form {
            Section {
                Toggle("Show Calendar Events", isOn: $calendarEnabled)

                if calendarEnabled {
                    Text("Allow access to Apple Calendar to view events in Today and Upcoming.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if container.isCalendarConnected {
                        Label("Calendar Access Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }

                    if !container.isCalendarConnected {
                        Button("Allow Calendar Access") {
                            Task {
                                await container.connectCalendar()
                            }
                        }
                        .disabled(container.isCalendarSyncing)
                    }

                    Button("Refresh Calendar") {
                        Task {
                            await container.refreshCalendar(force: true)
                        }
                    }
                    .disabled(container.isCalendarSyncing || !container.isCalendarConnected)

                    if container.isCalendarConnected, !container.calendarSources.isEmpty {
                        Button("Select All Calendars") {
                            container.selectAllCalendarSources()
                        }

                        ForEach(container.calendarSources) { source in
                            Toggle(
                                isOn: Binding(
                                    get: { container.isCalendarSourceSelected(source.id) },
                                    set: { isOn in
                                        container.setCalendarSourceSelected(sourceID: source.id, isSelected: isOn)
                                    }
                                )
                            ) {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(color(for: source.colorHex))
                                        .frame(width: 10, height: 10)
                                    Text(source.name)
                                }
                            }
                        }
                    }

                    if let calendarStatusMessage = container.calendarStatusMessage,
                       !calendarStatusMessage.isEmpty {
                        Text(calendarStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(SettingsSection.calendar.title)
        .onChange(of: calendarEnabled) { _, _ in
            Task {
                await container.refreshCalendar(force: true)
            }
        }
    }

    private var remindersImportSettingsView: some View {
        Form {
            Section {
                Text(
                    "Import incomplete reminders using natural-language parsing, then delete them from Reminders."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if container.reminderLists.isEmpty {
                    Text("No Reminders lists available. Tap Refresh Lists to load them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Import from list", selection: reminderListSelection) {
                        Text("All Lists").tag("")
                        ForEach(container.reminderLists) { list in
                            Text(list.displayName).tag(list.id)
                        }
                    }
                    .accessibilityIdentifier("settings.remindersImport.listPicker")
                    .disabled(container.isRemindersImporting)
                }

                Button("Refresh Lists") {
                    Task {
                        await container.refreshReminderLists()
                    }
                }
                .accessibilityIdentifier("settings.remindersImport.refreshListsButton")
                .disabled(container.isRemindersImporting)

                Button(container.isRemindersImporting ? "Importing..." : "Import Now") {
                    Task {
                        await container.importFromReminders()
                    }
                }
                .accessibilityIdentifier("settings.remindersImport.importButton")
                .disabled(container.isRemindersImporting || container.reminderLists.isEmpty)

                if let remindersImportStatusMessage = container.remindersImportStatusMessage,
                   !remindersImportStatusMessage.isEmpty {
                    Text(remindersImportStatusMessage)
                        .accessibilityIdentifier("settings.remindersImport.status")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(SettingsSection.remindersImport.title)
        .task {
            await container.refreshReminderListsIfNeeded()
        }
    }

    private var appearanceSettingsView: some View {
        Form {
            Section {
                Picker("Color mode", selection: $appearanceMode) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            }
        }
        .navigationTitle(SettingsSection.appearance.title)
    }

    private var notificationsSettingsView: some View {
        Form {
            Section {
                DatePicker(
                    "Default time",
                    selection: Binding(
                        get: {
                            var components = DateComponents()
                            components.hour = notificationHour
                            components.minute = notificationMinute
                            return Calendar.current.date(from: components) ?? Date()
                        },
                        set: { date in
                            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                            notificationHour = components.hour ?? 9
                            notificationMinute = components.minute ?? 0
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )

                Toggle("Persistent reminders", isOn: $persistentRemindersEnabled)
                Toggle("Notify when blocked tasks are unblocked", isOn: $notifyAutoUnblocked)

                if persistentRemindersEnabled {
                    Stepper(value: $persistentReminderIntervalMinutes, in: 1...240, step: 1) {
                        Text("Reminder interval: \(persistentReminderIntervalMinutes) minute\(persistentReminderIntervalMinutes == 1 ? "" : "s")")
                    }

                    Text("Persistent reminders follow system Focus mode behavior.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(SettingsSection.notifications.title)
    }

    private var taskBehaviorSettingsView: some View {
        Form {
            Section {
                Toggle("Archive completed", isOn: $archiveCompleted)

                Picker("Completed retention", selection: $completedRetention) {
                    Text("Forever").tag("forever")
                    Text("7 days").tag("7d")
                    Text("30 days").tag("30d")
                }

                Picker("Default priority", selection: $defaultPriority) {
                    Text("None").tag(TaskPriority.none.rawValue)
                    Text("Low").tag(TaskPriority.low.rawValue)
                    Text("Medium").tag(TaskPriority.medium.rawValue)
                    Text("High").tag(TaskPriority.high.rawValue)
                }

                Picker("Quick entry default view", selection: $quickEntryDefaultView) {
                    Text("Inbox").tag(BuiltInView.inbox.rawValue)
                    Text("Today").tag(BuiltInView.today.rawValue)
                    Text("Anytime").tag(BuiltInView.anytime.rawValue)
                }

                Picker("Quick entry default date", selection: $quickEntryDefaultDateModeRawValue) {
                    ForEach(QuickEntryDefaultDateMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Quick entry visible fields")
                        .font(.subheadline.weight(.semibold))

                    ForEach(QuickEntryField.allCases, id: \.self) { field in
                        Toggle(field.title, isOn: quickEntryFieldBinding(field))
                    }
                }

                if !selectedQuickEntryFields.isEmpty {
                    Text("Quick entry field order (drag to reorder)")
                        .font(.subheadline.weight(.semibold))

                    ForEach(selectedQuickEntryFields, id: \.self) { field in
                        Label(field.title, systemImage: field.systemImage)
                    }
                    .onMove(perform: moveQuickEntryFields)
                }
            }
        }
        .navigationTitle(SettingsSection.taskBehavior.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
    }

    private var bottomNavigationSettingsView: some View {
        Form {
            Section {
                Text("Configure 0 to 5 bottom sections for compact screens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if bottomNavigationSections.isEmpty {
                    Text("No bottom sections configured.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(bottomNavigationSections) { section in
                        let sectionNumber = (bottomNavigationSections.firstIndex(where: { $0.id == section.id }) ?? 0) + 1
                        Picker("Section \(sectionNumber)", selection: bottomNavigationSectionBinding(section.id)) {
                            ForEach(bottomNavigationOptions) { option in
                                Label(option.label, systemImage: option.icon)
                                    .tag(option.id)
                            }

                            if !bottomNavigationOptions.contains(where: { $0.id == section.viewRawValue }) {
                                Text("Unavailable (\(section.viewRawValue))")
                                    .tag(section.viewRawValue)
                            }
                        }
                    }
                    .onMove(perform: moveBottomNavigationSections)
                    .onDelete(perform: deleteBottomNavigationSections)
                }

                HStack {
                    Button("Add Section") {
                        addBottomNavigationSection()
                    }
                    .disabled(bottomNavigationSections.count >= BottomNavigationSettings.maxSections)

                    Spacer()

                    Text("\(bottomNavigationSections.count)/\(BottomNavigationSettings.maxSections)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !bottomNavigationSections.isEmpty {
                    Button("Remove All Sections", role: .destructive) {
                        bottomNavigationSectionsRawValue = BottomNavigationSettings.encodeSections([])
                    }
                }
            }
        }
        .navigationTitle(SettingsSection.bottomNavigation.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
    }

    private var storageSettingsView: some View {
        Form {
            Section {
                TextField("Default iCloud folder name", text: $iCloudFolderName)
                    .textInputAutocapitalization(.never)

                LabeledContent("Selected folder") {
                    Text(selectedFolderPath ?? "Automatic (\(iCloudFolderName))")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(selectedFolderPath == nil ? .secondary : .primary)
                }

                Button("Choose Folder…") {
                    showingFolderPicker = true
                }

                if selectedFolderPath != nil {
                    Button("Use Default iCloud Folder", role: .destructive) {
                        TaskFolderPreferences.clearSelectedFolder()
                        selectedFolderPath = nil
                        container.reloadStorageLocation()
                    }
                }

                Text("Current resolved folder in this session: \(container.rootFolderPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Changing folder selection refreshes tasks immediately.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(SettingsSection.storage.title)
    }

    private var maintenanceSettingsView: some View {
        Form {
            Section {
                Button("Sync now") {
                    container.refresh()
                }

                Button("Rebuild local index") {
                    container.rebuildIndex()
                }

                NavigationLink("Perspectives") {
                    PerspectivesView()
                }

                NavigationLink("Conflict resolution") {
                    ConflictResolutionView()
                }

                NavigationLink("Unparseable files") {
                    UnparseableFilesView()
                }
            }
        }
        .navigationTitle(SettingsSection.maintenance.title)
    }

    private var reminderListSelection: Binding<String> {
        Binding(
            get: {
                container.selectedReminderListID ?? ""
            },
            set: { selectedID in
                container.setReminderListSelected(id: selectedID)
            }
        )
    }

    private var bottomNavigationSections: [BottomNavigationSection] {
        BottomNavigationSettings.decodeSections(bottomNavigationSectionsRawValue)
    }

    private var bottomNavigationOptions: [BottomNavigationOption] {
        var options: [BottomNavigationOption] = []
        var seen = Set<String>()

        func appendOption(view: ViewIdentifier, label: String, icon: String) {
            let rawValue = view.rawValue
            guard seen.insert(rawValue).inserted else { return }
            options.append(BottomNavigationOption(id: rawValue, label: label, icon: icon))
        }

        for builtIn in BuiltInView.allCases {
            let label: String
            let icon: String
            switch builtIn {
            case .inbox:
                label = "Inbox"
                icon = "tray"
            case .myTasks:
                label = "My Tasks"
                icon = "person"
            case .delegated:
                label = "Delegated"
                icon = "person.2"
            case .today:
                label = "Today"
                icon = "sun.max"
            case .upcoming:
                label = "Upcoming"
                icon = "calendar"
            case .anytime:
                label = "Anytime"
                icon = "list.bullet"
            case .someday:
                label = "Someday"
                icon = "clock"
            case .flagged:
                label = "Flagged"
                icon = "flag"
            }
            appendOption(view: .builtIn(builtIn), label: label, icon: icon)
        }

        for perspective in container.perspectives {
            appendOption(
                view: container.perspectiveViewIdentifier(for: perspective.id),
                label: "Perspective: \(perspective.name)",
                icon: perspective.icon
            )
        }

        for area in container.availableAreas() {
            appendOption(view: .area(area), label: "Area: \(area)", icon: "square.grid.2x2")
        }

        for project in container.allProjects() {
            appendOption(view: .project(project), label: "Project: \(project)", icon: "folder")
        }

        for tag in container.availableTags() {
            appendOption(view: .tag(tag), label: "Tag: #\(tag)", icon: "number")
        }

        return options
    }

    private func bottomNavigationSectionBinding(_ sectionID: String) -> Binding<String> {
        Binding(
            get: {
                bottomNavigationSections.first(where: { $0.id == sectionID })?.viewRawValue ?? BuiltInView.inbox.rawValue
            },
            set: { newRawValue in
                var sections = bottomNavigationSections
                guard let index = sections.firstIndex(where: { $0.id == sectionID }) else { return }
                sections[index].viewRawValue = newRawValue
                bottomNavigationSectionsRawValue = BottomNavigationSettings.encodeSections(sections)
            }
        )
    }

    private func addBottomNavigationSection() {
        var sections = bottomNavigationSections
        guard sections.count < BottomNavigationSettings.maxSections else { return }
        let existingViews = sections.map(\.viewIdentifier)
        sections.append(BottomNavigationSection(view: nextBottomNavigationView(existing: existingViews)))
        bottomNavigationSectionsRawValue = BottomNavigationSettings.encodeSections(sections)
    }

    private func moveBottomNavigationSections(from source: IndexSet, to destination: Int) {
        var sections = bottomNavigationSections
        sections.move(fromOffsets: source, toOffset: destination)
        bottomNavigationSectionsRawValue = BottomNavigationSettings.encodeSections(sections)
    }

    private func deleteBottomNavigationSections(at offsets: IndexSet) {
        var sections = bottomNavigationSections
        sections.remove(atOffsets: offsets)
        bottomNavigationSectionsRawValue = BottomNavigationSettings.encodeSections(sections)
    }

    private func nextBottomNavigationView(existing: [ViewIdentifier]) -> ViewIdentifier {
        let builtInCandidates: [ViewIdentifier] = [
            .builtIn(.inbox),
            .builtIn(.today),
            .builtIn(.upcoming),
            .builtIn(.anytime),
            .builtIn(.flagged),
            .builtIn(.someday)
        ]

        for candidate in builtInCandidates where !existing.contains(candidate) {
            return candidate
        }

        if let firstPerspective = container.perspectives.first {
            let perspectiveView = container.perspectiveViewIdentifier(for: firstPerspective.id)
            if !existing.contains(perspectiveView) {
                return perspectiveView
            }
        }

        return .builtIn(.inbox)
    }

    private func color(for hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        let red = Double((rgb & 0xFF0000) >> 16) / 255.0
        let green = Double((rgb & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgb & 0x0000FF) / 255.0
        return Color(red: red, green: green, blue: blue)
    }

    private func handleFolderSelection(result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls):
            guard let selectedURL = urls.first else { return }
            do {
                try TaskFolderPreferences.saveSelectedFolder(selectedURL)
                selectedFolderPath = selectedURL.path
                container.reloadStorageLocation()
            } catch {
                folderSelectionErrorMessage = error.localizedDescription
            }
        case .failure(let error):
            folderSelectionErrorMessage = error.localizedDescription
        }
    }

    private func quickEntryFieldBinding(_ field: QuickEntryField) -> Binding<Bool> {
        Binding(
            get: {
                selectedQuickEntryFields.contains(field)
            },
            set: { isOn in
                var fields = selectedQuickEntryFields
                if isOn {
                    if !fields.contains(field) {
                        fields.append(field)
                    }
                } else {
                    fields.removeAll { $0 == field }
                }
                quickEntryFieldsRawValue = QuickEntrySettings.encodeFields(fields)
            }
        )
    }

    private var selectedQuickEntryFields: [QuickEntryField] {
        QuickEntrySettings.decodeFields(quickEntryFieldsRawValue)
    }

    private func moveQuickEntryFields(from source: IndexSet, to destination: Int) {
        var fields = selectedQuickEntryFields
        fields.move(fromOffsets: source, toOffset: destination)
        quickEntryFieldsRawValue = QuickEntrySettings.encodeFields(fields)
    }
}
