import Foundation

enum TaskSourceAttribution {
    struct Badge: Equatable {
        let label: String
        let systemImage: String
        let accessibilityLabel: String
    }

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

    static func badge(for source: String?) -> Badge? {
        guard let normalized = normalized(source),
              normalized != "unknown",
              normalized != "user",
              let displayName = displayName(source)
        else {
            return nil
        }

        return Badge(
            label: badgeLabel(normalized: normalized, displayName: displayName),
            systemImage: badgeSystemImage(for: normalized),
            accessibilityLabel: "Source: \(displayName)"
        )
    }

    private static func badgeLabel(normalized: String, displayName: String) -> String {
        switch normalized {
        case "shortcut":
            return "Shortcut"
        case "voice-ramble":
            return "Voice"
        case "import-reminders":
            return "Reminders"
        case "inbox-drop":
            return "Inbox"
        case "obsidian":
            return "Obsidian"
        default:
            if normalized.contains("calendar") {
                return "Calendar"
            }
            if normalized.hasSuffix("-agent") {
                let stem = String(displayName.dropLast("-agent".count))
                return compactFallbackLabel(titleizedSource(stem))
            }
            return compactFallbackLabel(titleizedSource(displayName))
        }
    }

    private static func badgeSystemImage(for normalized: String) -> String {
        switch normalized {
        case "shortcut":
            return "bolt.fill"
        case "voice-ramble":
            return "waveform"
        case "import-reminders":
            return "checklist"
        case "inbox-drop":
            return "tray.and.arrow.down.fill"
        case "obsidian":
            return "book.closed.fill"
        default:
            if normalized.contains("agent")
                || normalized.contains("claude")
                || normalized.contains("codex")
                || normalized.contains("gpt")
                || normalized.contains("ai") {
                return "sparkles"
            }
            if normalized.contains("calendar") {
                return "calendar"
            }
            return "arrow.down.circle"
        }
    }

    private static func compactFallbackLabel(_ label: String) -> String {
        let maxCompactLabelLength = 10
        let words = label.split(separator: " ").map(String.init)
        guard var compact = words.first, !compact.isEmpty else { return label }

        for word in words.dropFirst() {
            let candidate = "\(compact) \(word)"
            if candidate.count > maxCompactLabelLength {
                break
            }
            compact = candidate
        }

        if compact.count > maxCompactLabelLength {
            return String(compact.prefix(maxCompactLabelLength))
        }
        return compact
    }

    private static func titleizedSource(_ source: String) -> String {
        source
            .split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " })
            .map { token in
                token.prefix(1).uppercased() + token.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }
}
