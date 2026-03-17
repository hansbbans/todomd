import SwiftUI
import UniformTypeIdentifiers
#if canImport(UserNotifications)
    @preconcurrency import UserNotifications
#endif

private enum SettingsSection: String, CaseIterable, Identifiable {
    case integrations
    case appearance
    case notifications
    case taskBehavior
    case storage
    case maintenance

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .integrations:
            "Integrations"
        case .appearance:
            "Appearance"
        case .notifications:
            "Notifications"
        case .taskBehavior:
            "Task Behavior"
        case .storage:
            "Storage"
        case .maintenance:
            "Maintenance"
        }
    }

    var systemImage: String {
        switch self {
        case .integrations:
            "square.3.layers.3d"
        case .appearance:
            "paintpalette"
        case .notifications:
            "bell.badge"
        case .taskBehavior:
            "checkmark.circle"
        case .storage:
            "externaldrive"
        case .maintenance:
            "wrench.and.screwdriver"
        }
    }
}

private enum IntegrationAccessPrimer: String, Identifiable {
    case reminders
    case calendar

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .reminders:
            "Allow Reminders Access"
        case .calendar:
            "Allow Calendar Access"
        }
    }

    var message: String {
        switch self {
        case .reminders:
            "Allow Reminders access to import tasks from Reminders."
        case .calendar:
            "Allow Calendar access to show calendar events alongside your tasks."
        }
    }

    var continueTitle: String {
        "Continue"
    }
}

struct SettingsView: View {
    @Bindable var quickFindStore: QuickFindStore   // injected from RootView

    @EnvironmentObject private var container: AppContainer

    @AppStorage("settings_notification_hour") private var notificationHour = 9
    @AppStorage("settings_notification_minute") private var notificationMinute = 0
    @AppStorage("settings_notify_auto_unblocked") private var notifyAutoUnblocked = true
    @AppStorage("settings_notify_agent_created_tasks") private var notifyAgentCreatedTasks = true
    @AppStorage("settings_persistent_reminders_enabled") private var persistentRemindersEnabled = false
    @AppStorage("settings_persistent_reminder_interval_minutes") private var persistentReminderIntervalMinutes = 1
    @AppStorage("settings_reminders_import_enabled") private var remindersImportEnabled = false
    @AppStorage("settings_google_calendar_enabled") private var calendarEnabled = false
    @AppStorage("settings_appearance_mode") private var appearanceMode = "system"
    @AppStorage("settings_archive_completed") private var archiveCompleted = false
    @AppStorage("settings_completed_retention") private var completedRetention = "forever"
    @AppStorage("settings_default_priority") private var defaultPriority = TaskPriority.none.rawValue
    @AppStorage(CompactTabSettings.leadingViewKey) private var compactPrimaryTabRawValue = CompactTabSettings
        .defaultLeadingView.rawValue
    @AppStorage(CompactTabSettings.trailingViewKey) private var compactSecondaryTabRawValue = CompactTabSettings
        .defaultTrailingView.rawValue
    @AppStorage("settings_quick_entry_default_view") private var quickEntryDefaultView = BuiltInView.inbox.rawValue
    @AppStorage(QuickEntrySettings.fieldsKey) private var quickEntryFieldsRawValue = QuickEntrySettings
        .defaultFieldsRawValue
    @AppStorage(QuickEntrySettings.defaultDateModeKey) private var quickEntryDefaultDateModeRawValue =
        QuickEntryDefaultDateMode.none.rawValue
    @AppStorage(ExpandedTaskSettings.actionsKey) private var expandedTaskActionsRawValue = ExpandedTaskSettings
        .defaultActionsRawValue
    @AppStorage("settings_pomodoro_enabled") private var pomodoroEnabled = false
    @AppStorage(
        TaskFolderPreferences.legacyFolderNameKey,
        store: TaskFolderPreferences.shared
    ) private var iCloudFolderName = "todo.md"
    @State private var selectedFolderPath = TaskFolderPreferences.shared
        .string(forKey: TaskFolderPreferences.selectedFolderPathKey)
    @State private var showingFolderPicker = false
    @State private var folderSelectionErrorMessage: String?
    @State private var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var pendingAccessPrimer: IntegrationAccessPrimer?

    var body: some View {
        List {
            NavigationLink {
                integrationsSettingsView
            } label: {
                Label(SettingsSection.integrations.title, systemImage: SettingsSection.integrations.systemImage)
            }
            .accessibilityIdentifier("settings.section.\(SettingsSection.integrations.rawValue)")

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
            Section("Reminders") {
                Toggle("Reminders", isOn: remindersToggleBinding)
                    .accessibilityIdentifier("settings.integrations.remindersToggle")

                Text("Allow access to Apple Reminders so todo.md can import your reminder tasks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if container.isRemindersAccessGranted {
                    Label("Reminders Access Granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if container.remindersAccessRequiresSettingsRedirect {
                    Label("Reminders access is disabled", systemImage: "checkmark.circle.badge.xmark")
                        .foregroundStyle(.orange)

#if canImport(UIKit)
                    Button("Open iOS Settings") {
                        openIOSSettings()
                    }
                    .buttonStyle(.borderedProminent)
#endif
                } else if container.remindersAccessNeedsExplanationBeforeRequest {
                    Button("Allow Reminders Access") {
                        pendingAccessPrimer = .reminders
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(container.isRemindersImportBusy)
                    .accessibilityIdentifier("settings.integrations.allowRemindersAccessButton")
                }
            }

            Section("Calendar") {
                Toggle("Calendar", isOn: calendarToggleBinding)
                    .accessibilityIdentifier("settings.integrations.calendarToggle")

                Text("Allow access to Apple Calendar to show calendar events alongside your tasks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if container.isCalendarConnected {
                    Label("Calendar Access Granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if container.calendarAccessRequiresSettingsRedirect {
                    Label("Calendar access is disabled", systemImage: "calendar.badge.exclamationmark")
                        .foregroundStyle(.orange)

#if canImport(UIKit)
                    Button("Open iOS Settings") {
                        openIOSSettings()
                    }
                    .buttonStyle(.borderedProminent)
#endif
                } else if container.calendarAccessNeedsExplanationBeforeRequest {
                    Button("Allow Calendar Access") {
                        pendingAccessPrimer = .calendar
                    }
                    .accessibilityIdentifier("settings.integrations.allowCalendarAccessButton")
                    .disabled(container.isCalendarSyncing)
                }

                if calendarEnabled {
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
                       !calendarStatusMessage.isEmpty
                    {
                        Text(calendarStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
                await container.handleRemindersIntegrationChange()
            }
        }
        .onChange(of: calendarEnabled) { _, _ in
            Task {
                await container.refreshCalendar(force: true)
            }
        }
        .alert(item: $pendingAccessPrimer) { primer in
            Alert(
                title: Text(primer.title),
                message: Text(primer.message),
                primaryButton: .default(Text(primer.continueTitle)) {
                    handlePermissionPrimerConfirmation(primer)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var remindersToggleBinding: Binding<Bool> {
        Binding(
            get: { remindersImportEnabled },
            set: { isOn in
                guard isOn != remindersImportEnabled else { return }

                if isOn {
                    guard container.isRemindersAccessGranted else {
                        if container.remindersAccessNeedsExplanationBeforeRequest {
                            pendingAccessPrimer = .reminders
                        }
                        return
                    }
                }

                remindersImportEnabled = isOn
            }
        )
    }

    private var calendarToggleBinding: Binding<Bool> {
        Binding(
            get: { calendarEnabled },
            set: { isOn in
                guard isOn != calendarEnabled else { return }

                if isOn {
                    guard container.isCalendarConnected else {
                        if container.calendarAccessNeedsExplanationBeforeRequest {
                            pendingAccessPrimer = .calendar
                        }
                        return
                    }
                }

                calendarEnabled = isOn
            }
        )
    }

    private var pomodoroToggleBinding: Binding<Bool> {
        Binding(
            get: { pomodoroEnabled },
            set: { isOn in
                guard isOn != pomodoroEnabled else { return }

                pomodoroEnabled = isOn

                let normalized = CompactTabSettings.normalizedCustomViews(
                    leadingRawValue: compactPrimaryTabRawValue,
                    trailingRawValue: compactSecondaryTabRawValue,
                    pomodoroEnabled: isOn,
                    additionalViews: compactPerspectiveViews
                )
                compactPrimaryTabRawValue = normalized.primary.rawValue
                compactSecondaryTabRawValue = normalized.secondary.rawValue
            }
        )
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
                    ForEach(compactPrimaryTabChoices) { choice in
                        CompactTabChoiceLabel(choice: choice)
                            .tag(choice.view.rawValue)
                    }
                }
                .accessibilityIdentifier("settings.appearance.compactPrimaryTabPicker")

                Picker("Fifth tab", selection: compactSecondaryTabBinding) {
                    ForEach(compactSecondaryTabChoices) { choice in
                        CompactTabChoiceLabel(choice: choice)
                            .tag(choice.view.rawValue)
                    }
                }
                .accessibilityIdentifier("settings.appearance.compactSecondaryTabPicker")

                Text(
                    "Inbox, Today, and Areas stay pinned in slots 1-3. Choose which two extra lists appear in slots 4 and 5 on the iPhone tab bar."
                )
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
                            Text(
                                "You won't receive any reminders until you enable notifications for todo.md in iOS Settings."
                            )
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
                            Text(
                                "Open the app and add a task with a due date to trigger the notification permission prompt."
                            )
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
                    .accessibilityIdentifier("settings.notifications.persistentRemindersToggle")
                Toggle("Notify when agents create tasks", isOn: $notifyAgentCreatedTasks)
                    .accessibilityIdentifier("settings.notifications.agentCreatedTasksToggle")
                Toggle("Notify when blocked tasks are unblocked", isOn: $notifyAutoUnblocked)
                    .accessibilityIdentifier("settings.notifications.autoUnblockedToggle")

                if persistentRemindersEnabled {
                    Stepper(value: $persistentReminderIntervalMinutes, in: 1 ... 240, step: 1) {
                        Text(
                            "Reminder interval: \(persistentReminderIntervalMinutes) minute\(persistentReminderIntervalMinutes == 1 ? "" : "s")"
                        )
                    }

                    Text("Persistent reminders follow system Focus mode behavior.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Tasks you create in the app, via Shortcuts, voice ramble, or Reminders import won't trigger this alert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(SettingsSection.notifications.title)
        #if canImport(UserNotifications)
            .task {
                await refreshNotificationAuthorizationStatus()
            }
            #if canImport(UIKit)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task {
                    await refreshNotificationAuthorizationStatus()
                }
            }
            #endif
        #endif
    }

    #if canImport(UserNotifications)
        @MainActor
        private func refreshNotificationAuthorizationStatus() async {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationAuthorizationStatus = settings.authorizationStatus
        }
    #endif

    private var taskBehaviorSettingsView: some View {
        Form {
            Section("Quick Find") {
                Toggle("Include tasks in recents", isOn: $quickFindStore.recordTasks)
            }

            Section("Scheduling") {
                DatePicker(
                    "Evening starts at",
                    selection: Binding(
                        get: { container.eveningStartDate },
                        set: { container.eveningStartDate = $0 }
                    ),
                    displayedComponents: .hourAndMinute
                )
            }

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

                Toggle("Enable Pomodoro view", isOn: pomodoroToggleBinding)
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

                Text("Pomodoro appears in Browse on compact screens and in the sidebar on larger layouts.")
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
        case let .success(urls):
            guard let selectedURL = urls.first else { return }
            do {
                try TaskFolderPreferences.saveSelectedFolder(selectedURL)
                selectedFolderPath = selectedURL.path
                container.reloadStorageLocation()
            } catch {
                folderSelectionErrorMessage = error.localizedDescription
            }
        case let .failure(error):
            folderSelectionErrorMessage = error.localizedDescription
        }
    }

    private var compactPerspectiveViews: [ViewIdentifier] {
        container.perspectives.map { container.perspectiveViewIdentifier(for: $0.id) }
    }

    private var compactAvailableTabChoices: [CompactTabChoice] {
        CompactTabChoiceCatalog.availableViews(
            pomodoroEnabled: pomodoroEnabled,
            perspectives: container.perspectives
        )
        .map { CompactTabChoiceCatalog.choice(for: $0, perspectives: container.perspectives) }
    }

    private var compactCustomTabSelection: (primary: ViewIdentifier, secondary: ViewIdentifier) {
        CompactTabSettings.normalizedCustomViews(
            leadingRawValue: compactPrimaryTabRawValue,
            trailingRawValue: compactSecondaryTabRawValue,
            pomodoroEnabled: pomodoroEnabled,
            additionalViews: compactPerspectiveViews
        )
    }

    private var compactPrimaryTabChoices: [CompactTabChoice] {
        let selection = compactCustomTabSelection
        return compactAvailableTabChoices
            .filter { $0.view == selection.primary || $0.view != selection.secondary }
    }

    private var compactSecondaryTabChoices: [CompactTabChoice] {
        let selection = compactCustomTabSelection
        return compactAvailableTabChoices
            .filter { $0.view == selection.secondary || $0.view != selection.primary }
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
                    pomodoroEnabled: pomodoroEnabled,
                    additionalViews: compactPerspectiveViews
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
                    pomodoroEnabled: pomodoroEnabled,
                    additionalViews: compactPerspectiveViews
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

private extension SettingsView {
    func handlePermissionPrimerConfirmation(_ primer: IntegrationAccessPrimer) {
        switch primer {
        case .reminders:
            Task {
                await MainActor.run {
                    remindersImportEnabled = true
                }
                let outcome = await container.requestRemindersAccess()
                await MainActor.run {
                    remindersImportEnabled = container.isRemindersAccessGranted
                    guard outcome == .needsCalendarAccessPrimer,
                          calendarEnabled,
                          container.calendarAccessNeedsExplanationBeforeRequest else {
                        return
                    }
                    pendingAccessPrimer = .calendar
                }
            }
        case .calendar:
            Task {
                await MainActor.run {
                    calendarEnabled = true
                }
                await container.connectCalendar()
                await MainActor.run {
                    calendarEnabled = container.isCalendarConnected
                }
            }
        }
    }

#if canImport(UIKit)
    func openIOSSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
#endif
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
