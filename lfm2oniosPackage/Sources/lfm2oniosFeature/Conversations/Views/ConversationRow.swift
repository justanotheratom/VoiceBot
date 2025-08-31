import SwiftUI

struct ConversationRow: View {
    let conversation: ChatConversation
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityLabel("Conversation title: \(conversation.title)")
                
                if let lastMessage = conversation.messages.last {
                    Text(lastMessage.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .accessibilityLabel("Last message: \(lastMessage.content)")
                }
                
                HStack {
                    Text(conversation.updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Updated \(conversation.updatedAt, style: .relative)")
                    
                    Spacer()
                    
                    Text(conversation.modelSlug)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                        .accessibilityLabel("Model: \(conversation.modelSlug)")
                }
            }
            
            Spacer()
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete conversation")
            .accessibilityHint("Deletes this conversation permanently")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conversation-row-\(conversation.id)")
    }
}

#if DEBUG
#Preview {
    let sampleMessage = ChatMessageModel(role: .user, content: "What is SwiftUI and how does it work?")
    var sampleConversation = ChatConversation(modelSlug: "lfm2-350m", initialMessage: sampleMessage)
    sampleConversation.setTitle("SwiftUI Discussion")
    
    return List {
        ConversationRow(conversation: sampleConversation) {
            print("Delete tapped")
        }
    }
    .listStyle(.plain)
}
#endif