import Foundation
import os.log

@Observable
@MainActor
class ConversationManager {
    private let conversationService = ConversationService()
    private let contextManager = ContextWindowManager()
    private let titleService: TitleGenerationService
    private let logger = Logger(subsystem: "com.oneoffrepo.lfm2onios", category: "conversation")
    private var activeModelSlug: String?
    
    var currentConversation: ChatConversation?
    var needsTitleGeneration = false
    
    init(modelRuntimeService: ModelRuntimeService) {
        self.titleService = TitleGenerationService(modelRuntimeService: modelRuntimeService)
    }
    
    func startNewConversation(modelSlug: String) {
        activeModelSlug = modelSlug
        var conversation = ChatConversation(modelSlug: modelSlug, initialMessages: [])
        ensureSystemMessage(in: &conversation, persist: false)
        currentConversation = conversation
        needsTitleGeneration = false
        logger.info("conversation: { event: \"new\", modelSlug: \"\(modelSlug)\" }")
        saveCurrentConversation()
    }
    
    func loadConversation(_ conversation: ChatConversation) {
        var mutableConversation = conversation
        activeModelSlug = conversation.modelSlug
        ensureSystemMessage(in: &mutableConversation, persist: true)
        currentConversation = mutableConversation
        needsTitleGeneration = false
        logger.info("conversation: { event: \"loaded\", id: \"\(mutableConversation.id)\", messageCount: \(mutableConversation.messages.count) }")
    }
    
    func addUserMessage(_ content: String) {
        var conversation: ChatConversation
        if var existing = currentConversation {
            ensureSystemMessage(in: &existing, persist: true)
            conversation = existing
        } else {
            let slug = activeModelSlug ?? "unknown"
            conversation = ChatConversation(modelSlug: slug, initialMessages: [])
            ensureSystemMessage(in: &conversation, persist: false)
            activeModelSlug = slug
        }
        
        let message = ChatMessageModel(role: .user, content: content)
        if let last = conversation.messages.last, last.role == .user {
            conversation.replaceLastMessage(with: message)
        } else {
            conversation.addMessage(message)
        }
        
        // Check if we need to archive messages using context manager
        if contextManager.shouldArchiveMessages(in: conversation) {
            let messagesToArchive = contextManager.getMessagesToArchive(from: conversation)
            conversation.archiveOldMessages(messagesToArchive)
        }

        currentConversation = conversation
        saveCurrentConversation()
    }
    
    func addAssistantMessage(_ content: String) async {
        guard var conversation = currentConversation else { return }
        ensureSystemMessage(in: &conversation, persist: true)

        let shouldTriggerTitle = !needsTitleGeneration && !conversation.messages.contains { $0.role == .assistant }

        let message = ChatMessageModel(role: .assistant, content: content)
        conversation.addMessage(message)
        currentConversation = conversation
        activeModelSlug = conversation.modelSlug

        if shouldTriggerTitle {
            needsTitleGeneration = true
            // DISABLED: Title generation interferes with streaming when user stops mid-response
            // TODO: Re-enable after fixing concurrent streaming issue
            // Task.detached { @MainActor in
            //     try? await Task.sleep(for: .seconds(0.5))
            //     await self.generateTitleIfNeeded()
            // }
        }

        saveCurrentConversation()
    }
    
    func getMessagesForLLM() -> [ChatMessageModel] {
        guard var conversation = currentConversation else { return [] }
        ensureSystemMessage(in: &conversation, persist: true)
        return conversation.messages
    }
    
    func getAllMessagesForDisplay() -> [ChatMessageModel] {
        // Return all messages (archived + active) for UI display
        return currentConversation?.allMessages ?? []
    }
    
    private func saveCurrentConversation() {
        guard let conversation = currentConversation else { return }
        
        do {
            try conversationService.saveConversation(conversation)
        } catch {
            logger.error("conversation: { event: \"saveFailed\", error: \"\(error.localizedDescription)\" }")
        }
    }

    private func ensureSystemMessage(in conversation: inout ChatConversation, persist: Bool) {
        let slug = conversation.modelSlug
        guard let prompt = ModelCatalog.entry(forSlug: slug)?.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
              !prompt.isEmpty else {
            return
        }

        if conversation.messages.first(where: { $0.role == .system }) == nil {
            let systemMessage = ChatMessageModel(role: .system, content: prompt)
            conversation.messages.insert(systemMessage, at: 0)
            if persist {
                currentConversation = conversation
                saveCurrentConversation()
            }
        }
    }

    private func generateTitleIfNeeded() async {
        guard var conversation = currentConversation,
              conversation.title == "New Conversation" else { return }
        
        let generatedTitle = await titleService.generateTitle(for: conversation)
        conversation.setTitle(generatedTitle)
        currentConversation = conversation
        saveCurrentConversation()
    }
}
