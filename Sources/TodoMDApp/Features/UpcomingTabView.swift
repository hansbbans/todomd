import SwiftUI

struct UpcomingTabEventDescriptor: Equatable {
    let id: String
    let title: String
    let calendarColorHex: String
    let isAllDay: Bool
    let timeText: String?

    static func make(event: CalendarEventItem) -> Self {
        Self(
            id: event.id,
            title: event.title,
            calendarColorHex: event.calendarColorHex,
            isAllDay: event.isAllDay,
            timeText: event.isAllDay ? nil : formatTime(event.startDate)
        )
    }

    private static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

struct UpcomingTabSectionDescriptor: Identifiable, Equatable {
    let id: String
    let date: Date
    let dayNumberText: String
    let dayHeaderLabel: String
    let records: [TaskRecord]
    let events: [UpcomingTabEventDescriptor]

    var taskRecordPaths: [String] {
        records.map(\.identity.path)
    }

    var eventIDs: [String] {
        events.map(\.id)
    }

    var showsEmptyState: Bool {
        records.isEmpty && events.isEmpty
    }

    static func make(section: UpcomingAgendaSection) -> Self {
        Self(
            id: section.id,
            date: section.date,
            dayNumberText: String(Calendar.current.component(.day, from: section.date)),
            dayHeaderLabel: dayHeaderLabel(for: section.date),
            records: section.records,
            events: section.events.map(UpcomingTabEventDescriptor.make)
        )
    }

    private static func dayHeaderLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
}

struct UpcomingTabDescriptor: Equatable {
    let listID: String
    let sections: [UpcomingTabSectionDescriptor]

    static func makeForRootState(sections: [UpcomingAgendaSection]) -> Self {
        make(sections: sections)
    }

    static func make(sections: [UpcomingAgendaSection]) -> Self {
        Self(
            listID: BuiltInView.upcoming.rawValue,
            sections: sections.map(UpcomingTabSectionDescriptor.make)
        )
    }
}

struct UpcomingTabView<TaskRowContent: View>: View {
    let descriptor: UpcomingTabDescriptor
    let taskRow: (TaskRecord) -> TaskRowContent
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                CalendarHeroHeader(kind: .upcoming)

                ForEach(descriptor.sections) { section in
                    UpcomingTabSectionView(section: section, taskRow: taskRow)
                }
            }
            .padding(.horizontal, ThingsSurfaceLayout.heroHorizontalPadding)
            .padding(.top, ThingsSurfaceLayout.heroTopPadding)
            .padding(.bottom, ThingsSurfaceLayout.upcomingBottomPadding)
        }
        .scrollIndicators(.hidden)
        .background(theme.backgroundColor)
    }
}

private struct UpcomingTabSectionView<TaskRowContent: View>: View {
    let section: UpcomingTabSectionDescriptor
    let taskRow: (TaskRecord) -> TaskRowContent
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(section.dayNumberText)
                    .font(.system(size: 46, weight: .bold))
                    .tracking(-1.8)
                    .foregroundStyle(theme.textPrimaryColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(section.dayHeaderLabel)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(theme.textPrimaryColor)
                    .tracking(-0.4)
                    .lineLimit(1)
                    .layoutPriority(1)

                Rectangle()
                    .fill(theme.separatorColor.opacity(0.46))
                    .frame(maxWidth: .infinity)
                    .frame(height: 1)
                    .offset(y: -4)
            }

            if section.showsEmptyState {
                Text("No tasks or events")
                    .font(.system(size: 16.5, weight: .regular))
                    .foregroundStyle(theme.textSecondaryColor)
            } else {
                if !section.records.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(section.records) { record in
                            taskRow(record)
                        }
                    }
                }

                if !section.events.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(section.events.enumerated()), id: \.offset) { _, event in
                            UpcomingTabEventLineView(event: event)
                        }
                    }
                }
            }
        }
    }
}

private struct UpcomingTabEventLineView: View {
    let event: UpcomingTabEventDescriptor
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            if event.isAllDay {
                RoundedRectangle(cornerRadius: 2)
                    .fill(eventAccentColor)
                    .frame(width: 4, height: 21)

                Text(event.title)
                    .foregroundStyle(theme.textPrimaryColor.opacity(0.9))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                if let timeText = event.timeText {
                    Text(timeText)
                        .foregroundStyle(eventAccentColor)
                        .monospacedDigit()
                        .frame(width: 84, alignment: .leading)
                        .lineLimit(1)
                }

                Text(event.title)
                    .foregroundStyle(theme.textPrimaryColor.opacity(0.9))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.system(size: 16.5, weight: .regular))
    }

    private var eventAccentColor: Color {
        Color(hex: event.calendarColorHex) ?? theme.textSecondaryColor
    }
}

private extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6 else { return nil }

        var rgb: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&rgb) else { return nil }

        let red = Double((rgb & 0xFF0000) >> 16) / 255.0
        let green = Double((rgb & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgb & 0x0000FF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}
