import AVFoundation
@preconcurrency import Speech
import SwiftUI

@MainActor
final class VoiceRambleController: ObservableObject {
    @Published var transcript = ""
    @Published var drafts: [VoiceRambleTaskDraft] = []
    @Published var isRecording = false
    @Published var errorMessage: String?
    @Published var permissionMessage: String?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer = SFSpeechRecognizer()
    private var recordingSessionID: UInt64 = 0
    private var shouldSkipAutostartForUITests: Bool {
        ProcessInfo.processInfo.environment["TODOMD_UI_TEST_DISABLE_VOICE_RAMBLE_AUTOSTART"] == "1"
    }
    private var shouldUseFakeRecordingForUITests: Bool {
        ProcessInfo.processInfo.environment["TODOMD_UI_TEST_FAKE_VOICE_RAMBLE"] == "1"
    }

    func start(availableProjects: [String]) async {
        recordingSessionID &+= 1
        let sessionID = recordingSessionID
        errorMessage = nil
        permissionMessage = nil

        if shouldUseFakeRecordingForUITests {
            teardownRecordingSession()
            isRecording = true
            return
        }

        if shouldSkipAutostartForUITests {
            return
        }

        let speechStatus = await Self.requestSpeechPermission()
        guard !Task.isCancelled, isCurrentSession(sessionID) else { return }
        guard speechStatus == .authorized else {
            permissionMessage = permissionMessage(for: speechStatus)
            return
        }

        let microphoneGranted = await Self.requestMicrophonePermission()
        guard !Task.isCancelled, isCurrentSession(sessionID) else { return }
        guard microphoneGranted else {
            permissionMessage = "Microphone access is required for voice ramble."
            return
        }

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition is not available right now."
            return
        }

        teardownRecordingSession()

        do {
            try configureAudioSessionIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        guard !Task.isCancelled, isCurrentSession(sessionID) else {
            teardownRecordingSession()
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [request] buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            errorMessage = error.localizedDescription
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                guard self.isCurrentSession(sessionID) else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.reparse(availableProjects: availableProjects)
                    if result.isFinal {
                        self.stop()
                    }
                }

                if let error {
                    self.errorMessage = error.localizedDescription
                    self.stop()
                }
            }
        }

        guard isCurrentSession(sessionID) else {
            teardownRecordingSession()
            return
        }
        isRecording = true
    }

    func stop() {
        recordingSessionID &+= 1
        teardownRecordingSession()
    }

    private func teardownRecordingSession() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false

        deactivateAudioSessionIfNeeded()
    }

    private func isCurrentSession(_ sessionID: UInt64) -> Bool {
        recordingSessionID == sessionID
    }

    func clear() {
        stop()
        transcript = ""
        drafts = []
        errorMessage = nil
        permissionMessage = nil
    }

    private func reparse(availableProjects: [String]) {
        let parser = VoiceRambleParser(availableProjects: availableProjects)
        drafts = parser.parse(transcript)
    }

    private nonisolated static func requestSpeechPermission() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private nonisolated static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            #if os(iOS)
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            #else
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
            #endif
        }
    }

    private func configureAudioSessionIfNeeded() throws {
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func deactivateAudioSessionIfNeeded() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func permissionMessage(for status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .denied:
            return "Speech recognition access is denied. Enable it in Settings to use voice ramble."
        case .restricted:
            return "Speech recognition is restricted on this device."
        case .notDetermined:
            return "Speech recognition permission is required for voice ramble."
        case .authorized:
            return ""
        @unknown default:
            return "Speech recognition is unavailable."
        }
    }
}

struct VoiceRambleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var theme: ThemeManager

    @StateObject private var controller = VoiceRambleController()

    let fallbackDue: LocalDate?
    let fallbackDueTime: LocalTime?
    let fallbackPriority: TaskPriority?
    let fallbackFlagged: Bool
    let fallbackTags: [String]
    let fallbackArea: String?
    let fallbackProject: String?
    let defaultView: BuiltInView?
    let onClose: () -> Void
    let onTasksCreated: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                transcriptCard
                previewSection
                Spacer(minLength: 0)
                actionRow
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .accessibilityIdentifier("voiceRamble.sheet")
            .navigationTitle("Voice Ramble")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onClose()
                        dismiss()
                    }
                    .accessibilityIdentifier("voiceRamble.closeButton")
                }
            }
        }
        .presentationDetents([.large])
        .task {
            if controller.transcript.isEmpty && controller.permissionMessage == nil && controller.errorMessage == nil {
                await controller.start(availableProjects: container.allProjects())
            }
        }
        .onDisappear {
            controller.stop()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill((controller.isRecording ? Color.red : theme.textSecondaryColor).opacity(0.18))
                        .frame(width: 42, height: 42)
                    Image(systemName: controller.isRecording ? "waveform.circle.fill" : "mic.circle")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(controller.isRecording ? Color.red : theme.textPrimaryColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(controller.isRecording ? "Listening for tasks" : "Ready to capture")
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                    Text("Say multiple tasks naturally. Use “actually …” to replace the last one or “remove that” to delete it.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(theme.textSecondaryColor)
                }
            }

            if let message = controller.permissionMessage, !message.isEmpty {
                Text(message)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.red)
            } else if let errorMessage = controller.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(theme.surfaceColor.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.textSecondaryColor.opacity(0.22), lineWidth: 1)
        )
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transcript")
                .font(.system(.headline, design: .rounded).weight(.semibold))

            Text(controller.transcript.isEmpty ? "Start speaking to preview parsed tasks here." : controller.transcript)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(controller.transcript.isEmpty ? theme.textSecondaryColor : theme.textPrimaryColor)
                .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(theme.backgroundColor.opacity(0.9))
                )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(theme.surfaceColor.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.textSecondaryColor.opacity(0.22), lineWidth: 1)
        )
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Preview")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                Spacer()
                Text("\(controller.drafts.count) task\(controller.drafts.count == 1 ? "" : "s")")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(theme.textSecondaryColor)
            }

            if controller.drafts.isEmpty {
                Text("Detected tasks will appear here as you speak.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(theme.textSecondaryColor)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(controller.drafts) { draft in
                            draftCard(draft)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 260)
            }
        }
    }

    private func draftCard(_ draft: VoiceRambleTaskDraft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(draft.title)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(theme.textPrimaryColor)
                .frame(maxWidth: .infinity, alignment: .leading)

            let metadata = metadataLine(for: draft)
            if !metadata.isEmpty {
                Text(metadata)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(theme.textSecondaryColor)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.surfaceColor.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.textSecondaryColor.opacity(0.18), lineWidth: 1)
        )
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    if controller.isRecording {
                        controller.stop()
                    } else {
                        await controller.start(availableProjects: container.allProjects())
                    }
                }
            } label: {
                Label(controller.isRecording ? "Stop" : "Record", systemImage: controller.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(controller.isRecording ? Color.red : theme.accentColor)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("voiceRamble.recordButton")

            Button {
                saveDrafts()
            } label: {
                Label("Add Tasks", systemImage: "arrow.up")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(controller.drafts.isEmpty ? theme.textSecondaryColor.opacity(0.45) : theme.accentColor)
                    )
            }
            .buttonStyle(.plain)
            .disabled(controller.drafts.isEmpty)
        }
    }

    private func metadataLine(for draft: VoiceRambleTaskDraft) -> String {
        var parts: [String] = []
        if let due = draft.due {
            var datePart = due.isoString
            if let dueTime = draft.dueTime {
                datePart += " \(dueTime.isoString)"
            }
            parts.append(datePart)
        } else if let fallbackDue {
            var datePart = fallbackDue.isoString
            if let fallbackDueTime {
                datePart += " \(fallbackDueTime.isoString)"
            }
            parts.append("default \(datePart)")
        }

        if let project = draft.project ?? fallbackProject {
            parts.append(project)
        }
        if let priority = draft.priority ?? fallbackPriority, priority != .none {
            parts.append(priority.rawValue.capitalized)
        }
        let tags = Array(Set(draft.tags + fallbackTags)).sorted()
        if !tags.isEmpty {
            parts.append(tags.map { "#\($0)" }.joined(separator: " "))
        }
        if let estimatedMinutes = draft.estimatedMinutes {
            parts.append("\(estimatedMinutes)m")
        }
        if fallbackFlagged {
            parts.append("Flagged")
        }
        return parts.joined(separator: "  •  ")
    }

    private func saveDrafts() {
        let created = container.createTasks(
            fromVoiceRambleDrafts: controller.drafts,
            fallbackDue: fallbackDue,
            fallbackDueTime: fallbackDueTime,
            fallbackPriority: fallbackPriority,
            flagged: fallbackFlagged,
            tags: fallbackTags,
            area: fallbackArea,
            project: fallbackProject,
            defaultView: defaultView
        )
        guard created > 0 else { return }
        controller.stop()
        onTasksCreated()
        dismiss()
    }
}
