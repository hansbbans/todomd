import Testing
@testable import TodoMDApp

struct TaskSourceAttributionTests {
    @Test("Agent-created task notifications ignore user-owned sources")
    func agentCreatedTaskNotificationsIgnoreUserOwnedSources() {
        #expect(TaskSourceAttribution.shouldNotifyForAgentCreatedTask(source: "user") == false)
        #expect(TaskSourceAttribution.shouldNotifyForAgentCreatedTask(source: "shortcut") == false)
        #expect(TaskSourceAttribution.shouldNotifyForAgentCreatedTask(source: "voice-ramble") == false)
        #expect(TaskSourceAttribution.shouldNotifyForAgentCreatedTask(source: "import-reminders") == false)
        #expect(TaskSourceAttribution.shouldNotifyForAgentCreatedTask(source: "unknown") == false)
        #expect(TaskSourceAttribution.shouldNotifyForAgentCreatedTask(source: nil) == false)
    }

    @Test("Agent-created task notifications include external creators")
    func agentCreatedTaskNotificationsIncludeExternalCreators() {
        #expect(TaskSourceAttribution.shouldNotifyForAgentCreatedTask(source: "claude-agent"))
        #expect(TaskSourceAttribution.shouldNotifyForAgentCreatedTask(source: "obsidian"))
        #expect(TaskSourceAttribution.shouldNotifyForAgentCreatedTask(source: " Claude-Agent "))
        #expect(TaskSourceAttribution.displayName(" Claude-Agent ") == "Claude-Agent")
    }

    @Test("Badges are hidden for user and unknown sources")
    func badgesHideUserAndUnknownSources() {
        #expect(TaskSourceAttribution.badge(for: nil) == nil)
        #expect(TaskSourceAttribution.badge(for: "") == nil)
        #expect(TaskSourceAttribution.badge(for: "user") == nil)
        #expect(TaskSourceAttribution.badge(for: "unknown") == nil)
    }

    @Test("Badges map known automation and import sources to compact labels")
    func badgesMapKnownSources() {
        #expect(
            TaskSourceAttribution.badge(for: "shortcut") ==
            .init(label: "Shortcut", systemImage: "bolt.fill", accessibilityLabel: "Source: shortcut")
        )
        #expect(
            TaskSourceAttribution.badge(for: "voice-ramble") ==
            .init(label: "Voice", systemImage: "waveform", accessibilityLabel: "Source: voice-ramble")
        )
        #expect(
            TaskSourceAttribution.badge(for: "import-reminders") ==
            .init(label: "Reminders", systemImage: "checklist", accessibilityLabel: "Source: import-reminders")
        )
        #expect(
            TaskSourceAttribution.badge(for: "inbox-drop") ==
            .init(label: "Inbox", systemImage: "tray.and.arrow.down.fill", accessibilityLabel: "Source: inbox-drop")
        )
    }

    @Test("Badges normalize external app and agent names")
    func badgesNormalizeExternalNames() {
        #expect(
            TaskSourceAttribution.badge(for: "obsidian") ==
            .init(label: "Obsidian", systemImage: "book.closed.fill", accessibilityLabel: "Source: obsidian")
        )
        #expect(
            TaskSourceAttribution.badge(for: " Claude-Agent ") ==
            .init(label: "Claude", systemImage: "sparkles", accessibilityLabel: "Source: Claude-Agent")
        )
        #expect(
            TaskSourceAttribution.badge(for: "calendar-sync") ==
            .init(label: "Calendar", systemImage: "calendar", accessibilityLabel: "Source: calendar-sync")
        )
    }

    @Test("Fallback badge labels stay compact for long external source names")
    func fallbackBadgeLabelsStayCompact() {
        #expect(
            TaskSourceAttribution.badge(for: "my-very-long-automation-name") ==
            .init(label: "My Very", systemImage: "arrow.down.circle", accessibilityLabel: "Source: my-very-long-automation-name")
        )
    }
}
