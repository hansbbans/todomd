import SwiftUI
import UniformTypeIdentifiers
#if canImport(UserNotifications)
import UserNotifications
#endif

private enum SettingsSection: String, CaseIterable, Identifiable {
    case integrations
    case calendar
    case appearance
    case notifications
    case taskBehavior
    case storage
    case maintenance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .integrations:
            return "Integrations"
        case .calendar:
            return "Calendar"
        case .appearance:
            return "Appearance"
        case .notifications:
            return "Notifications"
        case .taskBehavior:
            return "Task Behavior"
        case .storage:
            return "Storage"
        case .maintenance:
            return "Maintenance"
        }
    }

    var systemImage: String {
        switch self {
        case .integrations:
            return "square.3.layers.3d"
        case .calendar:
            return "calendar"
        case .appearance:
            return "paintpalette"
        case .notifications:
            return "bell.badge"
        case .taskBehavior:
            return "checkmark.circle"
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
    @AppStorage("settings_reminders_import_enabled") private var remindersImportEnabled = true
    @AppStorage("settings_google_calendar_enabled") private var calendarEnabled = true
    @AppStorage("settings_appearance_mode") private var appearanceMode = "system"
    @AppStorage("settings_archive_completed") private var archiveCompleted = false
    @AppStorage("settings_completed_retention") private var completedRetention = "forever"
    @AppStorage("settings_default_priority") private var defaultPriority = TaskPriority.none.rawValue
    @AppStorage(CompactTabSettings.leadingViewKey) private var compactPrimaryTabRawValue = CompactTabSettings.defaultLeadingView.rawValue
    @AppStorage(CompactTabSettings.trailingViewKey) private var compactSecondaryTabRawValue = CompactTabSettings.defaultTrailingView.rawValue
    @AppStorage("settings_quick_entry_default_view") private var quickEntryDefaultView = BuiltInView.inbox.rawValue
    @AppStorage(QuickEntrySettings.fieldsKey) private var quickEntryFieldsRawValue = QuickEntrySettings.defaultFieldsRawValue
    @AppStorage(QuickEntrySettings.defaultDateModeKey) private var quickEntryDefaultDateModeRawValue = QuickEntryDefaultDateMode.none.rawValue
    @AppStorage(ExpandedTaskSettings.actionsKey) private var expandedTaskActionsRawValue = ExpandedTaskSettings.defaultActionsRawValue
    @AppStorage("settings_pomodoro_enabled") private var pomodoroEnabled = false
    @AppStorage(TaskFolderPreferences.legacyFolderNameKey, store: TaskFolderPreferences.shared) private var iCloudFolderName = "todo.md"
    @State private var selectedFolderPath = TaskFolderPreferences.shared.string(forKey: TaskFolderPreferences.selectedFolderPathKey)
    @State private var showingFolderPicker = false
    @State private var folderSelectionErrorMessage: String?
    @State private var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        List {
            NavigationLink {
                integrationsSettingsView
            } label: {
                Label(SettingsSection.integrations.title, systemImage: SettingsSection.integrations.systemImage)
            }
            .accessibilityIdentifier("settings.section.\(SettingsSection.integrations.rawValue)")

            NavigationLink {
                calendarSettingsView
            } label: {
                Label(SettingsSection.calendar.title, systemImage: SettingsSection.calendar.systemImage)
            }
            .accessibilityIdentifier("settings.section.\(SettingsSection.calendar.rawValue)")

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

            Section {
                NavigationLink {
                    DebugView()
                } label: {
                    Label("Debug", systemImage: "ladybug")
                        .foregroundStyle(.secondary)
                }
            }
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

    private var integrationsSettingsView: some View {
        Form {
            Section {
                Toggle("Reminders", isOn: $remindersImportEnabled)
                    .accessibilityIdentifier("settings.integrations.remindersToggle")

                Toggle("Calendar", isOn: $calendarEnabled)
                    .accessibilityIdentifier("settings.integrations.calendarToggle")
            }

            Section {
                Text("Turn Apple Reminders and Apple Calendar features on or off for todo.md.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(SettingsSection.integrations.title)
        .onChange(of: remindersImportEnabled) { _, _ in
            Task {
                await container.refreshReminderLists()
            }
        }
        .onChange(of: calendarEnabled) { _, _ in
            Task {
                await container.refreshCalendar(force: true)
            }
        }
    }

    private var calendarSettingsView: some View {
        Form {
            Section {
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
                } else {
                    Text("Enable Calendar in Integrations to configure calendars and show events in Today and Upcoming.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(SettingsSection.calendar.title)
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

            Section("Compact Tab Bar") {
                Picker("Fourth tab", selection: compactPrimaryTabBinding) {
                    ForEach(compactPrimaryTabChoices, id: \.rawValue) { view in
                        Label(view.displayTitle, systemImage: view.displaySystemImage)
                            .tag(view.rawValue)
                    }
                }
                .accessibilityIdentifier("settings.appearance.compactPrimaryTabPicker")

                Picker("Fifth tab", selection: compactSecondaryTabBinding) {
                    ForEach(compactSecondaryTabChoices, id: \.rawValue) { view in
                        Label(view.displayTitle, systemImage: view.displaySystemImage)
                            .tag(view.rawValue)
                    }
                }
                .accessibilityIdentifier("settings.appearance.compactSecondaryTabPicker")

                Text("Inbox, Today, and Areas stay pinned in slots 1-3. Choose which two extra lists appear in slots 4 and 5 on the iPhone tab bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(SettingsSection.appearance.title)
    }

    private var notificationsSettingsView: some View {
        Form {
#if canImport(UserNotifications)
            if notificationAuthorizationStatus == .denied {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Notifications are disabled", systemImage: "bell.slash.fill")
                            .font(.headline)
                            .foregroundStyle(.red)
                        Text("You won't receive any reminders until you enable notifications for todo.md in iOS Settings.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        #if canImport(UIKit)
                        Button("Open iOS Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                        #endif
                    }
                    .padding(.vertical, 4)
                }
            } else if notificationAuthorizationStatus == .notDetermined {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Permission not yet granted", systemImage: "bell.badge.slash")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        Text("Open the app and add a task with a due date to trigger the notification permission prompt.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
#endif
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
#if canImport(UserNotifications)
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationAuthorizationStatus = settings.authorizationStatus
        }
        #if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                notificationAuthorizationStatus = settings.authorizationStatus
            }
        }
        #endif
#endif
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

                Toggle("Enable Pomodoro view", isOn: $pomodoroEnabled)
                    .accessibilityIdentifier("settings.taskBehavior.pomodoroToggle")

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

                VStack(alignment: .leading, spacing: 10) {
                    Text("Expanded task quick actions")
                        .font(.subheadline.weight(.semibold))

                    ForEach(ExpandedTaskQuickAction.allCases.filter { $0 != .more }, id: \.self) { action in
                        Toggle(action.title, isOn: expandedTaskActionBinding(action))
                    }

                    Text("The ... button always stays visible so the full task editor is one tap away.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !selectedExpandedTaskQuickActions.isEmpty {
                    Text("Expanded task action order (drag to reorder)")
                        .font(.subheadline.weight(.semibold))

                    ForEach(selectedExpandedTaskQuickActions, id: \.self) { action in
                        Label(action.title, systemImage: action.systemImage)
                    }
                    .onMove(perform: moveExpandedTaskActions)
                }

                Text("Pomodoro appears in Areas on compact screens and in the sidebar on larger layouts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(SettingsSection.taskBehavior.title)
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .appTrailingAction) {
                EditButton()
            }
            #endif
        }
    }

    private var storageSettingsView: some View {
        Form {
            Section {
                TextField("Default iCloud folder name", text: $iCloudFolderName)
                    .modifier(SettingsNoAutocapitalization())

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

    private var compactCustomTabSelection: (primary: BuiltInView, secondary: BuiltInView) {
        CompactTabSettings.normalizedCustomViews(
            leadingRawValue: compactPrimaryTabRawValue,
            trailingRawValue: compactSecondaryTabRawValue,
            pomodoroEnabled: pomodoroEnabled
        )
    }

    private var compactPrimaryTabChoices: [BuiltInView] {
        let selection = compactCustomTabSelection
        return CompactTabSettings.availableCustomViews(pomodoroEnabled: pomodoroEnabled)
            .filter { $0 == selection.primary || $0 != selection.secondary }
    }

    private var compactSecondaryTabChoices: [BuiltInView] {
        let selection = compactCustomTabSelection
        return CompactTabSettings.availableCustomViews(pomodoroEnabled: pomodoroEnabled)
            .filter { $0 == selection.secondary || $0 != selection.primary }
    }

    private var compactPrimaryTabBinding: Binding<String> {
        Binding(
            get: {
                compactCustomTabSelection.primary.rawValue
            },
            set: { newValue in
                let normalized = CompactTabSettings.normalizedCustomViews(
                    leadingRawValue: newValue,
                    trailingRawValue: compactSecondaryTabRawValue,
                    pomodoroEnabled: pomodoroEnabled
                )
                compactPrimaryTabRawValue = normalized.primary.rawValue
                compactSecondaryTabRawValue = normalized.secondary.rawValue
            }
        )
    }

    private var compactSecondaryTabBinding: Binding<String> {
        Binding(
            get: {
                compactCustomTabSelection.secondary.rawValue
            },
            set: { newValue in
                let normalized = CompactTabSettings.normalizedCustomViews(
                    leadingRawValue: compactPrimaryTabRawValue,
                    trailingRawValue: newValue,
                    pomodoroEnabled: pomodoroEnabled
                )
                compactPrimaryTabRawValue = normalized.primary.rawValue
                compactSecondaryTabRawValue = normalized.secondary.rawValue
            }
        )
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

    private func expandedTaskActionBinding(_ action: ExpandedTaskQuickAction) -> Binding<Bool> {
        Binding(
            get: {
                selectedExpandedTaskQuickActions.contains(action)
            },
            set: { isOn in
                var actions = selectedExpandedTaskQuickActions
                if isOn {
                    if !actions.contains(action) {
                        actions.append(action)
                    }
                } else {
                    actions.removeAll { $0 == action }
                }
                expandedTaskActionsRawValue = ExpandedTaskSettings.encodeActions(actions)
            }
        )
    }

    private var selectedExpandedTaskQuickActions: [ExpandedTaskQuickAction] {
        ExpandedTaskSettings
            .decodeActions(expandedTaskActionsRawValue)
            .filter { $0 != .more }
    }

    private func moveExpandedTaskActions(from source: IndexSet, to destination: Int) {
        var actions = selectedExpandedTaskQuickActions
        actions.move(fromOffsets: source, toOffset: destination)
        expandedTaskActionsRawValue = ExpandedTaskSettings.encodeActions(actions + [.more])
    }
}

private struct SettingsNoAutocapitalization: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.textInputAutocapitalization(.never)
        #else
        content
        #endif
    }
}
