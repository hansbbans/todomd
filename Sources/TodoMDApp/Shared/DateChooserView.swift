import SwiftUI

struct DateChooserView: View {
    enum TimeMode {
        case hidden
        case optional
    }

    enum Context {
        case due
        case scheduled

        var title: String {
            switch self {
            case .due:
                "Due"
            case .scheduled:
                "Scheduled"
            }
        }

        var emptyTitle: String {
            switch self {
            case .due:
                "No due date"
            case .scheduled:
                "Not scheduled"
            }
        }

        var emptyMessage: String {
            switch self {
            case .due:
                "Use a quick preset or pick a day from the calendar."
            case .scheduled:
                "Choose when this task should surface without adding a deadline."
            }
        }

        var iconName: String {
            switch self {
            case .due:
                "calendar.badge.exclamationmark"
            case .scheduled:
                "calendar.badge.clock"
            }
        }
    }

    private enum Preset: String, Identifiable {
        case today = "Today"
        case tonight = "Tonight"
        case tomorrow = "Tomorrow"
        case nextWeek = "Next Week"

        var id: String {
            switch self {
            case .today:
                "today"
            case .tonight:
                "tonight"
            case .tomorrow:
                "tomorrow"
            case .nextWeek:
                "nextWeek"
            }
        }
    }

    @EnvironmentObject private var theme: ThemeManager
    @AppStorage(NotificationTimePreference.hourKey) private var notificationHour = 9
    @AppStorage(NotificationTimePreference.minuteKey) private var notificationMinute = 0

    let context: Context
    let timeMode: TimeMode
    @Binding var hasDate: Bool
    @Binding var date: Date
    @Binding var hasTime: Bool
    @Binding var time: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            presetGrid
            calendarSurface
            if timeMode == .optional {
                timeSurface
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(theme.surfaceColor.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.textSecondaryColor.opacity(0.16), lineWidth: 1)
        )
        .onChange(of: hasDate, initial: false) { _, isOn in
            if !isOn {
                hasTime = false
            }
        }
        .onChange(of: hasTime, initial: false) { _, isOn in
            if isOn {
                let calendar = Calendar.current
                let hour = calendar.component(.hour, from: time)
                let minute = calendar.component(.minute, from: time)
                if hour == 0, minute == 0 {
                    time = notificationTimePreference.date(on: date, calendar: calendar)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(theme.accentColor.opacity(hasDate ? 0.18 : 0.1))
                Image(systemName: context.iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(hasDate ? theme.accentColor : theme.textSecondaryColor)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(hasDate ? summaryTitle : context.emptyTitle)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(theme.textPrimaryColor)
                    .accessibilityIdentifier("\(accessibilityIDPrefix).summaryTitle")
                Text(hasDate ? summarySubtitle : context.emptyMessage)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(theme.textSecondaryColor)
            }

            Spacer(minLength: 0)

            if hasDate {
                Button("Clear") {
                    hasDate = false
                }
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .accessibilityIdentifier("\(accessibilityIDPrefix).clear")
            }
        }
    }

    private var presetGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(availablePresets) { preset in
                Button {
                    apply(preset)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: iconName(for: preset))
                            .font(.system(size: 13, weight: .semibold))
                        Text(preset.rawValue)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(presetIsSelected(preset) ? theme.accentColor : theme.textPrimaryColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(presetIsSelected(preset) ? theme.accentColor.opacity(0.14) : theme.backgroundColor
                                .opacity(0.72))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                presetIsSelected(preset) ? theme.accentColor.opacity(0.38) : theme.textSecondaryColor
                                    .opacity(0.14),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(accessibilityIDPrefix).preset.\(preset.id)")
            }
        }
    }

    private var calendarSurface: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calendar")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(theme.textSecondaryColor)

            DatePicker(
                context.title,
                selection: visibleDateBinding,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(theme.accentColor)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.backgroundColor.opacity(0.8))
        )
    }

    @ViewBuilder
    private var timeSurface: some View {
        if hasDate {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $hasTime) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add time")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(theme.textPrimaryColor)
                        Text(hasTime ? time.formatted(date: .omitted, time: .shortened) : "Optional")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(theme.textSecondaryColor)
                    }
                }
                .toggleStyle(.switch)
                .accessibilityIdentifier("\(accessibilityIDPrefix).toggleTime")

                if hasTime {
                    timePicker
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(theme.backgroundColor.opacity(0.8))
            )
        }
    }

    private var timePicker: some View {
        Group {
            #if os(iOS)
                DatePicker(
                    "Time",
                    selection: $time,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .clipped()
            #else
                DatePicker(
                    "Time",
                    selection: $time,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
            #endif
        }
    }

    private var summaryTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return hasTime ? "Today at \(time.formatted(date: .omitted, time: .shortened))" : "Today"
        }
        if calendar.isDateInTomorrow(date) {
            return hasTime ? "Tomorrow at \(time.formatted(date: .omitted, time: .shortened))" : "Tomorrow"
        }
        if hasTime {
            return "\(date.formatted(date: .complete, time: .omitted)) at \(time.formatted(date: .omitted, time: .shortened))"
        }
        return date.formatted(date: .complete, time: .omitted)
    }

    private var summarySubtitle: String {
        switch context {
        case .due:
            hasTime ? "Deadline and reminder time are aligned." : "Day-only deadline."
        case .scheduled:
            "Shows when this task should appear in your flow."
        }
    }

    private func presetIsSelected(_ preset: Preset) -> Bool {
        let calendar = Calendar.current
        switch preset {
        case .today:
            guard hasDate, calendar.isDateInToday(date) else { return false }
            return !hasTime || !notificationTimePreference.matches(time, calendar: calendar)
        case .tonight:
            return hasDate &&
                hasTime &&
                calendar.isDateInToday(date) &&
                notificationTimePreference.matches(time, calendar: calendar)
        case .tomorrow:
            return hasDate && calendar.isDateInTomorrow(date)
        case .nextWeek:
            guard hasDate, let nextWeek = nextWeekDate else { return false }
            return calendar.isDate(date, inSameDayAs: nextWeek)
        }
    }

    private func apply(_ preset: Preset) {
        let calendar = Calendar.current
        switch preset {
        case .today:
            hasDate = true
            date = calendar.startOfDay(for: Date())
            if showsTonightPreset {
                hasTime = false
            }
        case .tonight:
            let today = calendar.startOfDay(for: Date())
            hasDate = true
            hasTime = true
            date = today
            time = notificationTimePreference.date(on: today, calendar: calendar)
        case .tomorrow:
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))
            else { return }
            hasDate = true
            date = tomorrow
        case .nextWeek:
            guard let nextWeek = nextWeekDate else { return }
            hasDate = true
            date = nextWeek
        }
    }

    private var visibleDateBinding: Binding<Date> {
        Binding(
            get: { hasDate ? date : Calendar.current.startOfDay(for: Date()) },
            set: { newValue in
                hasDate = true
                date = Calendar.current.startOfDay(for: newValue)
            }
        )
    }

    private var nextWeekDate: Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayWeekday = calendar.component(.weekday, from: today)
        let monday = 2
        var daysUntilNextMonday = (monday - todayWeekday + 7) % 7
        if daysUntilNextMonday == 0 {
            daysUntilNextMonday = 7
        }
        return calendar.date(byAdding: .day, value: daysUntilNextMonday, to: today)
    }

    private func iconName(for preset: Preset) -> String {
        switch preset {
        case .today:
            "sun.max"
        case .tonight:
            "moon.stars"
        case .tomorrow:
            "sunrise"
        case .nextWeek:
            "forward"
        }
    }

    private var availablePresets: [Preset] {
        var presets: [Preset] = [.today]
        if showsTonightPreset {
            presets.append(.tonight)
        }
        presets.append(contentsOf: [.tomorrow, .nextWeek])
        return presets
    }

    private var showsTonightPreset: Bool {
        context == .due && timeMode == .optional
    }

    private var notificationTimePreference: NotificationTimePreference {
        NotificationTimePreference(hour: notificationHour, minute: notificationMinute)
    }

    private var accessibilityIDPrefix: String {
        switch context {
        case .due:
            "dateChooser.due"
        case .scheduled:
            "dateChooser.scheduled"
        }
    }
}

#Preview("Due") {
    DateChooserPreviewHost(context: .due, timeMode: .optional)
        .environmentObject(ThemeManager())
        .padding()
}

#Preview("Scheduled") {
    DateChooserPreviewHost(context: .scheduled, timeMode: .hidden)
        .environmentObject(ThemeManager())
        .padding()
}

private struct DateChooserPreviewHost: View {
    let context: DateChooserView.Context
    let timeMode: DateChooserView.TimeMode

    @State private var hasDate = true
    @State private var date = Date()
    @State private var hasTime = false
    @State private var time = Date()

    var body: some View {
        DateChooserView(
            context: context,
            timeMode: timeMode,
            hasDate: $hasDate,
            date: $date,
            hasTime: $hasTime,
            time: $time
        )
    }
}
