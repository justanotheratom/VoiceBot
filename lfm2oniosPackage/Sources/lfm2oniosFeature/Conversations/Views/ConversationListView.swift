import SwiftUI
import os.log

struct ConversationListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var conversationService = ConversationService()
    @State private var conversations: [ChatConversation] = []
    @State private var searchText = ""
    
    private let logger = Logger(subsystem: "com.oneoffrepo.lfm2onios", category: "ui")
    
    let onConversationSelected: (ChatConversation) -> Void
    
    var filteredConversations: [ChatConversation] {
        if searchText.isEmpty {
            return conversations
        } else {
            return conversations.filter { conversation in
                conversation.title.localizedCaseInsensitiveContains(searchText) ||
                conversation.messages.contains { message in
                    message.content.localizedCaseInsensitiveContains(searchText)
                }
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                if conversations.isEmpty {
                    ContentUnavailableView(
                        "No Conversations",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Start a new conversation to see it here")
                    )
                    .accessibilityIdentifier("empty-conversations-view")
                } else {
                    List {
                        ForEach(filteredConversations) { conversation in
                            ConversationRow(
                                conversation: conversation,
                                onDelete: {
                                    deleteConversation(conversation)
                                }
                            )
                            .onTapGesture {
                                logger.info("ui: { event: \"conversationSelected\", id: \"\(conversation.id)\" }")
                                onConversationSelected(conversation)
                                dismiss()
                            }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint("Tap to open this conversation")
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search conversations...")
                    .accessibilityIdentifier("conversations-list")
                }
            }
            .navigationTitle("Conversations")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("done-button")
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("done-button")
                }
                #endif
            }
            .refreshable {
                await refreshConversations()
            }
        }
        .task {
            await loadConversations()
        }
    }
    
    @MainActor
    private func loadConversations() async {
        conversations = conversationService.loadAllConversations()
        logger.info("ui: { event: \"conversationsLoaded\", count: \(conversations.count) }")
    }
    
    @MainActor
    private func refreshConversations() async {
        await loadConversations()
    }
    
    private func deleteConversation(_ conversation: ChatConversation) {
        do {
            try conversationService.deleteConversation(id: conversation.id)
            conversations.removeAll { $0.id == conversation.id }
            logger.info("ui: { event: \"conversationDeleted\", id: \"\(conversation.id)\" }")
        } catch {
            logger.error("ui: { event: \"conversationDeleteFailed\", error: \"\(error.localizedDescription)\" }")
        }
    }
}

#if DEBUG
#Preview {
    ConversationListView { conversation in
    }
}
#endif
