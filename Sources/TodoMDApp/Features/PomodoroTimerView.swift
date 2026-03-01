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

struct PomodoroTimerView: View {
    @AppStorage("settings_pomodoro_mode") private var modeRawValue = PomodoroPreset.standard.rawValue
    @AppStorage("settings_pomodoro_auto_start_next") private var autoStartNext = false
    @AppStorage("settings_pomodoro_phase") private var phaseRawValue = PomodoroPhase.focus.rawValue
    @AppStorage("settings_pomodoro_is_running") private var isRunning = false
    @AppStorage("settings_pomodoro_remaining_seconds") private var remainingSeconds = 25 * 60
    @AppStorage("settings_pomodoro_end_timestamp") private var endTimestamp = 0.0

    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(currentPhase.title)
                        .font(.title3.weight(.semibold))

                    Text(formattedTime(displayedRemainingSeconds))
                        .font(.system(size: 56, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ProgressView(value: progressValue)
                        .tint(currentPhase == .focus ? .blue : .green)

                    Text(currentPhase == .focus ? "Stay on task." : "Take a short break.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button(isRunning ? "Pause" : "Start") {
                        isRunning ? pauseTimer() : startTimer()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Reset") {
                        resetTimer()
                    }
                    .buttonStyle(.bordered)

                    Button("Skip Break") {
                        skipBreak()
                    }
                    .buttonStyle(.bordered)
                    .disabled(currentPhase != .breakTime)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Session")
                        .font(.headline)

                    Picker("Session preset", selection: $modeRawValue) {
                        ForEach(PomodoroPreset.allCases) { preset in
                            Text(preset.title).tag(preset.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Auto-start next session", isOn: $autoStartNext)
                }
            }
            .padding()
        }
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
