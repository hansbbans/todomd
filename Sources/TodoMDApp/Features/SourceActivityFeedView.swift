import SwiftUI

struct SourceActivityFeedView: View {
    let entries: [SourceActivityEntry]
    var emptyStateText = "No recent source activity"

    var body: some View {
        if entries.isEmpty {
            Text(emptyStateText)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(daySections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(section.entries) { entry in
                            SourceActivityFeedRow(entry: entry)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var daySections: [DaySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { entry in
            calendar.startOfDay(for: entry.timestamp)
        }

        return grouped.keys.sorted(by: >).map { day in
            DaySection(
                date: day,
                title: Self.dayTitle(for: day, calendar: calendar),
                entries: grouped[day, default: []].sorted { $0.timestamp > $1.timestamp }
            )
        }
    }

    private static func dayTitle(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct DaySection: Identifiable {
    let date: Date
    let title: String
    let entries: [SourceActivityEntry]

    var id: TimeInterval {
        date.timeIntervalSinceReferenceDate
    }
}

private struct SourceActivityFeedRow: View {
    let entry: SourceActivityEntry
    private let visibleSubjectLimit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                sourceView

                Text(summaryText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Text(timestampText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(displayedSubjects, id: \.self) { subject in
                    Text("• \(subject)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if remainingSubjectCount > 0 {
                    Text("+\(remainingSubjectCount) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 2)
        }
    }

    private var displayedSubjects: [String] {
        Array(entry.subjects.prefix(visibleSubjectLimit))
    }

    private var remainingSubjectCount: Int {
        max(entry.itemCount - displayedSubjects.count, 0)
    }

    private var summaryText: String {
        switch entry.action {
        case .created:
            return "created \(entry.itemCount) task\(nounSuffix)"
        case .modified:
            return "updated \(entry.itemCount) task\(nounSuffix)"
        case .completed:
            return "completed \(entry.itemCount) task\(nounSuffix)"
        case .deleted:
            return "deleted \(entry.itemCount) task\(nounSuffix)"
        case .conflicted:
            return "flagged \(entry.itemCount) conflict\(nounSuffix)"
        case .unreadable:
            return "found \(entry.itemCount) unreadable file\(nounSuffix)"
        }
    }

    @ViewBuilder
    private var sourceView: some View {
        if let badge = TaskSourceAttribution.badge(for: entry.source) {
            TaskRowSourceBadge(badge: badge)
        } else {
            Text(TaskSourceAttribution.displayName(entry.source) ?? entry.source)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.secondary.opacity(0.12), in: Capsule(style: .continuous))
        }
    }

    private var nounSuffix: String {
        entry.itemCount == 1 ? "" : "s"
    }

    private var timestampText: String {
        entry.timestamp.formatted(date: .omitted, time: .shortened)
    }
}
