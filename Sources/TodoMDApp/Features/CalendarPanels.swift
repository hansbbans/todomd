import SwiftUI

struct TodayCalendarCard: View {
    let events: [CalendarEventItem]
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textPrimaryColor)

            if events.isEmpty {
                Text("No calendar events")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.textSecondaryColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(events.prefix(8)) { event in
                        TodayCalendarEventLine(
                            event: event,
                            isHighlighted: isHighlighted(event: event)
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.surfaceColor.opacity(0.95))
        )
    }

    private func isHighlighted(event: CalendarEventItem) -> Bool {
        if event.isAllDay {
            return false
        }
        let now = Date()
        if event.startDate <= now, now <= event.endDate {
            return true
        }
        let futureTimed = events.filter { !$0.isAllDay && $0.startDate >= now }
        return futureTimed.first?.id == event.id
    }
}

private struct TodayCalendarEventLine: View {
    let event: CalendarEventItem
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: event.calendarColorHex))
                .frame(width: 4, height: 16)

            if event.isAllDay {
                Text(event.title)
                    .foregroundStyle(.white.opacity(isHighlighted ? 0.95 : 0.72))
                    .lineLimit(1)
            } else {
                Text(formatTime(event.startDate))
                    .foregroundStyle(Color(hex: event.calendarColorHex))
                    .lineLimit(1)
                Text(event.title)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(isHighlighted ? 0.95 : 0.72))
            }
        }
        .font(.system(size: 14, weight: isHighlighted ? .semibold : .regular, design: .rounded))
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

struct UpcomingCalendarView: View {
    let sections: [CalendarDaySection]
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Label {
                    Text("Upcoming")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.textPrimaryColor)
                } icon: {
                    Image(systemName: "calendar")
                        .foregroundStyle(.pink)
                        .font(.system(size: 26, weight: .bold))
                }
                .padding(.bottom, 2)

                if sections.isEmpty {
                    ContentUnavailableView(
                        "No Upcoming Events",
                        systemImage: "calendar",
                        description: Text("Allow Calendar access in Settings to view events.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    ForEach(sections) { section in
                        UpcomingDaySectionView(section: section)
                    }
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
    let section: CalendarDaySection
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(dayNumberText)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textPrimaryColor)

                Text(dayLabelText)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textPrimaryColor)

                Rectangle()
                    .fill(theme.textSecondaryColor.opacity(0.35))
                    .frame(height: 1)
                    .padding(.leading, 6)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(section.events) { event in
                    UpcomingEventLineView(event: event)
                }
            }
            .padding(.leading, 4)
        }
    }

    private var dayNumberText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: section.date)
    }

    private var dayLabelText: String {
        let calendar = Calendar.current
        if calendar.isDateInTomorrow(section.date) {
            return "Tomorrow"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: section.date)
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
