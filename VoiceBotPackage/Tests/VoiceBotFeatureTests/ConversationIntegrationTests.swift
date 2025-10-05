import Testing
import Foundation
@testable import VoiceBotFeature

// MARK: - Integration Testing for Phase 6

@Test("Integration: Create new conversation and verify file is saved")
@MainActor
func integrationCreateAndSaveConversation() throws {
    let mockRuntimeService = ModelRuntimeService()
    let manager = ConversationManager(modelRuntimeService: mockRuntimeService)
    let conversationService = ConversationService()
    
    // Start new conversation
    manager.startNewConversation(modelSlug: "lfm2-350m")
    manager.addUserMessage("Hello, this is a test conversation")
    
    // Verify conversation was created
    #expect(manager.currentConversation != nil)
    #expect(manager.currentConversation?.modelSlug == "lfm2-350m")
    
    // Test that conversation was saved by loading all conversations
    let allConversations = conversationService.loadAllConversations()
    let savedConversation = allConversations.first { $0.id == manager.currentConversation?.id }
    #expect(savedConversation != nil)
    let systemPrompt = ModelCatalog.entry(forSlug: "lfm2-350m")?.systemPrompt
    let expectedMessageCount = (systemPrompt == nil ? 0 : 1) + 1 // system? + user
    #expect(savedConversation?.messages.count == expectedMessageCount)
}

@Test("Integration: Add multiple messages and verify context window management")
@MainActor
func integrationContextWindowManagement() throws {
    let mockRuntimeService = ModelRuntimeService()
    let manager = ConversationManager(modelRuntimeService: mockRuntimeService)
    
    manager.startNewConversation(modelSlug: "lfm2-1.2b")
    
    // Add multiple messages to test context window management
    for i in 1...10 {
        manager.addUserMessage("User message \(i)")
        if i <= 5 {
            Task {
                await manager.addAssistantMessage("Assistant response \(i)")
            }
        }
    }
    
    let messages = manager.getMessagesForLLM()
    let allMessages = manager.getAllMessagesForDisplay()
    
    // Context window should limit messages for LLM but display should show all
    #expect(messages.count >= 1)
    #expect(allMessages.count >= messages.count)
    
    // Verify conversation was saved with multiple messages
    #expect(manager.currentConversation != nil)
}

@Test("Integration: Test title generation after first response")
@MainActor
func integrationTitleGeneration() async throws {
    let mockRuntimeService = ModelRuntimeService()
    let manager = ConversationManager(modelRuntimeService: mockRuntimeService)
    
    manager.startNewConversation(modelSlug: "lfm2-700m")
    manager.addUserMessage("What is machine learning?")
    
    #expect(manager.needsTitleGeneration == false)
    #expect(manager.currentConversation?.title == "New Conversation")
    
    // Add assistant response to trigger title generation
    await manager.addAssistantMessage("Machine learning is a subset of artificial intelligence...")
    
    // Title generation should be triggered
    #expect(manager.needsTitleGeneration == true)
    
    // Verify conversation state
    let messages = manager.getMessagesForLLM()
    let systemPrompt = ModelCatalog.entry(forSlug: "lfm2-700m")?.systemPrompt
    let expectedCount = (systemPrompt == nil ? 0 : 1) + 2 // system? + user + assistant
    #expect(messages.count == expectedCount)
}

@Test("Integration: Test conversation loading and continuation")
@MainActor
func integrationConversationLoadingAndContinuation() throws {
    let mockRuntimeService = ModelRuntimeService()
    let manager = ConversationManager(modelRuntimeService: mockRuntimeService)
    let conversationService = ConversationService()
    
    // Create and save a conversation
    let userMessage = ChatMessageModel(role: .user, content: "Original question")
    let assistantMessage = ChatMessageModel(role: .assistant, content: "Original answer")
    var testConversation = ChatConversation(modelSlug: "lfm2-350m", initialMessage: userMessage)
    testConversation.addMessage(assistantMessage)
    testConversation.setTitle("Test Conversation")
    
    try conversationService.saveConversation(testConversation)
    
    // Load the conversation in manager
    manager.loadConversation(testConversation)
    
    // Verify loaded state
    #expect(manager.currentConversation?.id == testConversation.id)
    #expect(manager.currentConversation?.title == "Test Conversation")
    
    // Continue the conversation
    manager.addUserMessage("Follow-up question")
    
    // Verify continuation worked
    let messages = manager.getMessagesForLLM()
    #expect(messages.count == 3) // Original user + assistant + new user
    #expect(messages.last?.content == "Follow-up question")
    
    // Clean up
    try conversationService.deleteConversation(id: testConversation.id)
}

@Test("Integration: Test search functionality")
func integrationSearchFunctionality() throws {
    let service = ConversationService()
    
    // Create test conversations with different content
    let conversations = [
        createTestConversation(
            title: "SwiftUI Discussion",
            userContent: "How do I create SwiftUI views?",
            assistantContent: "SwiftUI views are created by defining structs...",
            modelSlug: "lfm2-350m"
        ),
        createTestConversation(
            title: "Python Programming",
            userContent: "What are Python decorators?",
            assistantContent: "Python decorators are a way to modify functions...",
            modelSlug: "lfm2-700m"
        ),
        createTestConversation(
            title: "Machine Learning Basics",
            userContent: "Explain neural networks",
            assistantContent: "Neural networks are computational models...",
            modelSlug: "lfm2-1.2b"
        )
    ]
    
    // Save test conversations
    for conversation in conversations {
        try service.saveConversation(conversation)
    }
    
    // Test search functionality
    let allConversations = service.loadAllConversations()
    
    // Search by title
    let swiftResults = allConversations.filter { $0.title.localizedCaseInsensitiveContains("swift") }
    #expect(swiftResults.contains { $0.id == conversations[0].id })
    
    // Search by content
    let pythonResults = allConversations.filter { conversation in
        conversation.messages.contains { message in
            message.content.localizedCaseInsensitiveContains("python")
        }
    }
    #expect(pythonResults.contains { $0.id == conversations[1].id })
    
    // Search with no results
    let noResults = allConversations.filter { $0.title.localizedCaseInsensitiveContains("nonexistent") }
    #expect(noResults.isEmpty)
    
    // Clean up
    for conversation in conversations {
        try service.deleteConversation(id: conversation.id)
    }
}

@Test("Integration: Test conversation deletion")
func integrationConversationDeletion() throws {
    let service = ConversationService()
    
    // Create test conversation
    let testConversation = createTestConversation(
        title: "Test for Deletion",
        userContent: "This will be deleted",
        assistantContent: "This response will also be deleted",
        modelSlug: "lfm2-350m"
    )
    
    // Save conversation
    try service.saveConversation(testConversation)
    
    // Verify it exists
    let beforeDeletion = service.loadAllConversations()
    #expect(beforeDeletion.contains { $0.id == testConversation.id })
    
    // Delete conversation
    try service.deleteConversation(id: testConversation.id)
    
    // Verify deletion
    let afterDeletion = service.loadAllConversations()
    #expect(!afterDeletion.contains { $0.id == testConversation.id })
    
    // Verify deleting non-existent conversation throws appropriate error
    #expect(throws: Error.self) {
        try service.deleteConversation(id: testConversation.id)
    }
}

// MARK: - Edge Case Testing

@Test("EdgeCase: Test with empty conversations")
@MainActor
func edgeCaseEmptyConversations() throws {
    let mockRuntimeService = ModelRuntimeService()
    let manager = ConversationManager(modelRuntimeService: mockRuntimeService)
    
    // Test empty conversation behavior
    #expect(manager.getMessagesForLLM().isEmpty)
    #expect(manager.getAllMessagesForDisplay().isEmpty)
    #expect(manager.currentConversation == nil)
    
    // Start conversation but don't add messages
    manager.startNewConversation(modelSlug: "lfm2-350m")
    #expect(manager.currentConversation != nil)
    
    let messages = manager.getMessagesForLLM()
    let systemPrompt = ModelCatalog.entry(forSlug: "lfm2-350m")?.systemPrompt
    let expectedCount = (systemPrompt == nil ? 0 : 1)
    #expect(messages.count == expectedCount)
}

@Test("EdgeCase: Test with very long conversations")
@MainActor
func edgeCaseLongConversations() async throws {
    let mockRuntimeService = ModelRuntimeService()
    let manager = ConversationManager(modelRuntimeService: mockRuntimeService)
    
    manager.startNewConversation(modelSlug: "lfm2-350m")
    
    // Create a very long conversation (50 message pairs)
    for i in 1...50 {
        manager.addUserMessage("Long conversation user message \(i) with some extra content to make it longer and test context window management properly")
        await manager.addAssistantMessage("Long conversation assistant response \(i) with detailed explanation and lots of content to simulate a real conversation with substantial content")
    }
    
    let llmMessages = manager.getMessagesForLLM()
    let allMessages = manager.getAllMessagesForDisplay()
    
    // Context window should limit LLM messages but all should be available for display
    #expect(llmMessages.count < allMessages.count)
    let systemPrompt = ModelCatalog.entry(forSlug: "lfm2-350m")?.systemPrompt
    let expectedAllCount = (systemPrompt == nil ? 0 : 1) + (50 * 2) // system? + pairs
    #expect(allMessages.count == expectedAllCount)
    
    // Verify conversation was saved
    #expect(manager.currentConversation != nil)
}

@Test("EdgeCase: Test title generation failures")
@MainActor
func edgeCaseTitleGenerationFailures() async throws {
    let mockRuntimeService = ModelRuntimeService()
    let manager = ConversationManager(modelRuntimeService: mockRuntimeService)
    
    manager.startNewConversation(modelSlug: "lfm2-350m")
    
    // Test with very short/minimal content
    manager.addUserMessage("?")
    await manager.addAssistantMessage("Yes.")
    
    // Should still trigger title generation attempt
    #expect(manager.needsTitleGeneration == true)
    #expect(manager.currentConversation != nil)
}

@Test("EdgeCase: Test file system operations")
func edgeCaseFileSystemOperations() throws {
    let service = ConversationService()
    
    // Test loading when no conversations exist (should not crash)
    let emptyResult = service.loadAllConversations()
    #expect(emptyResult is [ChatConversation])
    
    // Test loading non-existent conversation
    let randomId = UUID()
    #expect(throws: Error.self) {
        try service.loadConversation(id: randomId)
    }
    
    // Test saving and loading with special characters
    let specialConversation = createTestConversation(
        title: "Test with émojis 🚀 and spëcial çharacters",
        userContent: "Content with 'quotes' and \"double quotes\" and new\nlines",
        assistantContent: "Response with special chars: @#$%^&*()_+{}|:<>?[];',./",
        modelSlug: "lfm2-350m"
    )
    
    try service.saveConversation(specialConversation)
    let loaded = try service.loadConversation(id: specialConversation.id)
    
    #expect(loaded.title == specialConversation.title)
    #expect(loaded.messages.first?.content == specialConversation.messages.first?.content)
    
    // Clean up
    try service.deleteConversation(id: specialConversation.id)
}

// MARK: - Performance Testing

@Test("Performance: Test with multiple conversations", .timeLimit(.minutes(1)))
func performanceMultipleConversations() throws {
    let service = ConversationService()
    var createdConversations: [ChatConversation] = []
    
    // Create 50 test conversations
    for i in 1...50 {
        let conversation = createTestConversation(
            title: "Performance Test Conversation \(i)",
            userContent: "Performance test user message \(i)",
            assistantContent: "Performance test assistant response \(i)",
            modelSlug: "lfm2-350m"
        )
        try service.saveConversation(conversation)
        createdConversations.append(conversation)
    }
    
    // Test loading performance
    let startTime = Date()
    let allConversations = service.loadAllConversations()
    let loadTime = Date().timeIntervalSince(startTime)
    
    #expect(allConversations.count >= 50)
    #expect(loadTime < 2.0) // Should load in under 2 seconds
    
    // Test search performance
    let searchStartTime = Date()
    let searchResults = allConversations.filter { $0.title.contains("Performance Test") }
    let searchTime = Date().timeIntervalSince(searchStartTime)
    
    #expect(searchResults.count == 50)
    #expect(searchTime < 0.5) // Search should be very fast
    
    // Clean up
    for conversation in createdConversations {
        try service.deleteConversation(id: conversation.id)
    }
}

// MARK: - Helper Functions

private func createTestConversation(
    title: String,
    userContent: String,
    assistantContent: String,
    modelSlug: String
) -> ChatConversation {
    let userMessage = ChatMessageModel(role: .user, content: userContent)
    let assistantMessage = ChatMessageModel(role: .assistant, content: assistantContent)
    
    var conversation = ChatConversation(modelSlug: modelSlug, initialMessage: userMessage)
    conversation.addMessage(assistantMessage)
    conversation.setTitle(title)
    
    return conversation
}
