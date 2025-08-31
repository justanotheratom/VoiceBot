import Testing
import Foundation
@testable import lfm2oniosFeature

@Test("ModelCatalog has curated entries")
func catalogEntries() {
    #expect(!ModelCatalog.all.isEmpty)
    #expect(ModelCatalog.entry(forSlug: "lfm2-350m")?.displayName.contains("LFM2") == true)
}

@Test("SelectedModel encodes and decodes via JSON")
func selectedModelCodable() throws {
    let original = SelectedModel(slug: "slug", displayName: "Name", provider: "Leap", quantizationSlug: nil, localURL: nil)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(SelectedModel.self, from: data)
    #expect(decoded == original)
}

actor _Accumulator {
    private(set) var text: String = ""
    func append(_ token: String) { text += token }
}

@Test("ModelRuntimeService initializes correctly and reports loaded state")
@MainActor
func runtimeServiceState() async throws {
    let svc = ModelRuntimeService()

    // Initially no model should be loaded
    #expect(!(await svc.isModelLoaded))
    #expect(await svc.currentModelURL == nil)
    
    // Test error when trying to stream without loading a model
    do {
        try await svc.streamResponse(prompt: "test") { token in }
        #expect(Bool(false), "Should throw error when no model loaded")
    } catch ModelRuntimeError.notLoaded {
        // Expected error
        #expect(true)
    }
}

@Test("PersistenceService saves and loads models correctly")
func persistenceService() throws {
    let testDefaults = UserDefaults(suiteName: UUID().uuidString)!
    let service = PersistenceService(defaults: testDefaults)
    
    // Test initial state
    #expect(service.loadSelectedModel() == nil)
    
    // Test save and load
    let model = SelectedModel(
        slug: "test-model", 
        displayName: "Test Model",
        provider: "Test Provider",
        quantizationSlug: "test-quant",
        localURL: URL(string: "file:///test/path")
    )
    
    service.saveSelectedModel(model)
    let loaded = service.loadSelectedModel()
    #expect(loaded == model)
    
    // Test clear
    service.clearSelectedModel()
    #expect(service.loadSelectedModel() == nil)
}

@Test("ModelStorageService correctly identifies downloaded models")
func modelStorageService() throws {
    let storage = ModelStorageService()
    let testEntry = ModelCatalogEntry(
        id: "test-id",
        displayName: "Test Model",
        provider: "Test",
        slug: "test-slug",
        quantizationSlug: "test-quant",
        estDownloadMB: 100,
        contextWindow: 2048,
        shortDescription: "A test model",
        downloadURLString: "https://example.com/model.zip"
    )
    
    // Should not be downloaded initially
    #expect(!storage.isDownloaded(entry: testEntry))
    
    // Test expected bundle URL generation
    let expectedURL = try storage.expectedBundleURL(for: testEntry)
    #expect(expectedURL.pathExtension == "bundle")
    #expect(expectedURL.lastPathComponent.contains("test-quant"))
}

@Test("ModelCatalog provides consistent entries")
func modelCatalogConsistency() {
    let entries = ModelCatalog.all
    
    // Check we have expected models
    #expect(entries.count >= 3)
    
    // Check all entries have required fields
    for entry in entries {
        #expect(!entry.slug.isEmpty)
        #expect(!entry.displayName.isEmpty)
        #expect(!entry.provider.isEmpty)
        #expect(entry.estDownloadMB > 0)
        #expect(entry.contextWindow > 0)
    }
    
    // Check lookup works
    let first = entries.first!
    let found = ModelCatalog.entry(forSlug: first.slug)
    #expect(found?.id == first.id)
}

@Test("Message model has correct properties")
func messageModel() {
    let userMessage = Message(role: .user, text: "Hello")
    let assistantMessage = Message(role: .assistant, text: "Hi there")
    
    #expect(userMessage.role == .user)
    #expect(assistantMessage.role == .assistant)
    #expect(userMessage.text == "Hello")
    #expect(assistantMessage.text == "Hi there")
    #expect(userMessage != assistantMessage)
}

@Test("DownloadState equality works correctly")
func downloadStateEquality() {
    let notStarted1 = DownloadState.notStarted
    let notStarted2 = DownloadState.notStarted
    let inProgress = DownloadState.inProgress(progress: 0.5)
    let downloaded = DownloadState.downloaded(localURL: URL(string: "file:///test")!)
    let failed = DownloadState.failed(error: "Test error")
    
    #expect(notStarted1 == notStarted2)
    #expect(notStarted1 != inProgress)
    #expect(inProgress != downloaded)
    #expect(downloaded != failed)
}

@Test("TokenStats model has correct properties")
func tokenStatsModel() {
    let stats = TokenStats(tokens: 42, timeToFirstToken: 1.5, tokensPerSecond: 28.0)
    
    #expect(stats.tokens == 42)
    #expect(stats.timeToFirstToken == 1.5)
    #expect(stats.tokensPerSecond == 28.0)
    
    // Test with optional values
    let minimalStats = TokenStats(tokens: 10)
    #expect(minimalStats.tokens == 10)
    #expect(minimalStats.timeToFirstToken == nil)
    #expect(minimalStats.tokensPerSecond == nil)
}

@Test("Message with token stats works correctly")
func messageWithTokenStats() {
    let stats = TokenStats(tokens: 25, timeToFirstToken: 0.8, tokensPerSecond: 31.25)
    let message = Message(role: .assistant, text: "Hello world!", stats: stats)
    
    #expect(message.role == .assistant)
    #expect(message.text == "Hello world!")
    #expect(message.stats?.tokens == 25)
    #expect(message.stats?.timeToFirstToken == 0.8)
    #expect(message.stats?.tokensPerSecond == 31.25)
    
    // Test message without stats
    let userMessage = Message(role: .user, text: "Hi there")
    #expect(userMessage.stats == nil)
}

@Test("ConversationService persistence works correctly")
func conversationPersistence() async throws {
    let service = ConversationService()
    let message = ChatMessageModel(role: .user, content: "Test message")
    var conversation = ChatConversation(modelSlug: "test-model", initialMessage: message)
    
    // Save and load
    try service.saveConversation(conversation)
    let loaded = try service.loadConversation(id: conversation.id)
    
    #expect(loaded.id == conversation.id)
    #expect(loaded.messages.count == 1)
    #expect(loaded.messages.first?.content == "Test message")
    #expect(loaded.modelSlug == "test-model")
    #expect(loaded.title == "New Conversation")
    
    // Test updating conversation
    conversation.addMessage(ChatMessageModel(role: .assistant, content: "Test response"))
    conversation.setTitle("Updated Title")
    try service.saveConversation(conversation)
    
    let updatedLoaded = try service.loadConversation(id: conversation.id)
    #expect(updatedLoaded.messages.count == 2)
    #expect(updatedLoaded.title == "Updated Title")
    
    // Test loading all conversations
    let allConversations = service.loadAllConversations()
    #expect(allConversations.contains { $0.id == conversation.id })
    
    // Cleanup
    try service.deleteConversation(id: conversation.id)
}

@Test("ChatConversation model methods work correctly")
func chatConversationModel() {
    var conversation = ChatConversation(modelSlug: "test-model")
    
    // Test initial state
    #expect(conversation.title == "New Conversation")
    #expect(conversation.messages.isEmpty)
    #expect(conversation.archivedMessages.isEmpty)
    #expect(conversation.modelSlug == "test-model")
    
    // Test adding messages
    let message1 = ChatMessageModel(role: .user, content: "Hello", tokenCount: 5)
    let message2 = ChatMessageModel(role: .assistant, content: "Hi there", tokenCount: 10)
    
    conversation.addMessage(message1)
    conversation.addMessage(message2)
    
    #expect(conversation.messages.count == 2)
    #expect(conversation.totalTokenCount == 15)
    #expect(conversation.allMessages.count == 2)
    
    // Test archiving messages
    conversation.archiveOldMessages([message1])
    #expect(conversation.messages.count == 1)
    #expect(conversation.archivedMessages.count == 1)
    #expect(conversation.allMessages.count == 2)
    
    // Test title setting
    conversation.setTitle("Test Conversation")
    #expect(conversation.title == "Test Conversation")
}

@Test("ChatMessageModel works correctly")
func chatMessageModel() {
    let message = ChatMessageModel(role: .user, content: "Test message", tokenCount: 5)
    
    #expect(message.role == .user)
    #expect(message.content == "Test message")
    #expect(message.tokenCount == 5)
    #expect(message.id != UUID())
    
    let message2 = ChatMessageModel(role: .assistant, content: "Response")
    #expect(message2.tokenCount == nil)
    #expect(message != message2)
}

@Test("ChatMessageModel token estimation works correctly")
func chatMessageTokenEstimation() {
    var message = ChatMessageModel(role: .user, content: "Hello world test message")
    #expect(message.tokenCount == nil)
    
    message.estimateAndSetTokenCount()
    #expect(message.tokenCount != nil)
    #expect(message.tokenCount! > 0)
}

@Test("ContextWindowManager token estimation works")
func contextWindowManagerTokenEstimation() {
    let manager = ContextWindowManager()
    
    // Test token estimation
    let tokenCount = manager.estimateTokenCount("Hello world")
    #expect(tokenCount > 0)
    #expect(tokenCount == 2) // 2 words * 1.3 = 2.6 -> 2 tokens (Int conversion truncates)
    
    // Test empty string
    let emptyCount = manager.estimateTokenCount("")
    #expect(emptyCount == 1) // Minimum 1 token
    
    // Test longer text
    let longCount = manager.estimateTokenCount("This is a longer test message with more words")
    #expect(longCount > tokenCount)
}

@Test("ContextWindowManager context limits work")
func contextWindowManagerLimits() {
    let manager = ContextWindowManager()
    
    // Test known models
    #expect(manager.getContextLimit(for: "lfm2-350m") == 4096)
    #expect(manager.getContextLimit(for: "lfm2-700m") == 4096)
    #expect(manager.getContextLimit(for: "lfm2-1.2b") == 4096)
    
    // Test unknown model defaults to 4096
    #expect(manager.getContextLimit(for: "unknown-model") == 4096)
}

@Test("ContextWindowManager archiving logic works")
func contextWindowManagerArchiving() {
    let manager = ContextWindowManager()
    
    // Create a conversation with many messages to trigger archiving
    var conversation = ChatConversation(modelSlug: "lfm2-350m")
    
    // Add messages that would exceed 70% of available context
    // Available for history: 4096 - (4096 * 0.3) = 2867 tokens
    // 70% threshold: 2867 * 0.7 = 2006 tokens
    // We'll add messages to exceed this
    
    for i in 1...50 {
        let message = ChatMessageModel(role: .user, content: "This is test message number \(i) with some additional content", tokenCount: 50)
        conversation.addMessage(message)
    }
    
    // Should recommend archiving at this point
    #expect(manager.shouldArchiveMessages(in: conversation))
    
    // Get messages to archive
    let messagesToArchive = manager.getMessagesToArchive(from: conversation)
    #expect(!messagesToArchive.isEmpty)
    #expect(messagesToArchive.count < conversation.messages.count) // Should keep some messages
}

@Test("ContextWindowManager preserves recent messages")
func contextWindowManagerPreservesRecent() {
    let manager = ContextWindowManager()
    var conversation = ChatConversation(modelSlug: "lfm2-350m")
    
    // Add old messages
    for i in 1...10 {
        let message = ChatMessageModel(role: .user, content: "Old message \(i)", tokenCount: 200)
        conversation.addMessage(message)
    }
    
    // Add recent important message
    let recentMessage = ChatMessageModel(role: .user, content: "Recent important message", tokenCount: 50)
    conversation.addMessage(recentMessage)
    
    let messagesToArchive = manager.getMessagesToArchive(from: conversation)
    
    // The recent message should not be in the archive list
    #expect(!messagesToArchive.contains { $0.id == recentMessage.id })
}
