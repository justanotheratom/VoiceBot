import SwiftUI

/// Reusable chat message view component that displays a message with role-based styling,
/// streaming indicator, and optional performance statistics.
@available(iOS 17.0, macOS 13.0, *)
public struct ChatMessageView: View {
    let message: Message
    let isStreaming: Bool

    public init(message: Message, isStreaming: Bool = false) {
        self.message = message
        self.isStreaming = isStreaming
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // Avatar
                avatarIcon
                    .font(.title3)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 6) {
                    // Role label
                    Text(message.role == .user ? "You" : "Assistant")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)

                    // Message content
                    Text(message.text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Streaming indicator for assistant messages
                    if message.role == .assistant && isStreaming {
                        streamingIndicator
                    }
                }
            }

            // Performance stats for assistant messages
            if message.role == .assistant, let stats = message.stats {
                performanceStats(stats)
            }
        }
    }

    @ViewBuilder
    private var avatarIcon: some View {
        if message.role == .user {
            Image(systemName: "person.circle.fill")
                .foregroundStyle(.blue)
        } else {
            Image(systemName: "brain.head.profile")
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private var streamingIndicator: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(.secondary)
                        .frame(width: 5, height: 5)
                        .opacity(0.4)
                        .animation(
                            .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                            value: isStreaming
                        )
                        .scaleEffect(isStreaming ? 1.3 : 1.0)
                }
            }

            Text("Assistant is typing...")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func performanceStats(_ stats: TokenStats) -> some View {
        HStack {
            Spacer()
                .frame(width: 40)
            HStack(spacing: 12) {
                Label("\(stats.tokens) tokens", systemImage: "number.circle")
                if let ttft = stats.timeToFirstToken {
                    Label("\(String(format: "%.2f", ttft))s", systemImage: "clock")
                }
                if let tps = stats.tokensPerSecond {
                    Label("\(String(format: "%.1f", tps))/s", systemImage: "speedometer")
                }
            }
            .labelStyle(.titleAndIcon)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            Spacer()
        }
    }
}

// MARK: - Preview

@available(iOS 17.0, macOS 13.0, *)
#Preview("User Message") {
    ChatMessageView(
        message: Message(
            role: .user,
            text: "What is SwiftUI?"
        ),
        isStreaming: false
    )
    .padding()
}

@available(iOS 17.0, macOS 13.0, *)
#Preview("Assistant Streaming") {
    ChatMessageView(
        message: Message(
            role: .assistant,
            text: "SwiftUI is a modern declarative framework for building user interfaces..."
        ),
        isStreaming: true
    )
    .padding()
}

@available(iOS 17.0, macOS 13.0, *)
#Preview("Assistant with Stats") {
    ChatMessageView(
        message: Message(
            role: .assistant,
            text: "SwiftUI is a modern declarative framework for building user interfaces across all Apple platforms.",
            stats: TokenStats(tokens: 156, timeToFirstToken: 0.42, tokensPerSecond: 127.3)
        ),
        isStreaming: false
    )
    .padding()
}
