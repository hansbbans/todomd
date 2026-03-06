import SwiftUI

struct TodayCalendarCard: View {
    let events: [CalendarEventItem]
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if events.isEmpty {
                Text("No calendar events today")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(theme.textSecondaryColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(events.prefix(6)) { event in
                        TodayCalendarEventLineView(event: event)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.04), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 10)
        .accessibilityIdentifier("today.calendarCard")
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(theme.surfaceColor)
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.03),
                                .clear,
                                theme.accentColor.opacity(0.03)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
    }
}

struct UpcomingCalendarView: View {
    let sections: [UpcomingAgendaSection]
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(sections) { section in
                    UpcomingDaySectionView(section: section)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 90)
        }
        .scrollIndicators(.hidden)
        .background(theme.backgroundColor)
    }
}

private struct UpcomingDaySectionView: View {
    let section: UpcomingAgendaSection
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(dayHeaderText)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textPrimaryColor)

            if section.records.isEmpty && section.events.isEmpty {
                Text("No tasks or events")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.textSecondaryColor)
                    .padding(.leading, 4)
            } else {
                if !section.records.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(section.records) { record in
                            UpcomingTaskLineView(record: record)
                        }
                    }
                    .padding(.leading, 4)
                }

                if !section.events.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(section.events) { event in
                            UpcomingEventLineView(event: event)
                        }
                    }
                    .padding(.leading, 4)
                }
            }

            Rectangle()
                .fill(theme.textSecondaryColor.opacity(0.2))
                .frame(height: 1)
                .padding(.top, 4)
        }
    }

    private var dayHeaderText: String {
        let weekday = weekdayText
        let month = monthText
        return "\(weekday) \(month) \(ordinal(dayOfMonth))"
    }

    private var dayOfMonth: Int {
        Calendar.current.component(.day, from: section.date)
    }

    private var weekdayText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "EEE"
        return formatter.string(from: section.date)
    }

    private var monthText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMMM"
        return formatter.string(from: section.date)
    }

    private func ordinal(_ day: Int) -> String {
        let mod100 = day % 100
        let suffix: String
        if (11...13).contains(mod100) {
            suffix = "th"
        } else {
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(day)\(suffix)"
    }
}

private struct UpcomingTaskLineView: View {
    let record: TaskRecord
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        NavigationLink(value: record.identity.path) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(theme.accentColor)
                    .font(.system(size: 14, weight: .semibold))
                Text(record.document.frontmatter.title)
                    .foregroundStyle(theme.textPrimaryColor.opacity(0.92))
                    .lineLimit(1)
            }
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

private struct CalendarDayHeaderView: View {
    let date: Date
    let label: String
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(dayNumberText)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textPrimaryColor)

            Text(label)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textPrimaryColor)

            Rectangle()
                .fill(theme.textSecondaryColor.opacity(0.35))
                .frame(height: 1)
                .padding(.leading, 6)
        }
    }

    private var dayNumberText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
}

private struct UpcomingEventLineView: View {
    let event: CalendarEventItem
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: event.calendarColorHex))
                .frame(width: 4, height: 18)

            if event.isAllDay {
                Text(event.title)
                    .foregroundStyle(theme.textPrimaryColor.opacity(0.88))
                    .lineLimit(1)
            } else {
                Text(formatTime(event.startDate))
                    .foregroundStyle(theme.accentColor)
                    .lineLimit(1)
                Text(event.title)
                    .foregroundStyle(theme.textPrimaryColor.opacity(0.88))
                    .lineLimit(1)
            }
        }
        .font(.system(size: 16, weight: .medium, design: .rounded))
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

private struct TodayCalendarEventLineView: View {
    let event: CalendarEventItem
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(timeLabel)
                .frame(width: 92, alignment: .leading)
                .monospacedDigit()

            Text(event.title)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 17, weight: .regular))
        .foregroundStyle(theme.textSecondaryColor)
    }

    private var timeLabel: String {
        if event.isAllDay {
            return "All-Day"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: event.startDate).uppercased()
    }
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        let red = Double((rgb & 0xFF0000) >> 16) / 255.0
        let green = Double((rgb & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgb & 0x0000FF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}
