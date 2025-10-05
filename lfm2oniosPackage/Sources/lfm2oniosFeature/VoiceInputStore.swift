import Foundation
import Observation
import SwiftUI

#if os(iOS)
import AVFoundation
import AVFAudio
#endif

enum MicrophonePermissionState: Equatable {
    case granted
    case denied
    case undetermined
}

/// Store managing voice input UI state and coordinating with SpeechRecognitionService
@available(iOS 18.0, macOS 13.0, *)
@MainActor
@Observable
final class VoiceInputStore {
    enum SpeechPermissionState: Equatable {
        case unknown
        case granted
        case denied
    }

    // MARK: - Published State (UI-observable)

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

    // MARK: - Dependencies (not published)

    @ObservationIgnored private let speechService: SpeechRecognitionService
    @ObservationIgnored private var errorDismissTask: Task<Void, Never>?
    @ObservationIgnored private var transcriptHandler: ((String) -> Void)?

    // MARK: - Initialization

    init(speechService: SpeechRecognitionService = SpeechRecognitionService()) {
        self.speechService = speechService
    }

    deinit {
        errorDismissTask?.cancel()
    }

    // MARK: - Computed UI Properties

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

    // MARK: - Actions

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

    // MARK: - Error Handling

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

    // MARK: - Private Helpers

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
