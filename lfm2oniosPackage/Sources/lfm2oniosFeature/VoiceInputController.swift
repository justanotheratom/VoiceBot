import SwiftUI
import Observation

#if os(iOS)
import AVFoundation
import AVFAudio
#endif

@available(iOS 18.0, macOS 13.0, *)
@MainActor
@Observable
final class VoiceInputController {
    enum SpeechPermissionState: Equatable {
        case unknown
        case granted
        case denied
    }

    private let speechService: SpeechRecognitionService
    @ObservationIgnored private var errorDismissTask: Task<Void, Never>?
    @ObservationIgnored private var transcriptHandler: ((String) -> Void)?

    var isRecording = false
    var isRequestingSpeechPermission = false
    var isTranscribing = false
    var microphoneErrorMessage: String?
    var speechPermissionState: SpeechPermissionState = .unknown
    var hasPrefetchedSpeechPermission = false
    var isRequestingRecordPermission = false

#if os(iOS)
    var recordPermission: MicrophonePermissionState = .undetermined
#else
    var recordPermission: MicrophonePermissionState = .granted
#endif

    var recordingStartTime: Date?

    init(speechService: SpeechRecognitionService = SpeechRecognitionService()) {
        self.speechService = speechService
    }

    deinit {
        errorDismissTask?.cancel()
    }

    var status: MicrophoneInputBar.Status {
        if let message = microphoneErrorMessage {
            return .error(message: message)
        }
        if isTranscribing {
            return .transcribing
        }
        if isRecording {
            return .recording
        }
        if isRequestingSpeechPermission || isRequestingRecordPermission {
            return .requestingPermission
        }
        if recordPermission == .denied {
            return .disabled(message: "Enable microphone access in Settings")
        }
        switch speechPermissionState {
        case .denied:
            return .disabled(message: "Enable microphone & speech access in Settings")
        case .unknown, .granted:
            return .idle
        }
    }

    func isEnabled(isStreaming: Bool) -> Bool {
        let base = !isStreaming && speechPermissionState != .denied && !isTranscribing && !isRequestingSpeechPermission
        return base && !isRequestingRecordPermission && recordPermission == .granted
    }

    var feedback: (text: String, color: Color)? {
        switch status {
        case .disabled(let message):
            return (message, .secondary)
        case .error(let message):
            return (message, .orange)
        default:
            return nil
        }
    }

    func prefetchPermissionsIfNeeded() async {
        guard !hasPrefetchedSpeechPermission else { return }
        hasPrefetchedSpeechPermission = true

        let currentStatus = await speechService.authorizationStatus()
        updatePermissionState(with: currentStatus)
        clearMicrophoneError()

        switch currentStatus {
        case .authorized, .denied, .restricted:
            AppLogger.ui().log(event: "mic:permissionPrefetch", data: ["status": String(describing: currentStatus)])
        case .notDetermined:
            isRequestingSpeechPermission = true
            let requestedStatus = await speechService.requestAuthorization()
            isRequestingSpeechPermission = false
            updatePermissionState(with: requestedStatus)
            clearMicrophoneError()
            AppLogger.ui().log(event: "mic:permissionPrefetch", data: ["status": String(describing: requestedStatus)])
        }

        await requestRecordPermissionIfNeeded()
    }

    func startRecording(modelSlug: String, locale: Locale, onTranscript: @escaping (String) -> Void) async {
        guard !isRecording, !isTranscribing else { return }

#if os(iOS)
        if recordPermission == .undetermined && !isRequestingRecordPermission {
            await requestRecordPermissionIfNeeded()
        }
        guard recordPermission == .granted else {
            setMicrophoneError("Enable microphone access in Settings.", autoDismiss: false)
            AppLogger.ui().log(event: "mic:record:permissionDenied", data: ["type": "record"])
            return
        }
#endif

        recordingStartTime = nil
        let status = await speechService.authorizationStatus()
        updatePermissionState(with: status)

        if speechPermissionState == .unknown {
            isRequestingSpeechPermission = true
            let requestedStatus = await speechService.requestAuthorization()
            isRequestingSpeechPermission = false
            updatePermissionState(with: requestedStatus)
        }

        guard speechPermissionState == .granted else {
            setMicrophoneError("Microphone access is required to capture your voice.", autoDismiss: false)
            AppLogger.ui().log(event: "mic:permissionDenied", data: ["state": String(describing: speechPermissionState)])
            return
        }

        do {
            transcriptHandler = onTranscript
            try await speechService.start(locale: locale)
            isRecording = true
            clearMicrophoneError()
            recordingStartTime = Date()
            AppLogger.ui().log(event: "mic:record:start", data: ["model": modelSlug])
        } catch {
            isRecording = false
            await handleSpeechRecognitionError(error)
        }
    }

    func finishRecording(modelSlug: String) async {
        if isRequestingSpeechPermission {
            isRequestingSpeechPermission = false
            if speechPermissionState != .granted {
                setMicrophoneError("Enable microphone & speech recognition in Settings to use voice input.", autoDismiss: false)
                return
            }
        }

        guard isRecording else { return }

        isRecording = false
        isTranscribing = true

        do {
            let transcript = try await speechService.stop()
            isTranscribing = false

            let elapsedMs: Int?
            if let start = recordingStartTime {
                let duration = Date().timeIntervalSince(start)
                elapsedMs = Int(duration * 1000)
                if duration < 0.5 {
                    recordingStartTime = nil
                    setMicrophoneError("Hold the microphone a bit longer.")
#if os(iOS)
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
#endif
                    AppLogger.ui().log(event: "mic:record:tooShort", data: ["durationMs": elapsedMs ?? 0])
                    return
                }
            } else {
                elapsedMs = nil
            }

            recordingStartTime = nil

            let cleaned = transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !cleaned.isEmpty else {
                setMicrophoneError("I didn't catch that. Try speaking again.")
#if os(iOS)
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
#endif
                AppLogger.ui().log(event: "mic:record:empty", data: [:])
                return
            }

            clearMicrophoneError()
#if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
#endif
            AppLogger.ui().log(event: "mic:record:transcript", data: [
                "characters": cleaned.count,
                "durationMs": elapsedMs ?? -1
            ])

            let handler = transcriptHandler
            transcriptHandler = nil
            handler?(cleaned)
        } catch {
            isTranscribing = false
            await handleSpeechRecognitionError(error)
        }
    }

    func cancelActiveRecording() async {
        recordingStartTime = nil
        transcriptHandler = nil
        await speechService.cancel()
        isRecording = false
        isTranscribing = false
    }

    func clearMicrophoneError() {
        errorDismissTask?.cancel()
        microphoneErrorMessage = nil
    }

    private func setMicrophoneError(_ message: String, autoDismiss: Bool = true) {
        errorDismissTask?.cancel()
        microphoneErrorMessage = message

        guard autoDismiss else { return }

        errorDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.clearMicrophoneError()
            }
        }
    }

    private func updatePermissionState(with status: SpeechRecognitionService.AuthorizationStatus) {
        switch status {
        case .authorized:
            speechPermissionState = .granted
        case .denied, .restricted:
            speechPermissionState = .denied
        case .notDetermined:
            speechPermissionState = .unknown
        }
    }

    private func handleSpeechRecognitionError(_ error: Error) async {
        recordingStartTime = nil
#if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
#endif

        if let serviceError = error as? SpeechRecognitionService.ServiceError {
            switch serviceError {
            case .authorizationDenied:
                speechPermissionState = .denied
                setMicrophoneError("Microphone access is required to capture your voice.", autoDismiss: false)
            case .onDeviceRecognitionUnsupported:
                setMicrophoneError("On-device speech recognition isn't supported on this device.", autoDismiss: false)
            case .recognizerUnavailable:
                setMicrophoneError("Speech recognizer is currently unavailable.")
            case .audioEngineUnavailable:
                setMicrophoneError("Couldn't access the microphone. Please try again.")
            case .recognitionFailed(let message):
                setMicrophoneError(message)
            case .recognitionAlreadyRunning:
                setMicrophoneError("A recording session is already active.")
            case .noActiveRecognition:
                setMicrophoneError("No recording session to finish.")
            }
            AppLogger.ui().logError(event: "mic:record:error", error: serviceError)
        } else {
            setMicrophoneError(error.localizedDescription)
            AppLogger.ui().logError(event: "mic:record:error", error: error)
        }

        await speechService.cancel()
        isRecording = false
        isTranscribing = false
    }

    private func requestRecordPermissionIfNeeded() async {
#if os(iOS)
        let permission = AVAudioApplication.shared.recordPermission

        switch permission {
        case .granted:
            recordPermission = .granted
            AppLogger.ui().log(event: "mic:recordPermission", data: ["status": "granted"])
            return
        case .denied:
            recordPermission = .denied
            microphoneErrorMessage = "Enable microphone access in Settings."
            AppLogger.ui().log(event: "mic:recordPermission", data: ["status": "denied"])
            return
        case .undetermined:
            recordPermission = .undetermined
        @unknown default:
            recordPermission = .denied
            microphoneErrorMessage = "Enable microphone access in Settings."
            AppLogger.ui().log(event: "mic:recordPermission", data: ["status": "unknown"])
            return
        }

        isRequestingRecordPermission = true
        let granted: Bool = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        isRequestingRecordPermission = false
        recordPermission = granted ? .granted : .denied
        microphoneErrorMessage = granted ? nil : "Enable microphone access in Settings."
        AppLogger.ui().log(event: "mic:recordPermission", data: ["status": granted ? "granted" : "denied"])
#else
        _ = await speechService.authorizationStatus()
#endif
    }
}

@available(iOS 18.0, macOS 13.0, *)
struct VoiceInputBar: View {
    @Bindable var controller: VoiceInputController
    let isStreaming: Bool
    let modelSlug: String
    let onSendText: (String) -> Void
    let onStopStreaming: () -> Void
    let onVoiceTranscript: (String) -> Void

    @State private var isTextInputMode = false
    @State private var textInputContent = ""
    @FocusState private var isTextFieldFocused: Bool

    private var microphoneStatus: MicrophoneInputBar.Status { controller.status }

    private var microphoneIsEnabled: Bool {
        controller.isEnabled(isStreaming: isStreaming)
    }

    private var microphoneFeedback: (text: String, color: Color)? {
        controller.feedback
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if isTextInputMode {
                    textInputField
                } else {
                    inputButton
                }

                if isStreaming {
                    stopButton
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                inputBarBackground
                    .ignoresSafeArea(edges: .bottom)
            }
            .overlay(alignment: .top) {
                if let feedback = microphoneFeedback {
                    statusBanner(text: feedback.text, color: feedback.color)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private var locale: Locale { Locale.current }

    @ViewBuilder
    private var inputButton: some View {
        let longPressGesture = LongPressGesture(minimumDuration: 0.3)
            .onEnded { _ in
                guard microphoneIsEnabled, microphoneStatus.allowsInteraction, !isStreaming else { return }
#if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
#endif
                controller.clearMicrophoneError()
                Task {
                    await controller.startRecording(modelSlug: modelSlug, locale: locale, onTranscript: onVoiceTranscript)
                }
            }

        let dragGesture = DragGesture(minimumDistance: 0)
            .onEnded { _ in
                if controller.isRecording {
#if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
                    Task {
                        await controller.finishRecording(modelSlug: modelSlug)
                    }
                }
            }

        let tapGesture = TapGesture()
            .onEnded {
                guard !isStreaming, !controller.isRecording else { return }
#if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isTextInputMode = true
                    isTextFieldFocused = true
                }
            }

        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(microphoneBackgroundColor.gradient)
                    .frame(width: 40, height: 40)
                    .shadow(color: microphoneBackgroundColor.opacity(0.3), radius: 6, y: 3)

                microphoneIcon
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, options: .repeating, isActive: microphoneStatus == .recording)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(microphonePrimaryText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(microphonePrimaryColor)

                if let detail = microphoneDetailText {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if microphoneShowsProgress {
                ProgressView()
                    .controlSize(.small)
                    .tint(microphoneBackgroundColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .scaleEffect(microphoneStatus == .recording ? 1.02 : 1.0)
        .opacity(microphoneIsEnabled ? 1.0 : 0.5)
        .simultaneousGesture(tapGesture)
        .simultaneousGesture(longPressGesture.sequenced(before: dragGesture))
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: microphoneStatus)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(microphoneAccessibilityLabel)
        .accessibilityHint(microphoneAccessibilityHint)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var textInputField: some View {
        HStack(spacing: 10) {
            TextField("Type your message...", text: $textInputContent)
                .focused($isTextFieldFocused)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                }
                .onSubmit {
                    sendTextInput()
                }

            Button(action: sendTextInput) {
                ZStack {
                    Circle()
                        .fill(Color.blue.gradient)
                        .frame(width: 40, height: 40)
                        .shadow(color: .blue.opacity(0.3), radius: 6, y: 3)

                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .disabled(textInputContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(textInputContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
            .buttonStyle(.plain)

            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isTextInputMode = false
                    textInputContent = ""
                    isTextFieldFocused = false
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func sendTextInput() {
        let trimmed = textInputContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

#if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
#endif

        onSendText(trimmed)
        textInputContent = ""
    }

    private func statusBanner(text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption)
            Text(text)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background {
            Capsule()
                .fill(.thinMaterial)
                .overlay {
                    Capsule()
                        .strokeBorder(color.opacity(0.2), lineWidth: 0.5)
                }
        }
        .offset(y: -10)
        .shadow(color: color.opacity(0.15), radius: 6, y: 3)
    }

    private var stopButton: some View {
        Button(action: onStopStreaming) {
            ZStack {
                Circle()
                    .fill(.red.gradient)
                    .frame(width: 40, height: 40)
                    .shadow(color: .red.opacity(0.3), radius: 6, y: 3)

                Image(systemName: "stop.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityLabel("Stop response")
        .accessibilityIdentifier("stopButton")
        .buttonStyle(.plain)
        .scaleEffect(1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isStreaming)
    }

    @ViewBuilder
    private var inputBarBackground: some View {
        Rectangle()
            .fill(.regularMaterial)
            .background {
                LinearGradient(
                    colors: [Color.black.opacity(0.01), Color.black.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .shadow(color: .black.opacity(0.06), radius: 1, y: -1)
    }

    private var microphoneIcon: Image {
        switch microphoneStatus {
        case .idle:
            return Image(systemName: "mic.fill")
        case .requestingPermission:
            return Image(systemName: "exclamationmark.circle.fill")
        case .recording:
            return Image(systemName: "waveform")
        case .transcribing:
            return Image(systemName: "arrow.triangle.2.circlepath")
        case .disabled:
            return Image(systemName: "mic.slash.fill")
        case .error:
            return Image(systemName: "exclamationmark.triangle.fill")
        }
    }

    private var microphoneBackgroundColor: Color {
        switch microphoneStatus {
        case .idle:
            return Color.blue
        case .requestingPermission:
            return Color.indigo
        case .recording:
            return Color.red
        case .transcribing:
            return Color.purple
        case .disabled:
            return Color.gray
        case .error:
            return Color.orange
        }
    }

    private var microphonePrimaryColor: Color {
        switch microphoneStatus {
        case .idle, .requestingPermission, .transcribing:
            return .primary
        case .recording:
            return .red
        case .disabled:
            return .secondary
        case .error:
            return .orange
        }
    }

    private var microphonePrimaryText: String {
        switch microphoneStatus {
        case .idle:
            return "Hold to talk, Tap to type"
        case .requestingPermission:
            return "Requesting access…"
        case .recording:
            return "Recording…"
        case .transcribing:
            return "Processing speech…"
        case .disabled:
            return "Microphone unavailable"
        case .error:
            return "Error occurred"
        }
    }

    private var microphoneDetailText: String? {
        switch microphoneStatus {
        case .idle:
            return nil
        case .requestingPermission:
            return "Grant permissions to continue"
        case .recording:
            return "Release to send"
        case .transcribing:
            return nil
        case .disabled(let message):
            return message.isEmpty ? nil : message
        case .error(let message):
            return message.isEmpty ? nil : message
        }
    }

    private var microphoneShowsProgress: Bool {
        switch microphoneStatus {
        case .requestingPermission, .transcribing:
            return true
        default:
            return false
        }
    }

    private var microphoneAccessibilityLabel: String {
        switch microphoneStatus {
        case .idle:
            return "Microphone button. Tap and hold to record your message."
        case .requestingPermission:
            return "Requesting microphone permission."
        case .recording:
            return "Recording in progress. Release to send."
        case .transcribing:
            return "Transcribing your speech."
        case .disabled:
            return "Microphone unavailable."
        case .error:
            return "Microphone error. Tap and hold to retry."
        }
    }

    private var microphoneAccessibilityHint: String {
        switch microphoneStatus {
        case .idle:
            return "Double tap and hold to record, release to send your voice message."
        case .recording:
            return "Release to send your voice message."
        case .requestingPermission:
            return "Grant microphone permissions in Settings."
        case .transcribing:
            return "Please wait while processing completes."
        case .disabled:
            return "Enable microphone in Settings to use voice input."
        case .error:
            return "Tap and hold again to retry."
        }
    }
}
