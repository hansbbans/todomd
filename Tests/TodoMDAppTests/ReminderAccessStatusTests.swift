import EventKit
import Foundation
import Testing
@testable import TodoMDApp

struct ReminderAccessStatusTests {
    @Test("Undetermined reminders access needs an explanation until prompting is allowed")
    func notDeterminedAccessNeedsExplanationBeforePrompt() {
        #expect(ReminderAccessStatus.needsExplanationBeforeRequest(.notDetermined))
        #expect(
            ReminderAccessStatus.refreshAction(
                for: .notDetermined,
                allowsPermissionPrompt: false
            ) == .needsExplanationBeforeRequest
        )
        #expect(
            ReminderAccessStatus.refreshAction(
                for: .notDetermined,
                allowsPermissionPrompt: true
            ) == .canRefresh
        )
    }

    @Test("Granted reminders access can refresh immediately")
    func grantedAccessCanRefreshImmediately() {
        #expect(ReminderAccessStatus.refreshAction(for: .fullAccess, allowsPermissionPrompt: false) == .canRefresh)
        #expect(
            ReminderAccessStatus.refreshAction(
                for: legacyAuthorizedStatus,
                allowsPermissionPrompt: false
            ) == .canRefresh
        )
    }

    @Test("Denied and restricted reminders access require Settings")
    func deniedAndRestrictedAccessRequireSettingsRedirect() {
        #expect(ReminderAccessStatus.requiresSettingsRedirect(.denied))
        #expect(ReminderAccessStatus.requiresSettingsRedirect(.restricted))
        #expect(
            ReminderAccessStatus.refreshAction(
                for: .denied,
                allowsPermissionPrompt: true
            ) == .requiresSettingsRedirect
        )
        #expect(
            ReminderAccessStatus.refreshAction(
                for: .restricted,
                allowsPermissionPrompt: false
            ) == .requiresSettingsRedirect
        )
    }

    @Test("Missing stored integration flags stay off until access is granted")
    func missingStoredIntegrationFlagsDefaultOff() {
        #expect(IntegrationEnablementDefaults.resolvedStoredValue(nil, hasGrantedAccess: false) == false)
        #expect(IntegrationEnablementDefaults.resolvedStoredValue(nil, hasGrantedAccess: true))
    }

    @Test("Stored integration flags preserve the user's explicit choice")
    func storedIntegrationFlagsOverrideGrantedAccessFallback() {
        #expect(IntegrationEnablementDefaults.resolvedStoredValue(false, hasGrantedAccess: true) == false)
        #expect(IntegrationEnablementDefaults.resolvedStoredValue(true, hasGrantedAccess: false))
    }

    // Raw value 3 preserves the pre-iOS 17 granted state without pulling in the deprecated symbol.
    private var legacyAuthorizedStatus: EKAuthorizationStatus {
        EKAuthorizationStatus(rawValue: 3) ?? .denied
    }
}

@Suite(.serialized)
@MainActor
struct AppContainerReminderIntegrationSyncTests {
    @Test("Explicit reminders enablement updates refresh the reminders integration state")
    func explicitEnablementUpdatesRefreshRemindersState() async throws {
        let root = try makeTempDirectory()
        let defaults = UserDefaults.standard
        let enabledKey = "settings_reminders_import_enabled"
        let listKey = "settings_reminders_import_list_id"
        let originalEnabled = defaults.object(forKey: enabledKey)
        let originalList = defaults.object(forKey: listKey)
        let originalOverride = ProcessInfo.processInfo.environment["TODOMD_STORAGE_OVERRIDE_PATH"]
        let originalFakeReminders = ProcessInfo.processInfo.environment["TODOMD_FAKE_REMINDERS_IMPORT"]

        setenv("TODOMD_STORAGE_OVERRIDE_PATH", root.path, 1)
        setenv("TODOMD_FAKE_REMINDERS_IMPORT", "1", 1)
        defaults.removeObject(forKey: enabledKey)
        defaults.removeObject(forKey: listKey)

        defer {
            if let originalOverride {
                setenv("TODOMD_STORAGE_OVERRIDE_PATH", originalOverride, 1)
            } else {
                unsetenv("TODOMD_STORAGE_OVERRIDE_PATH")
            }

            if let originalFakeReminders {
                setenv("TODOMD_FAKE_REMINDERS_IMPORT", originalFakeReminders, 1)
            } else {
                unsetenv("TODOMD_FAKE_REMINDERS_IMPORT")
            }

            if let originalEnabled {
                defaults.set(originalEnabled, forKey: enabledKey)
            } else {
                defaults.removeObject(forKey: enabledKey)
            }

            if let originalList {
                defaults.set(originalList, forKey: listKey)
            } else {
                defaults.removeObject(forKey: listKey)
            }

            try? FileManager.default.removeItem(at: root)
        }

        let container = AppContainer()
        await container.setRemindersIntegrationEnabled(false)

        try await waitFor(
            "reminders integration to stay cleared while disabled"
        ) {
            container.reminderLists.isEmpty && container.pendingReminderImports.isEmpty
        }

        await container.setRemindersIntegrationEnabled(true)

        try await waitFor(
            "reminders integration to refresh after explicit enablement"
        ) {
            container.reminderLists.count == 1
                && container.selectedReminderListID == "ui-test-reminders-list"
                && container.pendingReminderImports.count == 1
        }
    }

    @Test("Stored reminders list selection survives launch and refresh")
    func storedReminderListSelectionSurvivesLaunchAndRefresh() async throws {
        let root = try makeTempDirectory()
        let defaults = UserDefaults.standard
        let enabledKey = "settings_reminders_import_enabled"
        let listKey = "settings_reminders_import_list_id"
        let originalEnabled = defaults.object(forKey: enabledKey)
        let originalList = defaults.object(forKey: listKey)
        let originalOverride = ProcessInfo.processInfo.environment["TODOMD_STORAGE_OVERRIDE_PATH"]
        let originalFakeReminders = ProcessInfo.processInfo.environment["TODOMD_FAKE_REMINDERS_IMPORT"]

        setenv("TODOMD_STORAGE_OVERRIDE_PATH", root.path, 1)
        setenv("TODOMD_FAKE_REMINDERS_IMPORT", "1", 1)
        defaults.set(true, forKey: enabledKey)
        defaults.set("ui-test-reminders-list", forKey: listKey)

        defer {
            if let originalOverride {
                setenv("TODOMD_STORAGE_OVERRIDE_PATH", originalOverride, 1)
            } else {
                unsetenv("TODOMD_STORAGE_OVERRIDE_PATH")
            }

            if let originalFakeReminders {
                setenv("TODOMD_FAKE_REMINDERS_IMPORT", originalFakeReminders, 1)
            } else {
                unsetenv("TODOMD_FAKE_REMINDERS_IMPORT")
            }

            if let originalEnabled {
                defaults.set(originalEnabled, forKey: enabledKey)
            } else {
                defaults.removeObject(forKey: enabledKey)
            }

            if let originalList {
                defaults.set(originalList, forKey: listKey)
            } else {
                defaults.removeObject(forKey: listKey)
            }

            try? FileManager.default.removeItem(at: root)
        }

        let container = AppContainer()

        try await waitFor(
            "stored reminders list selection to survive initial refresh"
        ) {
            container.selectedReminderListID == "ui-test-reminders-list"
                && container.pendingReminderImports.count == 1
        }

        await container.refreshReminderLists()

        #expect(container.selectedReminderListID == "ui-test-reminders-list")
        #expect(defaults.string(forKey: listKey) == "ui-test-reminders-list")
    }

    @Test("Explicitly cleared reminders list selection stays cleared across refresh and relaunch")
    func explicitlyClearedReminderListSelectionStaysCleared() async throws {
        let root = try makeTempDirectory()
        let defaults = UserDefaults.standard
        let enabledKey = "settings_reminders_import_enabled"
        let listKey = "settings_reminders_import_list_id"
        let originalEnabled = defaults.object(forKey: enabledKey)
        let originalList = defaults.object(forKey: listKey)
        let originalOverride = ProcessInfo.processInfo.environment["TODOMD_STORAGE_OVERRIDE_PATH"]
        let originalFakeReminders = ProcessInfo.processInfo.environment["TODOMD_FAKE_REMINDERS_IMPORT"]

        setenv("TODOMD_STORAGE_OVERRIDE_PATH", root.path, 1)
        setenv("TODOMD_FAKE_REMINDERS_IMPORT", "1", 1)
        defaults.set(true, forKey: enabledKey)
        defaults.removeObject(forKey: listKey)

        defer {
            if let originalOverride {
                setenv("TODOMD_STORAGE_OVERRIDE_PATH", originalOverride, 1)
            } else {
                unsetenv("TODOMD_STORAGE_OVERRIDE_PATH")
            }

            if let originalFakeReminders {
                setenv("TODOMD_FAKE_REMINDERS_IMPORT", originalFakeReminders, 1)
            } else {
                unsetenv("TODOMD_FAKE_REMINDERS_IMPORT")
            }

            if let originalEnabled {
                defaults.set(originalEnabled, forKey: enabledKey)
            } else {
                defaults.removeObject(forKey: enabledKey)
            }

            if let originalList {
                defaults.set(originalList, forKey: listKey)
            } else {
                defaults.removeObject(forKey: listKey)
            }

            try? FileManager.default.removeItem(at: root)
        }

        let container = AppContainer()

        try await waitFor(
            "default reminders list selection to appear before clearing"
        ) {
            container.selectedReminderListID == "ui-test-reminders-list"
                && container.pendingReminderImports.count == 1
        }

        container.setReminderListSelected(id: "")

        try await waitFor(
            "explicit reminders list clear to empty imports"
        ) {
            container.selectedReminderListID == nil
                && container.pendingReminderImports.isEmpty
        }

        await container.refreshReminderLists()

        #expect(container.selectedReminderListID == nil)
        #expect(container.pendingReminderImports.isEmpty)

        let reloadedContainer = AppContainer()

        try await waitFor(
            "explicitly cleared reminders selection to survive relaunch"
        ) {
            reloadedContainer.reminderLists.count == 1
                && reloadedContainer.selectedReminderListID == nil
                && reloadedContainer.pendingReminderImports.isEmpty
        }
    }

    @Test("Missing stored reminders list selection clears cleanly on refresh")
    func missingStoredReminderListSelectionClearsCleanly() async throws {
        let root = try makeTempDirectory()
        let defaults = UserDefaults.standard
        let enabledKey = "settings_reminders_import_enabled"
        let listKey = "settings_reminders_import_list_id"
        let originalEnabled = defaults.object(forKey: enabledKey)
        let originalList = defaults.object(forKey: listKey)
        let originalOverride = ProcessInfo.processInfo.environment["TODOMD_STORAGE_OVERRIDE_PATH"]
        let originalFakeReminders = ProcessInfo.processInfo.environment["TODOMD_FAKE_REMINDERS_IMPORT"]

        setenv("TODOMD_STORAGE_OVERRIDE_PATH", root.path, 1)
        setenv("TODOMD_FAKE_REMINDERS_IMPORT", "1", 1)
        defaults.set(true, forKey: enabledKey)
        defaults.set("missing-list", forKey: listKey)

        defer {
            if let originalOverride {
                setenv("TODOMD_STORAGE_OVERRIDE_PATH", originalOverride, 1)
            } else {
                unsetenv("TODOMD_STORAGE_OVERRIDE_PATH")
            }

            if let originalFakeReminders {
                setenv("TODOMD_FAKE_REMINDERS_IMPORT", originalFakeReminders, 1)
            } else {
                unsetenv("TODOMD_FAKE_REMINDERS_IMPORT")
            }

            if let originalEnabled {
                defaults.set(originalEnabled, forKey: enabledKey)
            } else {
                defaults.removeObject(forKey: enabledKey)
            }

            if let originalList {
                defaults.set(originalList, forKey: listKey)
            } else {
                defaults.removeObject(forKey: listKey)
            }

            try? FileManager.default.removeItem(at: root)
        }

        let container = AppContainer()

        try await waitFor(
            "missing reminders list selection to clear after refresh"
        ) {
            container.reminderLists.count == 1
                && container.selectedReminderListID == nil
        }

        #expect(defaults.string(forKey: listKey) == nil)
        #expect(container.pendingReminderImports.isEmpty)
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoMDReminderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func waitFor(
        _ description: String,
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        Issue.record("Timed out waiting for \(description)")
        throw TimeoutError()
    }
}

private struct TimeoutError: Error {}
