import AVFoundation
import Speech

@available(iOS 17.0, macOS 13.0, *)
actor SpeechRecognitionService {
    enum AuthorizationStatus: Equatable {
        case notDetermined
        case authorized
        case denied
        case restricted

        init(_ status: SFSpeechRecognizerAuthorizationStatus) {
            switch status {
            case .authorized:
                self = .authorized
            case .denied:
                self = .denied
            case .restricted:
                self = .restricted
            case .notDetermined:
                fallthrough
            @unknown default:
                self = .notDetermined
            }
        }
    }

    enum ServiceError: Error, LocalizedError, Equatable {
        case recognizerUnavailable
        case onDeviceRecognitionUnsupported
        case authorizationDenied
        case audioEngineUnavailable
        case recognitionAlreadyRunning
        case noActiveRecognition
        case recognitionFailed(String)

        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable:
                return "Speech recognition is not available for the selected locale."
            case .onDeviceRecognitionUnsupported:
                return "On-device speech recognition is unavailable on this device."
            case .authorizationDenied:
                return "Speech recognition permission was denied."
            case .audioEngineUnavailable:
                return "Could not start audio capture."
            case .recognitionAlreadyRunning:
                return "Speech recognition session is already active."
            case .noActiveRecognition:
                return "There is no active speech session to stop."
            case .recognitionFailed(let message):
                return message
            }
        }
    }

    private enum State: Equatable { case idle, recording }

    private var state: State = .idle
    private var speechRecognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var finishContinuation: CheckedContinuation<String?, Error>?
    private var latestTranscription: String?
    private var localeProvider: () -> Locale

    init(localeProvider: @escaping () -> Locale = { Locale.current }) {
        self.localeProvider = localeProvider
    }

    func authorizationStatus() -> AuthorizationStatus {
        AuthorizationStatus(SFSpeechRecognizer.authorizationStatus())
    }

    func requestAuthorization() async -> AuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: AuthorizationStatus(status))
            }
        }
    }

    func start(locale overrideLocale: Locale? = nil) async throws {
        guard state == .idle else { throw ServiceError.recognitionAlreadyRunning }

        let locale = overrideLocale ?? localeProvider()
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw ServiceError.recognizerUnavailable
        }

        guard recognizer.supportsOnDeviceRecognition else {
            throw ServiceError.onDeviceRecognitionUnsupported
        }

        guard recognizer.isAvailable else {
            throw ServiceError.recognizerUnavailable
        }

        let audioEngine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true

        #if os(iOS)
        try await MainActor.run {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.duckOthers, .defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        }
        #endif

        let inputNode = audioEngine.inputNode

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw ServiceError.audioEngineUnavailable
        }

        recognitionRequest = request
        self.audioEngine = audioEngine
        speechRecognizer = recognizer
        latestTranscription = nil
        state = .recording

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errorInfo = (error as NSError?)
            Task { await self.processRecognitionUpdate(transcript: transcript, isFinal: isFinal, error: errorInfo) }
        }
    }

    func stop() async throws -> String? {
        guard state == .recording else { throw ServiceError.noActiveRecognition }

        return try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
            recognitionRequest?.endAudio()
            audioEngine?.stop()
        }
    }

    func cancel() async {
        if let continuation = finishContinuation {
            continuation.resume(throwing: ServiceError.recognitionFailed("Cancelled"))
            finishContinuation = nil
        }
        await cleanup()
    }

    private func processRecognitionUpdate(transcript: String?, isFinal: Bool, error: NSError?) async {
        if let error {
            if let continuation = finishContinuation {
                continuation.resume(throwing: ServiceError.recognitionFailed(error.localizedDescription))
                finishContinuation = nil
            }
            await cleanup()
            return
        }

        if let transcript {
            latestTranscription = transcript
        }

        if isFinal {
            if let continuation = finishContinuation {
                continuation.resume(returning: latestTranscription)
                finishContinuation = nil
            }
            await cleanup()
        }
    }

    private func cleanup() async {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        latestTranscription = nil
        state = .idle

        #if os(iOS)
        await MainActor.run {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        #endif
    }
}
