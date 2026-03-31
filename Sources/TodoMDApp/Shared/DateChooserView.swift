import SwiftUI

private enum RecurrenceFrequencyOption: String, CaseIterable {
    case none
    case daily
    case weekly
    case monthly
    case yearly

    var rruleValue: String? {
        switch self {
        case .none:
            nil
        case .daily:
            "DAILY"
        case .weekly:
            "WEEKLY"
        case .monthly:
            "MONTHLY"
        case .yearly:
            "YEARLY"
        }
    }
}

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

    private enum RecurrencePreset: String, CaseIterable, Identifiable {
        case daily
        case weekly
        case weekday
        case monthly
        case yearly
        case custom

        var id: String { rawValue }
    }

    @Environment(ThemeManager.self) private var theme
    @AppStorage(NotificationTimePreference.hourKey) private var notificationHour = 9
    @AppStorage(NotificationTimePreference.minuteKey) private var notificationMinute = 0

    let context: Context
    let timeMode: TimeMode
    @Binding var hasDate: Bool
    @Binding var date: Date
    @Binding var hasTime: Bool
    @Binding var time: Date
    private var recurrence: Binding<String>?

    @State private var recurrenceFrequency: RecurrenceFrequencyOption = .none
    @State private var recurrenceInterval = 1
    @State private var recurrenceWeekdays: Set<String> = []
    @State private var showingCustomRepeatEditor = false

    private let recurrenceWeekdayOptions = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

    init(
        context: Context,
        timeMode: TimeMode,
        hasDate: Binding<Bool>,
        date: Binding<Date>,
        hasTime: Binding<Bool>,
        time: Binding<Date>,
        recurrence: Binding<String>? = nil
    ) {
        self.context = context
        self.timeMode = timeMode
        self._hasDate = hasDate
        self._date = date
        self._hasTime = hasTime
        self._time = time
        self.recurrence = recurrence
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            presetGrid
            calendarSurface
            if timeMode == .optional {
                timeSurface
            }
            if supportsRecurrence {
                recurrenceSurface
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
        .onAppear {
            syncRecurrenceBuilderFromBinding()
        }
        .onChange(of: normalizedRecurrenceRule, initial: false) { _, _ in
            syncRecurrenceBuilderFromBinding()
        }
        .sheet(isPresented: $showingCustomRepeatEditor) {
            recurrenceEditorSheet
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

    private var recurrenceSurface: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Recurrence (optional)")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(theme.textPrimaryColor)
                Text(recurrenceIsEnabled ? recurrenceSummaryText() : "Optional")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(theme.textSecondaryColor)
            }

            Picker("Recurrence", selection: recurrenceEnabledBinding) {
                Text("No").tag(false)
                Text("Yes").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("\(accessibilityIDPrefix).toggleRecurrence")

            if recurrenceIsEnabled {
                recurrencePresetGrid
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.backgroundColor.opacity(0.8))
        )
    }

    private var recurrencePresetGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(RecurrencePreset.allCases) { preset in
                Button {
                    applyRecurrencePreset(preset)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: recurrenceIconName(for: preset))
                            .font(.system(size: 13, weight: .semibold))
                        Text(recurrenceTitle(for: preset))
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(recurrencePresetIsSelected(preset) ? theme.accentColor : theme.textPrimaryColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                recurrencePresetIsSelected(preset) ? theme.accentColor.opacity(0.14) : theme.surfaceColor.opacity(0.72)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                recurrencePresetIsSelected(preset) ? theme.accentColor.opacity(0.38) : theme.textSecondaryColor
                                    .opacity(0.14),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(accessibilityIDPrefix).recurrence.\(preset.id)")
            }
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

    private var supportsRecurrence: Bool {
        context == .due && recurrence != nil
    }

    private var recurrenceIsEnabled: Bool {
        !normalizedRecurrenceRule.isEmpty
    }

    private var recurrenceEnabledBinding: Binding<Bool> {
        Binding(
            get: { recurrenceIsEnabled },
            set: { isEnabled in
                if isEnabled {
                    if !recurrenceIsEnabled {
                        applyRecurrenceRule("FREQ=DAILY")
                    }
                } else {
                    clearRecurrence()
                }
            }
        )
    }

    private var normalizedRecurrenceRule: String {
        recurrence?.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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

    private var recurrenceEditorSheet: some View {
        NavigationStack {
            Form {
                Section("Pattern") {
                    Picker("Frequency", selection: $recurrenceFrequency) {
                        ForEach(RecurrenceFrequencyOption.allCases, id: \.self) { option in
                            Text(option.rawValue.capitalized).tag(option)
                        }
                    }

                    if recurrenceFrequency != .none {
                        Stepper(
                            "Every \(recurrenceInterval) \(recurrenceUnitText())",
                            value: $recurrenceInterval,
                            in: 1 ... 365
                        )

                        if recurrenceFrequency == .weekly {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                                ForEach(recurrenceWeekdayOptions, id: \.self) { day in
                                    Button(day) {
                                        if recurrenceWeekdays.contains(day) {
                                            recurrenceWeekdays.remove(day)
                                        } else {
                                            recurrenceWeekdays.insert(day)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(recurrenceWeekdays.contains(day) ? theme.accentColor : theme.textSecondaryColor)
                                }
                            }
                        }
                    }
                }

                Section("Preview") {
                    Text(recurrenceBuilderPreview() ?? "Never")
                        .foregroundStyle(theme.textSecondaryColor)
                }
            }
            .navigationTitle("Custom Repeat")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        syncRecurrenceBuilderFromBinding()
                        showingCustomRepeatEditor = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        applyRecurrenceBuilder()
                        showingCustomRepeatEditor = false
                    }
                    .disabled(recurrenceFrequency == .weekly && recurrenceWeekdays.isEmpty)
                }
            }
        }
    }

    private func applyRecurrencePreset(_ preset: RecurrencePreset) {
        switch preset {
        case .daily:
            applyRecurrenceRule("FREQ=DAILY")
        case .weekly:
            applyRecurrenceRule("FREQ=WEEKLY;BYDAY=\(weekdayToken(for: recurrenceAnchorDate()))")
        case .weekday:
            applyRecurrenceRule("FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR")
        case .monthly:
            applyRecurrenceRule("FREQ=MONTHLY")
        case .yearly:
            applyRecurrenceRule("FREQ=YEARLY")
        case .custom:
            if !recurrenceIsEnabled {
                applyRecurrenceRule("FREQ=DAILY")
            }
            syncRecurrenceBuilderFromBinding()
            showingCustomRepeatEditor = true
        }
    }

    private func applyRecurrenceRule(_ rule: String) {
        recurrence?.wrappedValue = rule
        syncRecurrenceBuilderFromBinding()
    }

    private func applyRecurrenceBuilder() {
        guard let freq = recurrenceFrequency.rruleValue else {
            clearRecurrence()
            return
        }

        var fields = ["FREQ=\(freq)"]
        if recurrenceInterval > 1 {
            fields.append("INTERVAL=\(recurrenceInterval)")
        }
        if recurrenceFrequency == .weekly, !recurrenceWeekdays.isEmpty {
            let ordered = recurrenceWeekdayOptions.filter { recurrenceWeekdays.contains($0) }
            fields.append("BYDAY=\(ordered.joined(separator: ","))")
        }

        applyRecurrenceRule(fields.joined(separator: ";"))
    }

    private func recurrenceBuilderPreview() -> String? {
        switch recurrenceFrequency {
        case .none:
            return nil
        case .daily:
            return recurrenceInterval == 1 ? "Every day" : "Every \(recurrenceInterval) days"
        case .weekly:
            if recurrenceWeekdays.isEmpty {
                return recurrenceInterval == 1 ? "Every week" : "Every \(recurrenceInterval) weeks"
            }
            let orderedDays = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
            let dayNames = orderedDays
                .filter { recurrenceWeekdays.contains($0) }
                .compactMap(weekdayShortText(fromToken:))
                .joined(separator: ", ")
            let weekPart = recurrenceInterval == 1 ? "week" : "\(recurrenceInterval) weeks"
            return "Every \(weekPart) on \(dayNames)"
        case .monthly:
            return recurrenceInterval == 1 ? "Every month" : "Every \(recurrenceInterval) months"
        case .yearly:
            return recurrenceInterval == 1 ? "Every year" : "Every \(recurrenceInterval) years"
        }
    }

    private func syncRecurrenceBuilderFromBinding() {
        guard !normalizedRecurrenceRule.isEmpty else {
            recurrenceFrequency = .none
            recurrenceInterval = 1
            recurrenceWeekdays = []
            return
        }

        do {
            let parsed = try RecurrenceRule.parse(normalizedRecurrenceRule)
            recurrenceInterval = max(1, parsed.interval)
            recurrenceWeekdays = Set(parsed.byDay)
            switch parsed.frequency {
            case .daily:
                recurrenceFrequency = .daily
            case .weekly:
                recurrenceFrequency = .weekly
            case .monthly:
                recurrenceFrequency = .monthly
            case .yearly:
                recurrenceFrequency = .yearly
            }
        } catch {
            recurrenceFrequency = .none
            recurrenceInterval = 1
            recurrenceWeekdays = []
        }
    }

    private func clearRecurrence() {
        recurrence?.wrappedValue = ""
        recurrenceFrequency = .none
        recurrenceInterval = 1
        recurrenceWeekdays = []
    }

    private func recurrenceSummaryText() -> String {
        guard recurrenceIsEnabled else { return "Optional" }
        guard let parsed = try? RecurrenceRule.parse(normalizedRecurrenceRule) else { return normalizedRecurrenceRule }

        let anchorDate = recurrenceAnchorDate()
        switch parsed.frequency {
        case .daily:
            return parsed.interval == 1 ? "Every day" : "Every \(parsed.interval) days"
        case .weekly:
            if parsed.byDay.isEmpty {
                return parsed.interval == 1 ? "Every week" : "Every \(parsed.interval) weeks"
            }
            let dayNames = parsed.byDay
                .compactMap(weekdayShortText(fromToken:))
                .joined(separator: ", ")
            if parsed.interval == 1 {
                return dayNames.isEmpty ? "Every week" : "Every week on \(dayNames)"
            }
            return dayNames.isEmpty ? "Every \(parsed.interval) weeks" : "Every \(parsed.interval) weeks on \(dayNames)"
        case .monthly:
            let dayText = ordinal(dayOfMonth(from: anchorDate))
            return parsed.interval == 1 ? "Every month on the \(dayText)" : "Every \(parsed.interval) months on the \(dayText)"
        case .yearly:
            let dateText = monthDayText(for: anchorDate)
            return parsed.interval == 1 ? "Every year on \(dateText)" : "Every \(parsed.interval) years on \(dateText)"
        }
    }

    private func recurrencePresetIsSelected(_ preset: RecurrencePreset) -> Bool {
        guard recurrenceIsEnabled else { return false }
        switch preset {
        case .daily:
            return normalizedRecurrenceRule == "FREQ=DAILY"
        case .weekly:
            return normalizedRecurrenceRule == "FREQ=WEEKLY;BYDAY=\(weekdayToken(for: recurrenceAnchorDate()))"
        case .weekday:
            return normalizedRecurrenceRule == "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
        case .monthly:
            return normalizedRecurrenceRule == "FREQ=MONTHLY"
        case .yearly:
            return normalizedRecurrenceRule == "FREQ=YEARLY"
        case .custom:
            return ![
                "FREQ=DAILY",
                "FREQ=WEEKLY;BYDAY=\(weekdayToken(for: recurrenceAnchorDate()))",
                "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR",
                "FREQ=MONTHLY",
                "FREQ=YEARLY",
            ].contains(normalizedRecurrenceRule)
        }
    }

    private func recurrenceTitle(for preset: RecurrencePreset) -> String {
        let anchorDate = recurrenceAnchorDate()
        switch preset {
        case .daily:
            return "Every day"
        case .weekly:
            return "Every week on \(weekdayShortText(for: anchorDate))"
        case .weekday:
            return "Every weekday"
        case .monthly:
            return "Every month on the \(ordinal(dayOfMonth(from: anchorDate)))"
        case .yearly:
            return "Every year on \(monthDayText(for: anchorDate))"
        case .custom:
            return "Custom"
        }
    }

    private func recurrenceIconName(for preset: RecurrencePreset) -> String {
        switch preset {
        case .daily:
            return "arrow.clockwise"
        case .weekly:
            return "calendar"
        case .weekday:
            return "calendar.badge.clock"
        case .monthly:
            return "calendar.circle"
        case .yearly:
            return "sparkles"
        case .custom:
            return "slider.horizontal.3"
        }
    }

    private func recurrenceAnchorDate() -> Date {
        let baseDate = hasDate ? date : Date()
        return Calendar.current.startOfDay(for: baseDate)
    }

    private func recurrenceUnitText() -> String {
        let singular: String
        let plural: String
        switch recurrenceFrequency {
        case .none, .daily:
            singular = "day"
            plural = "days"
        case .weekly:
            singular = "week"
            plural = "weeks"
        case .monthly:
            singular = "month"
            plural = "months"
        case .yearly:
            singular = "year"
            plural = "years"
        }
        return recurrenceInterval == 1 ? singular : plural
    }

    private func dayOfMonth(from date: Date) -> Int {
        Calendar.current.component(.day, from: date)
    }

    private func monthDayText(for date: Date) -> String {
        date.formatted(Date.FormatStyle().month(.abbreviated).day())
    }

    private func weekdayShortText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }

    private func weekdayToken(for date: Date) -> String {
        switch Calendar.current.component(.weekday, from: date) {
        case 1: "SU"
        case 2: "MO"
        case 3: "TU"
        case 4: "WE"
        case 5: "TH"
        case 6: "FR"
        case 7: "SA"
        default: "MO"
        }
    }

    private func weekdayShortText(fromToken token: String) -> String? {
        switch token {
        case "MO": "Mon"
        case "TU": "Tue"
        case "WE": "Wed"
        case "TH": "Thu"
        case "FR": "Fri"
        case "SA": "Sat"
        case "SU": "Sun"
        default: nil
        }
    }

    private func ordinal(_ day: Int) -> String {
        let mod100 = day % 100
        let suffix = if (11 ... 13).contains(mod100) {
            "th"
        } else {
            switch day % 10 {
            case 1: "st"
            case 2: "nd"
            case 3: "rd"
            default: "th"
            }
        }
        return "\(day)\(suffix)"
    }
}

#Preview("Due") {
    DateChooserPreviewHost(context: .due, timeMode: .optional)
        .environment(ThemeManager())
        .padding()
}

#Preview("Scheduled") {
    DateChooserPreviewHost(context: .scheduled, timeMode: .hidden)
        .environment(ThemeManager())
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
