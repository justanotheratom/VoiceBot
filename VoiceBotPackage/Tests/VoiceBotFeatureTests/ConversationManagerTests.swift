import Testing
import Foundation
@testable import VoiceBotFeature

@Test("ConversationManager creates new conversation correctly")
@MainActor
func conversationManagerNewConversation() {
    let mockRuntimeService = ModelRuntimeService()
    let manager = ConversationManager(modelRuntimeService: mockRuntimeService)
    
    #expect(manager.currentConversation == nil)
    #expect(manager.needsTitleGeneration == false)
    
    manager.startNewConversation(modelSlug: "lfm2-350m")
    
    #expect(manager.currentConversation != nil)
    #expect(manager.currentConversation?.modelSlug == "lfm2-350m")
    #expect(manager.needsTitleGeneration == false)
}

@Test("ConversationManager adds user messages correctly")
@MainActor
func conversationManagerAddUserMessage() {
    let mockRuntimeService = ModelRuntimeService()
    let manager = ConversationManager(modelRuntimeService: mockRuntimeService)
    
    manager.startNewConversation(modelSlug: "lfm2-350m")
    manager.addUserMessage("Hello, how are you?")
    
    let messages = manager.getMessagesForLLM()
    let systemPrompt = ModelCatalog.entry(forSlug: "lfm2-350m")?.systemPrompt
    if let systemPrompt {
        #expect(messages.count == 2)
        #expect(messages.first?.role == .system)
        #expect(messages.first?.content == systemPrompt)
        #expect(messages.last?.role == .user)
        #expect(messages.last?.content == "Hello, how are you?")
    } else {
        #expect(messages.count == 1)
        #expect(messages.first?.role == .user)
        #expect(messages.first?.content == "Hello, how are you?")
    }
}

@Test("ConversationManager adds assistant messages and triggers title generation")
@MainActor
func conversationManagerAddAssistantMessage() async {
    let mockRuntimeService = ModelRuntimeService()
    let manager = ConversationManager(modelRuntimeService: mockRuntimeService)
    
    manager.startNewConversation(modelSlug: "lfm2-350m")
    manager.addUserMessage("Hello, how are you?")
    
    #expect(manager.needsTitleGeneration == false)
    
    await manager.addAssistantMessage("I'm doing well, thank you!")
    
    let messages = manager.getMessagesForLLM()
    let systemPrompt = ModelCatalog.entry(forSlug: "lfm2-350m")?.systemPrompt
    let expectedCount = (systemPrompt == nil ? 0 : 1) + 2 // system? + user + assistant
    #expect(messages.count == expectedCount)
    #expect(messages.last?.role == .assistant)
    #expect(messages.last?.content == "I'm doing well, thank you!")
    
    // Should trigger title generation after first exchange
    #expect(manager.needsTitleGeneration == true)
}

@Test("ConversationManager loads existing conversation")
@MainActor
func conversationManagerLoadConversation() {
    let mockRuntimeService = ModelRuntimeService()
    let manager = ConversationManager(modelRuntimeService: mockRuntimeService)
    
    // Create test conversation
    let userMessage = ChatMessageModel(role: .user, content: "Test message")
    let assistantMessage = ChatMessageModel(role: .assistant, content: "Test response")
    var testConversation = ChatConversation(modelSlug: "lfm2-700m", initialMessage: userMessage)
    testConversation.addMessage(assistantMessage)
    testConversation.setTitle("Test Conversation")
    
    manager.loadConversation(testConversation)
    
    #expect(manager.currentConversation?.id == testConversation.id)
    #expect(manager.currentConversation?.title == "Test Conversation")
    #expect(manager.currentConversation?.modelSlug == "lfm2-700m")
    
    let messages = manager.getAllMessagesForDisplay()
    #expect(messages.count == 2)
    #expect(messages.first?.content == "Test message")
    #expect(messages.last?.content == "Test response")
}

@Test("ConversationManager handles empty state correctly")
@MainActor
func conversationManagerEmptyState() {
    let mockRuntimeService = ModelRuntimeService()
    let manager = ConversationManager(modelRuntimeService: mockRuntimeService)
    
    #expect(manager.getMessagesForLLM().isEmpty)
    #expect(manager.getAllMessagesForDisplay().isEmpty)
    #expect(manager.currentConversation == nil)
}

@Test("ConversationManager creates conversation for orphan user message")
@MainActor
func conversationManagerOrphanUserMessage() {
    let mockRuntimeService = ModelRuntimeService()
    let manager = ConversationManager(modelRuntimeService: mockRuntimeService)
    
    #expect(manager.currentConversation == nil)
    
    manager.addUserMessage("Hello without conversation")
    
    #expect(manager.currentConversation != nil)
    #expect(manager.currentConversation?.modelSlug == "unknown")
    
    let messages = manager.getMessagesForLLM()
    #expect(messages.count >= 1)
    #expect(messages.contains { $0.content == "Hello without conversation" && $0.role == .user })
}
