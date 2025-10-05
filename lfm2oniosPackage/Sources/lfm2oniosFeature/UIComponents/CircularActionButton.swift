import SwiftUI

/// Reusable circular action button with gradient background and shadow.
/// Used for microphone, send, and stop buttons throughout the app.
@available(iOS 17.0, macOS 13.0, *)
public struct CircularActionButton: View {
    public enum ButtonStyle {
        case primary
        case destructive
        case secondary

        var color: Color {
            switch self {
            case .primary: return .blue
            case .destructive: return .red
            case .secondary: return .gray
            }
        }
    }

    let icon: String
    let style: ButtonStyle
    let size: CGFloat
    let action: () -> Void
    let accessibilityLabel: String?
    let accessibilityIdentifier: String?

    public init(
        icon: String,
        style: ButtonStyle = .primary,
        size: CGFloat = 40,
        accessibilityLabel: String? = nil,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.style = style
        self.size = size
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(style.color.gradient)
                    .frame(width: size, height: size)
                    .shadow(color: style.color.opacity(0.3), radius: 6, y: 3)

                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? "")
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }

    private var iconSize: CGFloat {
        size * 0.45
    }
}

// MARK: - Preview

@available(iOS 17.0, macOS 13.0, *)
#Preview {
    VStack(spacing: 20) {
        CircularActionButton(
            icon: "mic.fill",
            style: .primary,
            accessibilityLabel: "Microphone"
        ) {}

        CircularActionButton(
            icon: "stop.fill",
            style: .destructive,
            accessibilityLabel: "Stop"
        ) {}

        CircularActionButton(
            icon: "arrow.up",
            style: .primary,
            size: 36,
            accessibilityLabel: "Send"
        ) {}
    }
    .padding()
}
