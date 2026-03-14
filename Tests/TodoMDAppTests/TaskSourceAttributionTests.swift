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
}
