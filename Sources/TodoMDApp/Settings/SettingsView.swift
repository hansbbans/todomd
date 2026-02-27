import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var container: AppContainer

    @AppStorage("settings_notification_hour") private var notificationHour = 9
    @AppStorage("settings_notification_minute") private var notificationMinute = 0
    @AppStorage("settings_persistent_reminders_enabled") private var persistentRemindersEnabled = false
    @AppStorage("settings_persistent_reminder_interval_minutes") private var persistentReminderIntervalMinutes = 1
    @AppStorage("settings_google_calendar_enabled") private var googleCalendarEnabled = true
    @AppStorage("settings_appearance_mode") private var appearanceMode = "system"
    @AppStorage("settings_archive_completed") private var archiveCompleted = false
    @AppStorage("settings_completed_retention") private var completedRetention = "forever"
    @AppStorage("settings_default_priority") private var defaultPriority = TaskPriority.none.rawValue
    @AppStorage("settings_quick_entry_default_view") private var quickEntryDefaultView = BuiltInView.inbox.rawValue
    @AppStorage("settings_icloud_folder_name") private var iCloudFolderName = "todo.md"
    @State private var selectedFolderPath = UserDefaults.standard.string(forKey: TaskFolderPreferences.selectedFolderPathKey)
    @State private var showingFolderPicker = false
    @State private var folderSelectionErrorMessage: String?

    var body: some View {
        Form {
            Section("Calendar") {
                Toggle("Enable Google Calendar", isOn: $googleCalendarEnabled)

                if googleCalendarEnabled {
                    Text("Sign in with your Google account to sync events.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if container.isCalendarConnected {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }

                    Button(container.isCalendarConnected ? "Reconnect Google Calendar" : "Connect Google Calendar") {
                        Task {
                            await container.connectGoogleCalendar()
                        }
                    }
                    .disabled(container.isCalendarSyncing || !container.isGoogleCalendarConfigured)

                    Button("Refresh Calendar") {
                        Task {
                            await container.refreshCalendar(force: true)
                        }
                    }
                    .disabled(container.isCalendarSyncing || !container.isCalendarConnected)

                    if container.isCalendarConnected {
                        Button("Disconnect Calendar", role: .destructive) {
                            container.disconnectGoogleCalendar()
                        }
                    }

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

                    if !container.isGoogleCalendarConfigured {
                        Text("This app build is missing Google OAuth configuration.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Appearance") {
                Picker("Color mode", selection: $appearanceMode) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            }

            Section("Notifications") {
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

                if persistentRemindersEnabled {
                    Stepper(value: $persistentReminderIntervalMinutes, in: 1...240, step: 1) {
                        Text("Reminder interval: \(persistentReminderIntervalMinutes) minute\(persistentReminderIntervalMinutes == 1 ? "" : "s")")
                    }

                    Text("Persistent reminders follow system Focus mode behavior.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Task Behavior") {
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
            }

            Section("Storage") {
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

            Section("Maintenance") {
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
        .onChange(of: googleCalendarEnabled) { _, _ in
            Task {
                await container.refreshCalendar(force: true)
            }
        }
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
}
