import Foundation
import os.log

@Observable
@MainActor
class ConversationManager {
    private let conversationService = ConversationService()
    private let contextManager = ContextWindowManager()
    private let titleService: TitleGenerationService
    private let logger = Logger(subsystem: "com.oneoffrepo.lfm2onios", category: "conversation")
    
    var currentConversation: ChatConversation?
    var needsTitleGeneration = false
    
    init(modelRuntimeService: ModelRuntimeService) {
        self.titleService = TitleGenerationService(modelRuntimeService: modelRuntimeService)
    }
    
    func startNewConversation(modelSlug: String) {
        let userMessage = ChatMessageModel(role: .user, content: "")
        currentConversation = ChatConversation(modelSlug: modelSlug, initialMessage: userMessage)
        needsTitleGeneration = false
        logger.info("conversation: { event: \"new\", modelSlug: \"\(modelSlug)\" }")
    }
    
    func loadConversation(_ conversation: ChatConversation) {
        currentConversation = conversation
        needsTitleGeneration = false
        logger.info("conversation: { event: \"loaded\", id: \"\(conversation.id)\", messageCount: \(conversation.messages.count) }")
    }
    
    func addUserMessage(_ content: String) {
        guard var conversation = currentConversation else { 
            // If no current conversation, create a new one with this message
            let userMessage = ChatMessageModel(role: .user, content: content)
            currentConversation = ChatConversation(modelSlug: "unknown", initialMessage: userMessage)
            saveCurrentConversation()
            return
        }
        
        let message = ChatMessageModel(role: .user, content: content)
        conversation.addMessage(message)
        
        // Check if we need to archive messages using context manager
        if contextManager.shouldArchiveMessages(in: conversation) {
            let messagesToArchive = contextManager.getMessagesToArchive(from: conversation)
            conversation.archiveOldMessages(messagesToArchive.map { ChatMessageModel(role: $0.role, content: $0.content) })
        }
        
        currentConversation = conversation
        saveCurrentConversation()
    }
    
    func addAssistantMessage(_ content: String) async {
        guard var conversation = currentConversation else { return }
        
        let message = ChatMessageModel(role: .assistant, content: content)
        conversation.addMessage(message)
        currentConversation = conversation
        
        // Generate title after first assistant response
        if conversation.messages.count == 2 && !needsTitleGeneration {
            needsTitleGeneration = true
            await generateTitleIfNeeded()
        }
        
        saveCurrentConversation()
    }
    
    func getMessagesForLLM() -> [ChatMessageModel] {
        // Return only active messages (not archived) for LLM context
        return currentConversation?.messages ?? []
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
    
    private func generateTitleIfNeeded() async {
        guard var conversation = currentConversation,
              conversation.title == "New Conversation" else { return }
        
        let generatedTitle = await titleService.generateTitle(for: conversation)
        conversation.setTitle(generatedTitle)
        currentConversation = conversation
        saveCurrentConversation()
    }
}