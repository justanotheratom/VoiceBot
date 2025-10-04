import SwiftUI

@available(iOS 17.0, macOS 13.0, *)
struct MicrophoneInputBar: View {
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

    let status: Status
    let isEnabled: Bool
    let onPressBegan: () -> Void
    let onPressEnded: () -> Void

    @State private var hasActivePress = false

    var body: some View {
        let gesture = DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard isEnabled, !hasActivePress, status.allowsInteraction else { return }
                hasActivePress = true
                onPressBegan()
            }
            .onEnded { _ in
                guard hasActivePress else { return }
                hasActivePress = false
                onPressEnded()
            }

        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
            .accessibilityAddTraits(.isButton)
            .gesture(gesture)
            .animation(.easeInOut(duration: 0.2), value: status)
            .animation(.easeInOut(duration: 0.1), value: hasActivePress)
    }

    @ViewBuilder
    private var content: some View {
        HStack(alignment: .center, spacing: 12) {
            image
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(primaryText)
                    .font(.headline)
                    .foregroundStyle(primaryColor)
                if let detail = detailText {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            if showsProgressIndicator {
                ProgressView()
                    .tint(primaryColor)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 28)
                .fill(backgroundFill)
                .shadow(color: shadowColor, radius: hasActivePress ? 6 : 3, x: 0, y: hasActivePress ? 6 : 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(borderColor, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .opacity(viewOpacity)
    }

    private var backgroundFill: AnyShapeStyle {
        switch status {
        case .idle:
            return AnyShapeStyle(.ultraThinMaterial)
        case .requestingPermission, .transcribing:
            return AnyShapeStyle(.thinMaterial)
        case .recording:
            return AnyShapeStyle(Color.red.opacity(hasActivePress ? 0.25 : 0.18))
        case .error:
            return AnyShapeStyle(Color.orange.opacity(0.18))
        case .disabled:
            return AnyShapeStyle(Color.secondary.opacity(0.1))
        }
    }

    private var shadowColor: Color {
        switch status {
        case .recording:
            return Color.red.opacity(hasActivePress ? 0.3 : 0.18)
        case .error:
            return Color.orange.opacity(0.18)
        default:
            return Color.black.opacity(hasActivePress ? 0.15 : 0.08)
        }
    }

    private var borderColor: Color {
        switch status {
        case .idle:
            return Color.primary.opacity(0.08)
        case .requestingPermission, .transcribing:
            return Color.primary.opacity(0.06)
        case .recording:
            return .red.opacity(0.4)
        case .error:
            return .orange.opacity(0.6)
        case .disabled:
            return Color.primary.opacity(0.04)
        }
    }

    private var viewOpacity: Double {
        if case .disabled = status {
            return 1.0
        }
        return isEnabled ? 1.0 : 0.6
    }

    private var iconColor: Color {
        switch status {
        case .idle:
            return .blue
        case .requestingPermission:
            return .blue
        case .recording:
            return .red
        case .transcribing:
            return .blue
        case .disabled:
            return .gray
        case .error:
            return .orange
        }
    }

    private var primaryColor: Color {
        switch status {
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

    private var image: Image {
        switch status {
        case .idle:
            return Image(systemName: "mic.circle.fill")
        case .requestingPermission:
            return Image(systemName: "exclamationmark.circle")
        case .recording:
            return Image(systemName: "waveform.circle.fill")
        case .transcribing:
            return Image(systemName: "arrow.triangle.2.circlepath.circle")
        case .disabled:
            return Image(systemName: "mic.slash.circle")
        case .error:
            return Image(systemName: "exclamationmark.triangle.fill")
        }
    }

    private var primaryText: String {
        switch status {
        case .idle:
            return "Hold to speak"
        case .requestingPermission:
            return "Requesting permission…"
        case .recording:
            return "Listening"
        case .transcribing:
            return "Transcribing…"
        case .disabled:
            return "Microphone unavailable"
        case .error:
            return "Something went wrong"
        }
    }

    private var detailText: String? {
        switch status {
        case .idle:
            return "Long press and release to send your prompt"
        case .requestingPermission:
            return "Grant microphone and speech access to continue"
        case .recording:
            return "Release to send"
        case .transcribing:
            return "Finishing up your transcript"
        case .disabled(let message):
            return message
        case .error(let message):
            return message
        }
    }

    private var showsProgressIndicator: Bool {
        switch status {
        case .requestingPermission, .transcribing:
            return true
        default:
            return false
        }
    }

    private var accessibilityLabel: String {
        switch status {
        case .idle:
            return "Microphone input. Hold to speak."
        case .requestingPermission:
            return "Microphone input disabled while requesting permission."
        case .recording:
            return "Recording in progress. Release to finish."
        case .transcribing:
            return "Transcribing your speech."
        case .disabled:
            return "Microphone unavailable."
        case .error:
            return "Microphone error. Double tap and hold to retry."
        }
    }

    private var accessibilityHint: String {
        switch status {
        case .idle:
            return "Double tap and hold, then release to send your message."
        case .recording:
            return "Release to send your voice message."
        case .requestingPermission:
            return "Grant microphone and speech permissions in Settings."
        case .transcribing:
            return "Please wait while we finish processing."
        case .disabled:
            return "Enable microphone and speech recognition in Settings to use voice input."
        case .error:
            return "Double tap and hold again to retry voice capture."
        }
    }
}

#Preview {
    if #available(iOS 17.0, *) {
        VStack(spacing: 20) {
            MicrophoneInputBar(status: .idle, isEnabled: true, onPressBegan: {}, onPressEnded: {})
            MicrophoneInputBar(status: .recording, isEnabled: true, onPressBegan: {}, onPressEnded: {})
            MicrophoneInputBar(status: .transcribing, isEnabled: false, onPressBegan: {}, onPressEnded: {})
            MicrophoneInputBar(status: .disabled(message: "Enable access in Settings"), isEnabled: false, onPressBegan: {}, onPressEnded: {})
        }
        .padding()
    }
}
