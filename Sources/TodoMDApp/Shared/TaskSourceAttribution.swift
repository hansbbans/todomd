import Foundation

enum TaskSourceAttribution {
    private static let selfOwnedSources: Set<String> = [
        "user",
        "shortcut",
        "voice-ramble",
        "import-reminders",
    ]

    static func normalized(_ source: String?) -> String? {
        guard let trimmed = source?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }

        return trimmed.lowercased()
    }

    static func displayName(_ source: String?) -> String? {
        guard let trimmed = source?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }

        return trimmed
    }

    static func shouldNotifyForAgentCreatedTask(source: String?) -> Bool {
        guard let normalized = normalized(source), normalized != "unknown" else {
            return false
        }

        return !selfOwnedSources.contains(normalized)
    }
}
