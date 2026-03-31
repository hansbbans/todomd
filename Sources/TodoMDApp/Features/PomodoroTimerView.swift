import SwiftUI

private enum PomodoroPreset: String, CaseIterable, Identifiable {
    case standard
    case doubleStack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard:
            return "25/5"
        case .doubleStack:
            return "50/10"
        }
    }

    var focusSeconds: Int {
        switch self {
        case .standard:
            return 25 * 60
        case .doubleStack:
            return 50 * 60
        }
    }

    var breakSeconds: Int {
        switch self {
        case .standard:
            return 5 * 60
        case .doubleStack:
            return 10 * 60
        }
    }
}

private enum PomodoroPhase: String {
    case focus
    case breakTime = "break"

    var title: String {
        switch self {
        case .focus:
            return "Focus"
        case .breakTime:
            return "Break"
        }
    }

    var next: PomodoroPhase {
        switch self {
        case .focus:
            return .breakTime
        case .breakTime:
            return .focus
        }
    }
}

struct PomodoroTimerView<Header: View>: View {
    let showsHeader: Bool
    let header: Header
    @Environment(\.colorScheme) private var colorScheme
    @Environment(ThemeManager.self) private var theme
    @AppStorage("settings_pomodoro_mode") private var modeRawValue = PomodoroPreset.standard.rawValue
    @AppStorage("settings_pomodoro_auto_start_next") private var autoStartNext = false
    @AppStorage("settings_pomodoro_phase") private var phaseRawValue = PomodoroPhase.focus.rawValue
    @AppStorage("settings_pomodoro_is_running") private var isRunning = false
    @AppStorage("settings_pomodoro_remaining_seconds") private var remainingSeconds = 25 * 60
    @AppStorage("settings_pomodoro_end_timestamp") private var endTimestamp = 0.0

    @State private var now = Date()
    @ScaledMetric(relativeTo: .largeTitle) private var timerFontSize = 56
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(
        showsHeader: Bool = false,
        @ViewBuilder header: () -> Header
    ) {
        self.showsHeader = showsHeader
        self.header = header()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if showsHeader {
                    header
                }

                timerCard
                controlsCard
                sessionCard
            }
            .padding(.horizontal, showsHeader ? 24 : 16)
            .padding(.top, showsHeader ? 72 : 18)
            .padding(.bottom, 108)
        }
        .background(theme.backgroundColor.ignoresSafeArea())
        .onAppear {
            sanitizeState(referenceDate: Date())
        }
        .onReceive(ticker) { timestamp in
            now = timestamp
            reconcileTimer(referenceDate: timestamp)
        }
        .onChange(of: modeRawValue) { _, _ in
            applyPresetChange()
        }
    }

    private var timerCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Label(currentPhase.title, systemImage: currentPhase == .focus ? "flame.fill" : "cup.and.saucer.fill")
                    .font(.headline)
                    .foregroundStyle(phaseTint)

                Spacer(minLength: 0)

                Text(isRunning ? "Running" : "Paused")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.textSecondaryColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(theme.backgroundColor.opacity(colorScheme == .dark ? 0.82 : 0.94))
                    )
            }

            Text(formattedTime(displayedRemainingSeconds))
                .font(.system(size: timerFontSize, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.textPrimaryColor)
                .minimumScaleFactor(0.55)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(accessibilityRemainingTime)

            ProgressView(value: progressValue)
                .tint(phaseTint)
                .accessibilityLabel("Session progress")
                .accessibilityValue(Text(progressValue.formatted(.percent.precision(.fractionLength(0)))))

            Text(phaseSummary)
                .font(.subheadline)
                .foregroundStyle(theme.textSecondaryColor)
                .fixedSize(horizontal: false, vertical: true)

            Text(currentPresetSummary)
                .font(.footnote)
                .foregroundStyle(theme.textTertiaryColor)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            ThingsSurfaceBackdrop(
                kind: .elevatedCard,
                theme: theme,
                colorScheme: colorScheme
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: ThingsSurfaceKind.elevatedCard.cornerRadius, style: .continuous))
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Controls")
                .font(.headline)
                .foregroundStyle(theme.textPrimaryColor)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    startPauseButton
                    resetButton
                    skipBreakButton
                }

                VStack(alignment: .leading, spacing: 10) {
                    startPauseButton
                    resetButton
                    skipBreakButton
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            ThingsSurfaceBackdrop(
                kind: .elevatedCard,
                theme: theme,
                colorScheme: colorScheme
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: ThingsSurfaceKind.elevatedCard.cornerRadius, style: .continuous))
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Session")
                .font(.headline)
                .foregroundStyle(theme.textPrimaryColor)

            Picker("Session preset", selection: $modeRawValue) {
                ForEach(PomodoroPreset.allCases) { preset in
                    Text(preset.title).tag(preset.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Start the next session automatically", isOn: $autoStartNext)

            Text("Standard runs 25 minutes of focus with a 5 minute break. Double Stack runs 50 and 10.")
                .font(.footnote)
                .foregroundStyle(theme.textSecondaryColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            ThingsSurfaceBackdrop(
                kind: .elevatedCard,
                theme: theme,
                colorScheme: colorScheme
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: ThingsSurfaceKind.elevatedCard.cornerRadius, style: .continuous))
    }

    private var startPauseButton: some View {
        Button(isRunning ? "Pause Session" : "Start Session", systemImage: isRunning ? "pause.fill" : "play.fill") {
            isRunning ? pauseTimer() : startTimer()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var resetButton: some View {
        Button("Reset", systemImage: "arrow.counterclockwise", action: resetTimer)
            .buttonStyle(.bordered)
            .controlSize(.large)
    }

    private var skipBreakButton: some View {
        Button("Skip Break", systemImage: "forward.fill", action: skipBreak)
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(currentPhase != .breakTime)
    }

    private var phaseTint: Color {
        currentPhase == .focus ? theme.accentColor : .green
    }

    private var phaseSummary: String {
        currentPhase == .focus
            ? "Stay with one task until the timer ends."
            : "Take a short reset before you start another focus block."
    }

    private var currentPresetSummary: String {
        "\(currentPreset.focusSeconds / 60) minutes of focus, \(currentPreset.breakSeconds / 60) minute break."
    }

    private var accessibilityRemainingTime: String {
        let totalSeconds = displayedRemainingSeconds
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes) minute\(minutes == 1 ? "" : "s"), \(seconds) second\(seconds == 1 ? "" : "s") remaining"
    }

    private var currentPreset: PomodoroPreset {
        PomodoroPreset(rawValue: modeRawValue) ?? .standard
    }

    private var currentPhase: PomodoroPhase {
        PomodoroPhase(rawValue: phaseRawValue) ?? .focus
    }

    private var displayedRemainingSeconds: Int {
        if isRunning, endTimestamp > 0 {
            let remaining = Int(ceil(endTimestamp - now.timeIntervalSince1970))
            return max(0, remaining)
        }
        return max(0, remainingSeconds)
    }

    private var progressValue: Double {
        let total = max(1, duration(for: currentPhase, preset: currentPreset))
        let remaining = min(total, max(0, displayedRemainingSeconds))
        return Double(total - remaining) / Double(total)
    }

    private func duration(for phase: PomodoroPhase, preset: PomodoroPreset) -> Int {
        switch phase {
        case .focus:
            return preset.focusSeconds
        case .breakTime:
            return preset.breakSeconds
        }
    }

    private func formattedTime(_ totalSeconds: Int) -> String {
        let seconds = max(0, totalSeconds)
        let minutesPart = seconds / 60
        let secondsPart = seconds % 60
        return String(format: "%02d:%02d", minutesPart, secondsPart)
    }

    private func sanitizeState(referenceDate: Date) {
        now = referenceDate

        let preset = currentPreset
        if PomodoroPreset(rawValue: modeRawValue) == nil {
            modeRawValue = PomodoroPreset.standard.rawValue
        }

        let phase = currentPhase
        if PomodoroPhase(rawValue: phaseRawValue) == nil {
            phaseRawValue = PomodoroPhase.focus.rawValue
        }

        if remainingSeconds <= 0 {
            remainingSeconds = duration(for: phase, preset: preset)
        }

        reconcileTimer(referenceDate: referenceDate)
    }

    private func reconcileTimer(referenceDate: Date) {
        guard isRunning else { return }
        guard endTimestamp > 0 else {
            isRunning = false
            remainingSeconds = max(1, duration(for: currentPhase, preset: currentPreset))
            return
        }

        let preset = currentPreset
        var phase = currentPhase
        var end = endTimestamp
        var transitions = 0

        while referenceDate.timeIntervalSince1970 >= end {
            phase = phase.next
            transitions += 1

            if !autoStartNext {
                isRunning = false
                endTimestamp = 0
                phaseRawValue = phase.rawValue
                remainingSeconds = duration(for: phase, preset: preset)
                now = referenceDate
                return
            }

            end += Double(duration(for: phase, preset: preset))

            if transitions > 720 {
                break
            }
        }

        if transitions > 0 {
            phaseRawValue = phase.rawValue
            endTimestamp = end
        }

        let remaining = max(0, Int(ceil(end - referenceDate.timeIntervalSince1970)))
        remainingSeconds = remaining
    }

    private func startTimer() {
        let baseline = max(1, displayedRemainingSeconds)
        remainingSeconds = baseline
        endTimestamp = Date().timeIntervalSince1970 + Double(baseline)
        isRunning = true
        now = Date()
    }

    private func pauseTimer() {
        let remaining = max(0, displayedRemainingSeconds)
        remainingSeconds = remaining
        isRunning = false
        endTimestamp = 0
    }

    private func resetTimer() {
        let preset = currentPreset
        phaseRawValue = PomodoroPhase.focus.rawValue
        remainingSeconds = duration(for: .focus, preset: preset)
        isRunning = false
        endTimestamp = 0
        now = Date()
    }

    private func skipBreak() {
        guard currentPhase == .breakTime else { return }

        let preset = currentPreset
        let focusDuration = duration(for: .focus, preset: preset)

        phaseRawValue = PomodoroPhase.focus.rawValue
        remainingSeconds = focusDuration

        if isRunning {
            endTimestamp = Date().timeIntervalSince1970 + Double(focusDuration)
        } else {
            endTimestamp = 0
        }

        now = Date()
    }

    private func applyPresetChange() {
        guard let preset = PomodoroPreset(rawValue: modeRawValue) else {
            modeRawValue = PomodoroPreset.standard.rawValue
            resetTimer()
            return
        }

        phaseRawValue = PomodoroPhase.focus.rawValue
        remainingSeconds = preset.focusSeconds
        isRunning = false
        endTimestamp = 0
        now = Date()
    }
}

extension PomodoroTimerView where Header == EmptyView {
    init() {
        self.init(showsHeader: false) {
            EmptyView()
        }
    }
}
