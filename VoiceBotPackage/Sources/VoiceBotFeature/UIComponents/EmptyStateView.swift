import SwiftUI

/// Reusable empty state view component for displaying a welcoming message
/// with suggestion pills when the chat is empty.
@available(iOS 17.0, macOS 13.0, *)
public struct EmptyStateView: View {
    let onSuggestionTap: (String) -> Void

    public init(onSuggestionTap: @escaping (String) -> Void) {
        self.onSuggestionTap = onSuggestionTap
    }

    public var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // AI Assistant Icon with animation
            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundStyle(.blue.gradient)
                .symbolEffect(.pulse.wholeSymbol, options: .repeating.speed(0.5))

            VStack(spacing: 8) {
                Text("Ready to Chat")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text("Ask me anything or start a conversation")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            suggestionPillsView

            Spacer()
        }
        .padding()
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var suggestionPillsView: some View {
        VStack(spacing: 12) {
            Text("Try asking:")
                .font(.caption)
                .foregroundStyle(.tertiary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                SuggestionPill(text: "Explain a concept") {
                    onSuggestionTap("Can you explain quantum computing in simple terms?")
                }
                SuggestionPill(text: "Write code") {
                    onSuggestionTap("Write a SwiftUI view that displays a list")
                }
                SuggestionPill(text: "Creative writing") {
                    onSuggestionTap("Write a short story about space exploration")
                }
                SuggestionPill(text: "Problem solving") {
                    onSuggestionTap("Help me debug this Swift code")
                }
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Preview

@available(iOS 17.0, macOS 13.0, *)
#Preview {
    EmptyStateView { suggestion in
        print("Tapped: \(suggestion)")
    }
}
