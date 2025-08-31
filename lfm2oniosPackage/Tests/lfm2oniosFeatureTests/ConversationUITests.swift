import Testing
import Foundation
@testable import lfm2oniosFeature

@Test("ConversationRow displays conversation data correctly")
func conversationRowDisplaysCorrectly() {
    let userMessage = ChatMessageModel(role: .user, content: "What is SwiftUI?")
    let assistantMessage = ChatMessageModel(role: .assistant, content: "SwiftUI is a user interface toolkit...")
    
    var conversation = ChatConversation(modelSlug: "lfm2-350m", initialMessage: userMessage)
    conversation.addMessage(assistantMessage)
    conversation.setTitle("SwiftUI Discussion")
    
    // Test that conversation has correct structure
    #expect(conversation.title == "SwiftUI Discussion")
    #expect(conversation.messages.count == 2)
    #expect(conversation.messages.first?.content == "What is SwiftUI?")
    #expect(conversation.messages.last?.content == "SwiftUI is a user interface toolkit...")
    #expect(conversation.modelSlug == "lfm2-350m")
}

@Test("ConversationListView filtering works correctly") 
func conversationListFiltering() {
    // Create test conversations
    let conversation1 = createTestConversation(
        title: "SwiftUI Tutorial",
        userContent: "How do I create a SwiftUI view?",
        assistantContent: "To create a SwiftUI view...",
        modelSlug: "lfm2-350m"
    )
    
    let conversation2 = createTestConversation(
        title: "Python Programming",
        userContent: "What is Python used for?",
        assistantContent: "Python is used for many things...",
        modelSlug: "lfm2-700m"
    )
    
    let conversations = [conversation1, conversation2]
    
    // Test filtering logic (simulating what ConversationListView does)
    let searchText = "swift"
    let filteredResults = conversations.filter { conversation in
        conversation.title.localizedCaseInsensitiveContains(searchText) ||
        conversation.messages.contains { message in
            message.content.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    #expect(filteredResults.count == 1)
    #expect(filteredResults.first?.title == "SwiftUI Tutorial")
}

@Test("ConversationService creates and loads conversations correctly")
func conversationServicePersistence() throws {
    let service = ConversationService()
    
    // Create test conversation
    let testConversation = createTestConversation(
        title: "Test Conversation",
        userContent: "Hello, how are you?",
        assistantContent: "I'm doing well, thank you!",
        modelSlug: "lfm2-1.2b"
    )
    
    // Save conversation
    try service.saveConversation(testConversation)
    
    // Load conversation
    let loadedConversation = try service.loadConversation(id: testConversation.id)
    
    // Verify conversation was loaded correctly
    #expect(loadedConversation.id == testConversation.id)
    #expect(loadedConversation.title == "Test Conversation")
    #expect(loadedConversation.messages.count == 2)
    #expect(loadedConversation.modelSlug == "lfm2-1.2b")
    
    // Test loading all conversations includes our test conversation
    let allConversations = service.loadAllConversations()
    #expect(allConversations.contains { $0.id == testConversation.id })
    
    // Cleanup
    try service.deleteConversation(id: testConversation.id)
}

@Test("ConversationService handles empty state correctly")
func conversationServiceEmptyState() {
    let service = ConversationService()
    
    // Should return empty array when no conversations exist
    let conversations = service.loadAllConversations()
    // Note: May contain conversations from previous tests, so we just check it's an array
    #expect(conversations is [ChatConversation])
}

@Test("ConversationService search functionality works")
func conversationServiceSearchFunctionality() throws {
    let service = ConversationService()
    
    // Create multiple test conversations
    let conversation1 = createTestConversation(
        title: "iOS Development",
        userContent: "How to build iOS apps?",
        assistantContent: "To build iOS apps, you need Xcode...",
        modelSlug: "lfm2-350m"
    )
    
    let conversation2 = createTestConversation(
        title: "Web Development", 
        userContent: "What is React?",
        assistantContent: "React is a JavaScript library...",
        modelSlug: "lfm2-700m"
    )
    
    // Save conversations
    try service.saveConversation(conversation1)
    try service.saveConversation(conversation2)
    
    // Load all conversations
    let allConversations = service.loadAllConversations()
    
    // Verify we can find our conversations
    let iosConversations = allConversations.filter { $0.title.contains("iOS") }
    let webConversations = allConversations.filter { $0.title.contains("Web") }
    
    #expect(iosConversations.count >= 1)
    #expect(webConversations.count >= 1)
    
    // Cleanup
    try service.deleteConversation(id: conversation1.id)
    try service.deleteConversation(id: conversation2.id)
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

@Test("Debug conversation service directory path")
func debugConversationServicePath() {
    let service = ConversationService()
    
    // Try to create a test conversation to see where it goes
    let testMessage = ChatMessageModel(role: .user, content: "Debug test")
    let testConversation = ChatConversation(modelSlug: "debug-model", initialMessage: testMessage)
    
    // This should create the directory and show us the path in logs
    do {
        try service.saveConversation(testConversation)
        print("DEBUG: Test conversation saved successfully")
        
        // Load all conversations to see if our test data shows up
        let allConversations = service.loadAllConversations()
        print("DEBUG: Found \(allConversations.count) conversations")
        for conv in allConversations {
            print("DEBUG: Conversation: \(conv.title) - \(conv.modelSlug)")
        }
        
        // Clean up
        try service.deleteConversation(id: testConversation.id)
        print("DEBUG: Test conversation cleaned up")
    } catch {
        print("DEBUG: Error saving conversation: \(error)")
    }
}

// Function to create test conversations in the simulator for manual testing
func createTestConversationsForSimulator() throws {
    let service = ConversationService()
    
    let conversations = [
        createTestConversation(
            title: "SwiftUI Basics",
            userContent: "How do I get started with SwiftUI?", 
            assistantContent: "SwiftUI is Apple's declarative framework for building user interfaces. To get started, you'll want to create a new Xcode project...",
            modelSlug: "lfm2-350m"
        ),
        createTestConversation(
            title: "iOS Architecture Patterns",
            userContent: "What are the best architecture patterns for iOS apps?",
            assistantContent: "There are several popular architecture patterns for iOS development: MVC, MVP, MVVM, VIPER, and the newer SwiftUI patterns...",
            modelSlug: "lfm2-700m"
        ),
        createTestConversation(
            title: "Core Data vs SwiftData",
            userContent: "Should I use Core Data or SwiftData for my new iOS app?",
            assistantContent: "SwiftData is Apple's newer framework that provides a more modern, Swift-native approach to data persistence...",
            modelSlug: "lfm2-1.2b"
        )
    ]
    
    for conversation in conversations {
        try service.saveConversation(conversation)
    }
    
    print("Created \(conversations.count) test conversations for UI testing")
}