import SwiftUI

#if os(iOS)
import AVFoundation
import AVFAudio
#endif

@available(iOS 18.0, macOS 13.0, *)
struct VoiceInputBar: View {
    @Bindable var controller: VoiceInputStore
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

            CircularActionButton(
                icon: "arrow.up",
                style: .primary,
                size: 40,
                action: sendTextInput
            )
            .disabled(textInputContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(textInputContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)

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
        StatusBanner(text: text, color: color)
            .offset(y: -10)
    }

    private var stopButton: some View {
        CircularActionButton(
            icon: "stop.fill",
            style: .destructive,
            size: 40,
            accessibilityLabel: "Stop response",
            accessibilityIdentifier: "stopButton",
            action: onStopStreaming
        )
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

// MARK: - Status enum used by VoiceInputStore
enum MicrophoneInputBar {
    enum Status: Equatable {
        case idle
        case requestingPermission
        case recording
        case transcribing
        case disabled(message: String)
        case error(message: String)

        var allowsInteraction: Bool {
            switch self {
            case .idle, .error:
                return true
            case .requestingPermission, .recording, .transcribing, .disabled:
                return false
            }
        }
    }
}
