import SwiftUI

/// Reusable pill-shaped button for displaying conversation starter suggestions.
@available(iOS 17.0, macOS 13.0, *)
public struct SuggestionPill: View {
    let text: String
    let action: () -> Void

    public init(text: String, action: @escaping () -> Void) {
        self.text = text
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(text)
                .font(.caption)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

@available(iOS 17.0, macOS 13.0, *)
#Preview {
    VStack(spacing: 12) {
        SuggestionPill(text: "Explain a concept") {}
        SuggestionPill(text: "Write code") {}
        SuggestionPill(text: "Creative writing") {}
    }
    .padding()
}
