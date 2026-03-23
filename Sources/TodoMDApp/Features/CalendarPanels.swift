import SwiftUI

struct MainHeroHeader: View {
    let title: String
    let symbolName: String
    let iconColor: Color
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: symbolName)
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 29, alignment: .leading)

            Text(title)
                .font(.system(size: 34, weight: .bold))
                .tracking(-1.2)
                .foregroundStyle(theme.textPrimaryColor)

            Spacer(minLength: 0)
        }
    }
}

enum CalendarHeroKind {
    case inbox
    case today
    case upcoming

    var title: String {
        switch self {
        case .inbox:
            return "Inbox"
        case .today:
            return "Today"
        case .upcoming:
            return "Upcoming"
        }
    }

    var symbolName: String {
        switch self {
        case .inbox:
            return "tray"
        case .today:
            return "star.fill"
        case .upcoming:
            return "calendar"
        }
    }

    var iconColor: Color {
        switch self {
        case .inbox:
            return Color(red: 0.11, green: 0.60, blue: 0.98)
        case .today:
            return Color(red: 0.89, green: 0.71, blue: 0.13)
        case .upcoming:
            return Color(red: 1.0, green: 0.22, blue: 0.45)
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .inbox:
            return 25
        case .today:
            return 25
        case .upcoming:
            return 25
        }
    }

    var titleSize: CGFloat {
        switch self {
        case .inbox:
            return 34
        case .today:
            return 34
        case .upcoming:
            return 34
        }
    }

    var bottomPadding: CGFloat {
        ThingsSurfaceLayout.heroBottomPadding
    }
}

struct CalendarHeroHeader: View {
    let kind: CalendarHeroKind

    var body: some View {
        MainHeroHeader(title: kind.title, symbolName: kind.symbolName, iconColor: kind.iconColor)
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
        .background(
            ThingsSurfaceBackdrop(
                kind: .elevatedCard,
                theme: theme,
                colorScheme: colorScheme
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: ThingsSurfaceKind.elevatedCard.cornerRadius, style: .continuous))
        .accessibilityIdentifier("today.calendarCard")
    }
}

struct UpcomingCalendarView<TaskRowContent: View>: View {
    let sections: [UpcomingAgendaSection]
    let taskRow: (TaskRecord) -> TaskRowContent
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                CalendarHeroHeader(kind: .upcoming)

                ForEach(sections) { section in
                    UpcomingDaySectionView(section: section, taskRow: taskRow)
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

private struct UpcomingDaySectionView<TaskRowContent: View>: View {
    let section: UpcomingAgendaSection
    let taskRow: (TaskRecord) -> TaskRowContent
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(dayNumberText)
                    .font(.system(size: 46, weight: .bold))
                    .tracking(-1.8)
                    .foregroundStyle(theme.textPrimaryColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(dayHeaderLabel)
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

            if section.records.isEmpty && section.events.isEmpty {
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
                        ForEach(section.events) { event in
                            UpcomingEventLineView(event: event)
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

private struct UpcomingEventLineView: View {
    let event: CalendarEventItem
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
                Text(formatTime(event.startDate))
                    .foregroundStyle(eventAccentColor)
                    .monospacedDigit()
                    .frame(width: 84, alignment: .leading)
                    .lineLimit(1)

                Text(event.title)
                    .foregroundStyle(theme.textPrimaryColor.opacity(0.9))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.system(size: 16.5, weight: .regular))
    }

    private var eventAccentColor: Color {
        Color(hex: event.calendarColorHex)
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
