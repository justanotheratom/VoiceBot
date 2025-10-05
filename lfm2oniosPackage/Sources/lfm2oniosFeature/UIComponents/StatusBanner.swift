import SwiftUI

/// Reusable status banner component for displaying informational or warning messages.
/// Used for microphone errors, permission states, and other temporary notifications.
@available(iOS 17.0, macOS 13.0, *)
public struct StatusBanner: View {
    let text: String
    let color: Color
    let icon: String

    public init(text: String, color: Color = .secondary, icon: String = "exclamationmark.circle.fill") {
        self.text = text
        self.color = color
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
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
        .shadow(color: color.opacity(0.15), radius: 6, y: 3)
    }
}

// MARK: - Preview

@available(iOS 17.0, macOS 13.0, *)
#Preview {
    VStack(spacing: 16) {
        StatusBanner(
            text: "Enable microphone access in Settings",
            color: .secondary
        )

        StatusBanner(
            text: "Recording failed. Try again.",
            color: .orange
        )

        StatusBanner(
            text: "Processing your speech...",
            color: .blue,
            icon: "waveform"
        )
    }
    .padding()
}
