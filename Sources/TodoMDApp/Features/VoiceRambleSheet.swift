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
    private var lastAvailableProjects: [String] = []
    private var shouldSkipAutostartForUITests: Bool {
        ProcessInfo.processInfo.environment["TODOMD_UI_TEST_DISABLE_VOICE_RAMBLE_AUTOSTART"] == "1"
    }
    private var shouldUseFakeRecordingForUITests: Bool {
        ProcessInfo.processInfo.environment["TODOMD_UI_TEST_FAKE_VOICE_RAMBLE"] == "1"
    }

    private var fakeTranscript: String {
        ProcessInfo.processInfo.environment["TODOMD_UI_TEST_FAKE_VOICE_RAMBLE_TRANSCRIPT"] ?? ""
    }

    func start(availableProjects: [String]) async {
        recordingSessionID &+= 1
        let sessionID = recordingSessionID
        lastAvailableProjects = availableProjects
        errorMessage = nil
        permissionMessage = nil

        if shouldUseFakeRecordingForUITests {
            teardownRecordingSession()
            transcript = fakeTranscript
            reparse(availableProjects: availableProjects, segments: fakeSegments(from: fakeTranscript))
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
                    let segments = result.bestTranscription.segments.map {
                        VoiceRambleSegment(text: $0.substring, startTime: $0.timestamp, duration: $0.duration)
                    }
                    self.reparse(availableProjects: availableProjects, segments: segments)
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

    func updateDraft(_ updated: VoiceRambleTaskDraft) {
        guard let index = drafts.firstIndex(where: { $0.id == updated.id }) else { return }
        drafts[index] = updated
    }

    func deleteDraft(id: UUID) {
        drafts.removeAll { $0.id == id }
    }

    func mergeDraftIntoPrevious(id: UUID) {
        guard let index = drafts.firstIndex(where: { $0.id == id }), index > 0 else { return }
        var previous = drafts[index - 1]
        let current = drafts[index]

        previous.title = normalizeWhitespace("\(previous.title) \(current.title)")
        previous.project = previous.project ?? current.project
        previous.priority = previous.priority ?? current.priority
        previous.due = previous.due ?? current.due
        previous.dueTime = previous.dueTime ?? current.dueTime
        previous.tags = normalizeTags(previous.tags + current.tags)
        previous.estimatedMinutes = previous.estimatedMinutes ?? current.estimatedMinutes
        previous.confidence = min(previous.confidence, current.confidence, 0.7)
        previous.warning = "Merged tasks. Review before saving."
        previous.sourceText = normalizeWhitespace("\(previous.sourceText) \(current.sourceText)")

        drafts[index - 1] = previous
        drafts.remove(at: index)
    }

    func splitDraft(id: UUID) {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        let draft = drafts[index]
        let suggestions = splitSuggestions(for: draft)
        guard suggestions.count == 2 else { return }

        var first = suggestions[0]
        var second = suggestions[1]

        first = finalizeSplitDraft(first, inheriting: draft, warning: "Split from one spoken draft. Review before saving.")
        second = finalizeSplitDraft(second, inheriting: draft, warning: "Split from one spoken draft. Review before saving.")

        drafts[index] = first
        drafts.insert(second, at: index + 1)
    }

    private func finalizeSplitDraft(
        _ draft: VoiceRambleTaskDraft,
        inheriting source: VoiceRambleTaskDraft,
        warning: String
    ) -> VoiceRambleTaskDraft {
        VoiceRambleTaskDraft(
            title: draft.title,
            due: draft.due,
            dueTime: draft.dueTime,
            priority: draft.priority ?? source.priority,
            project: draft.project ?? source.project,
            tags: normalizeTags(draft.tags.isEmpty ? source.tags : draft.tags),
            estimatedMinutes: draft.estimatedMinutes,
            confidence: min(draft.confidence, 0.68),
            warning: warning,
            sourceText: draft.sourceText
        )
    }

    private func splitSuggestions(for draft: VoiceRambleTaskDraft) -> [VoiceRambleTaskDraft] {
        let sourceText = draft.sourceText.isEmpty ? draft.title : draft.sourceText
        let pieces = manualSplitPieces(from: sourceText)
        guard pieces.count == 2 else { return [] }

        let parser = VoiceRambleParser(availableProjects: lastAvailableProjects)
        return pieces.compactMap { piece in
            parser.parse(piece).first ?? VoiceRambleTaskDraft(title: piece, sourceText: piece)
        }
    }

    private func manualSplitPieces(from sourceText: String) -> [String] {
        let normalized = normalizeWhitespace(sourceText)
        guard !normalized.isEmpty else { return [] }

        let separatorPatterns = [
            #"\s+\band\b\s+"#,
            #"\s+\balso\b\s+"#,
            #"\s+\bplus\b\s+"#
        ]

        for pattern in separatorPatterns {
            if let range = normalized.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                let first = normalizeWhitespace(String(normalized[..<range.lowerBound]))
                let second = normalizeWhitespace(String(normalized[range.upperBound...]))
                if !first.isEmpty, !second.isEmpty {
                    return [first, second]
                }
            }
        }

        let words = normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard words.count >= 4 else { return [] }
        let midpoint = max(1, words.count / 2)
        let first = words[..<midpoint].joined(separator: " ")
        let second = words[midpoint...].joined(separator: " ")
        return [normalizeWhitespace(first), normalizeWhitespace(second)].filter { !$0.isEmpty }
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

    private func reparse(availableProjects: [String], segments: [VoiceRambleSegment] = []) {
        lastAvailableProjects = availableProjects
        let parser = VoiceRambleParser(availableProjects: availableProjects)
        drafts = parser.parse(transcript, segments: segments)
    }

    private func fakeSegments(from transcript: String) -> [VoiceRambleSegment] {
        let groups = transcript
            .components(separatedBy: "||")
            .map { normalizeWhitespace($0) }
            .filter { !$0.isEmpty }

        var segments: [VoiceRambleSegment] = []
        var timestamp: TimeInterval = 0
        let sourceGroups = groups.isEmpty ? [normalizeWhitespace(transcript)] : groups

        for group in sourceGroups where !group.isEmpty {
            for word in group.split(whereSeparator: { $0.isWhitespace }) {
                let text = String(word)
                segments.append(VoiceRambleSegment(text: text, startTime: timestamp, duration: 0.18))
                timestamp += 0.22
            }
            timestamp += 1.0
        }

        return segments
    }

    private func normalizeWhitespace(_ value: String) -> String {
        value
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { rawTag in
            let normalized = rawTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return normalized
        }
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

private struct VoiceRambleDraftEditorState: Identifiable {
    let id: UUID
    var title: String
    var due: String
    var dueTime: String
    var project: String
    var priority: TaskPriority?
    var tags: String
    var estimatedMinutes: String

    init(draft: VoiceRambleTaskDraft) {
        id = draft.id
        title = draft.title
        due = draft.due?.isoString ?? ""
        dueTime = draft.dueTime?.isoString ?? ""
        project = draft.project ?? ""
        priority = draft.priority
        tags = draft.tags.joined(separator: ", ")
        if let estimatedMinutes = draft.estimatedMinutes {
            self.estimatedMinutes = String(estimatedMinutes)
        } else {
            self.estimatedMinutes = ""
        }
    }

    func validationError() -> String? {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Title is required."
        }

        if !due.isEmpty && (try? LocalDate(isoDate: due)) == nil {
            return "Due date must use YYYY-MM-DD."
        }

        if !dueTime.isEmpty && due.isEmpty {
            return "Add a due date before adding a time."
        }

        if !dueTime.isEmpty && (try? LocalTime(isoTime: dueTime)) == nil {
            return "Due time must use HH:MM."
        }

        if !estimatedMinutes.isEmpty, Int(estimatedMinutes) == nil {
            return "Estimated minutes must be a number."
        }

        return nil
    }

    func apply(to draft: VoiceRambleTaskDraft) -> VoiceRambleTaskDraft? {
        guard validationError() == nil else { return nil }

        let parsedDue = due.isEmpty ? nil : (try? LocalDate(isoDate: due))
        let parsedDueTime = dueTime.isEmpty ? nil : (try? LocalTime(isoTime: dueTime))
        let parsedEstimatedMinutes = estimatedMinutes.isEmpty ? nil : Int(estimatedMinutes)
        let parsedTags = tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        return VoiceRambleTaskDraft(
            id: draft.id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            due: parsedDue,
            dueTime: parsedDueTime,
            priority: priority,
            project: project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : project.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: parsedTags,
            estimatedMinutes: parsedEstimatedMinutes,
            confidence: 1,
            warning: nil,
            sourceText: title.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

struct VoiceRambleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var theme: ThemeManager

    @StateObject private var controller = VoiceRambleController()
    @State private var draftEditor: VoiceRambleDraftEditorState?

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
        .sheet(item: $draftEditor) { editor in
            draftEditorSheet(editor)
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
                    Text("Speak naturally. You can say “actually”, “change the second one”, or “same project as the last one” to correct drafts.")
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
                if let warningCount = previewWarningCount, warningCount > 0 {
                    Text("\(warningCount) draft\(warningCount == 1 ? " needs" : "s need") a quick review.")
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("voiceRamble.warningSummary")
                }

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(Array(controller.drafts.enumerated()), id: \.element.id) { index, draft in
                            draftCard(draft, index: index)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 320)
            }
        }
    }

    private var previewWarningCount: Int? {
        let count = controller.drafts.filter { $0.warning != nil }.count
        return count == 0 ? nil : count
    }

    private func draftCard(_ draft: VoiceRambleTaskDraft, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
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

                    if let warning = draft.warning {
                        Text(warning)
                            .font(.system(.footnote, design: .rounded).weight(.semibold))
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("voiceRamble.warning.\(index)")
                    } else {
                        Text("Confidence \(Int((draft.confidence * 100).rounded()))%")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(theme.textSecondaryColor)
                    }
                }

                VStack(alignment: .trailing, spacing: 8) {
                    previewActionButton(title: "Edit", systemImage: "pencil", identifier: "voiceRamble.editButton.\(index)") {
                        draftEditor = VoiceRambleDraftEditorState(draft: draft)
                    }

                    previewActionButton(title: "Split", systemImage: "square.split.2x1", identifier: "voiceRamble.splitButton.\(index)") {
                        controller.splitDraft(id: draft.id)
                    }
                    .disabled(!canSplit(draft))

                    previewActionButton(title: "Merge", systemImage: "arrow.up.left.and.arrow.down.right", identifier: "voiceRamble.mergeButton.\(index)") {
                        controller.mergeDraftIntoPrevious(id: draft.id)
                    }
                    .disabled(index == 0)

                    previewActionButton(title: "Delete", systemImage: "trash", identifier: "voiceRamble.deleteButton.\(index)") {
                        controller.deleteDraft(id: draft.id)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.surfaceColor.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(draft.warning == nil ? theme.textSecondaryColor.opacity(0.18) : Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    private func previewActionButton(
        title: String,
        systemImage: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(minWidth: 86)
                .background(
                    Capsule(style: .continuous)
                        .fill(theme.backgroundColor.opacity(0.95))
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func canSplit(_ draft: VoiceRambleTaskDraft) -> Bool {
        let source = draft.sourceText.isEmpty ? draft.title : draft.sourceText
        return source.split(whereSeparator: { $0.isWhitespace }).count >= 4
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
            .accessibilityIdentifier("voiceRamble.addTasksButton")
        }
    }

    private func draftEditorSheet(_ initialState: VoiceRambleDraftEditorState) -> some View {
        VoiceRambleDraftEditorView(theme: theme, initialState: initialState) { updatedState in
            guard let existing = controller.drafts.first(where: { $0.id == updatedState.id }),
                  let updated = updatedState.apply(to: existing) else {
                return
            }

            controller.updateDraft(updated)
            draftEditor = nil
        } onCancel: {
            draftEditor = nil
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

private struct VoiceRambleDraftEditorView: View {
    let theme: ThemeManager
    let onSave: (VoiceRambleDraftEditorState) -> Void
    let onCancel: () -> Void

    @State private var state: VoiceRambleDraftEditorState

    init(
        theme: ThemeManager,
        initialState: VoiceRambleDraftEditorState,
        onSave: @escaping (VoiceRambleDraftEditorState) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.theme = theme
        self.onSave = onSave
        self.onCancel = onCancel
        _state = State(initialValue: initialState)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $state.title)
                        .accessibilityIdentifier("voiceRamble.editor.titleField")
                    TextField("Project", text: $state.project)
                        .accessibilityIdentifier("voiceRamble.editor.projectField")
                }

                Section("Schedule") {
                    TextField("Due date (YYYY-MM-DD)", text: $state.due)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("voiceRamble.editor.dueField")
                    TextField("Due time (HH:MM)", text: $state.dueTime)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("voiceRamble.editor.dueTimeField")
                }

                Section("Details") {
                    Picker("Priority", selection: Binding(get: {
                        state.priority ?? TaskPriority.none
                    }, set: { newValue in
                        state.priority = newValue == TaskPriority.none ? nil : newValue
                    })) {
                        Text("None").tag(TaskPriority.none)
                        ForEach(TaskPriority.allCases.filter { $0 != .none }, id: \.self) { priority in
                            Text(priority.rawValue.capitalized).tag(priority)
                        }
                    }
                    .accessibilityIdentifier("voiceRamble.editor.priorityPicker")

                    TextField("Tags (comma separated)", text: $state.tags)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("voiceRamble.editor.tagsField")

                    TextField("Estimated minutes", text: $state.estimatedMinutes)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("voiceRamble.editor.estimateField")
                }

                if let validationError = state.validationError() {
                    Section {
                        Text(validationError)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("voiceRamble.editor.validationError")
                    }
                }
            }
            .navigationTitle("Edit Draft")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(state)
                    }
                    .disabled(state.validationError() != nil)
                    .accessibilityIdentifier("voiceRamble.editor.saveButton")
                }
            }
        }
        .tint(theme.accentColor)
    }
}
