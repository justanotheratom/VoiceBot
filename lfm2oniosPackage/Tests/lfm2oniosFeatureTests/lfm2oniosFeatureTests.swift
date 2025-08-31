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
