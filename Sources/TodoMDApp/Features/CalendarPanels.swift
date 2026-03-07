import SwiftUI

enum CalendarHeroKind {
    case today
    case upcoming

    var title: String {
        switch self {
        case .today:
            return "Today"
        case .upcoming:
            return "Upcoming"
        }
    }

    var symbolName: String {
        switch self {
        case .today:
            return "star.fill"
        case .upcoming:
            return "calendar"
        }
    }

    var iconColor: Color {
        switch self {
        case .today:
            return Color(red: 0.89, green: 0.71, blue: 0.13)
        case .upcoming:
            return Color(red: 1.0, green: 0.22, blue: 0.45)
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .today:
            return 25
        case .upcoming:
            return 31
        }
    }

    var titleSize: CGFloat {
        switch self {
        case .today:
            return 34
        case .upcoming:
            return 39
        }
    }

    var bottomPadding: CGFloat {
        switch self {
        case .today:
            return 8
        case .upcoming:
            return 18
        }
    }
}

struct CalendarHeroHeader: View {
    let kind: CalendarHeroKind
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: kind.symbolName)
                .font(.system(size: kind.iconSize, weight: .semibold))
                .foregroundStyle(kind.iconColor)
                .frame(width: kind.iconSize + 4, alignment: .leading)

            Text(kind.title)
                .font(.system(size: kind.titleSize, weight: .bold))
                .tracking(-1.2)
                .foregroundStyle(theme.textPrimaryColor)

            Spacer(minLength: 0)
        }
        .padding(.bottom, kind.bottomPadding)
        .accessibilityIdentifier("calendar.heroHeader.\(kind.title.lowercased())")
    }
}

struct TodayCalendarCard: View {
    let events: [CalendarEventItem]
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if events.isEmpty {
                Text("No calendar events today")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(theme.textSecondaryColor.opacity(0.88))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(events.prefix(7)) { event in
                        TodayCalendarEventLineView(event: event)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(colorScheme == .dark ? 0.035 : 0.08), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityIdentifier("today.calendarCard")
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(colorScheme == .dark ? Color(red: 0.07, green: 0.08, blue: 0.12) : theme.surfaceColor)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(colorScheme == .dark ? 0.022 : 0.05),
                                .clear,
                                .black.opacity(colorScheme == .dark ? 0.08 : 0.02)
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
            LazyVStack(alignment: .leading, spacing: 34) {
                CalendarHeroHeader(kind: .upcoming)

                ForEach(sections) { section in
                    UpcomingDaySectionView(section: section)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 72)
            .padding(.bottom, 108)
        }
        .scrollIndicators(.hidden)
        .background(theme.backgroundColor)
    }
}

private struct UpcomingDaySectionView: View {
    let section: UpcomingAgendaSection
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(dayNumberText)
                .font(.system(size: 62, weight: .bold))
                .tracking(-2.6)
                .foregroundStyle(theme.textPrimaryColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 54, alignment: .leading)
                .offset(y: -4)

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Rectangle()
                        .fill(theme.separatorColor.opacity(0.46))
                        .frame(maxWidth: .infinity)
                        .frame(height: 1)

                    Text(dayHeaderLabel)
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(theme.textPrimaryColor)
                        .tracking(-0.4)
                }
                .padding(.top, 10)

                if section.records.isEmpty && section.events.isEmpty {
                    Text("No tasks or events")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(theme.textSecondaryColor)
                } else {
                    if !section.records.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(section.records) { record in
                                UpcomingTaskLineView(record: record)
                            }
                        }
                    }

                    if !section.events.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(section.events) { event in
                                UpcomingEventLineView(event: event)
                            }
                        }
                    }
                }
            }
        }
    }

    private var dayNumberText: String {
        String(Calendar.current.component(.day, from: section.date))
    }

    private var dayHeaderLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInTomorrow(section.date) {
            return "Tomorrow"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "EEEE"
        return formatter.string(from: section.date)
    }

}

private struct UpcomingTaskLineView: View {
    let record: TaskRecord
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        NavigationLink(value: record.identity.path) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "circle")
                    .foregroundStyle(theme.textSecondaryColor.opacity(0.82))
                    .font(.system(size: 14, weight: .regular))
                Text(record.document.frontmatter.title)
                    .foregroundStyle(theme.textPrimaryColor.opacity(0.9))
                    .lineLimit(1)
            }
            .font(.system(size: 17, weight: .regular))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

private struct UpcomingEventLineView: View {
    let event: CalendarEventItem
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            if event.isAllDay {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: event.calendarColorHex))
                    .frame(width: 4, height: 22)

                Text(event.title)
                    .foregroundStyle(theme.textPrimaryColor.opacity(0.9))
                    .lineLimit(1)
            } else {
                Text(formatTime(event.startDate))
                    .foregroundStyle(Color(red: 0.29, green: 0.55, blue: 1.0))
                    .monospacedDigit()
                    .frame(width: 88, alignment: .leading)
                    .lineLimit(1)

                Text(event.title)
                    .foregroundStyle(theme.textPrimaryColor.opacity(0.9))
                    .lineLimit(1)
            }
        }
        .font(.system(size: 17, weight: .regular))
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

private struct TodayCalendarEventLineView: View {
    let event: CalendarEventItem
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(timeLabel)
                .frame(width: 84, alignment: .leading)
                .monospacedDigit()

            Text(event.title)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 16.5, weight: .regular))
        .foregroundStyle(theme.textPrimaryColor.opacity(0.52))
    }

    private var timeLabel: String {
        if event.isAllDay {
            return "All-Day"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: event.startDate)
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
