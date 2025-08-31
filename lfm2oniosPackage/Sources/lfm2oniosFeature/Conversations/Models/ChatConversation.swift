import Foundation

struct ChatConversation: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var messages: [ChatMessageModel]
    var archivedMessages: [ChatMessageModel]
    let createdAt: Date
    var updatedAt: Date
    var modelSlug: String
    
    init(modelSlug: String, initialMessage: ChatMessageModel? = nil) {
        self.id = UUID()
        self.title = "New Conversation"
        self.messages = initialMessage.map { [$0] } ?? []
        self.archivedMessages = []
        self.createdAt = Date()
        self.updatedAt = Date()
        self.modelSlug = modelSlug
    }
    
    var allMessages: [ChatMessageModel] {
        archivedMessages + messages
    }
    
    var totalTokenCount: Int {
        allMessages.compactMap(\.tokenCount).reduce(0, +)
    }
    
    mutating func addMessage(_ message: ChatMessageModel) {
        messages.append(message)
        updatedAt = Date()
    }
    
    mutating func setTitle(_ newTitle: String) {
        title = newTitle
        updatedAt = Date()
    }
    
    mutating func archiveOldMessages(_ messagesToArchive: [ChatMessageModel]) {
        archivedMessages.append(contentsOf: messagesToArchive)
        messages.removeAll { message in
            messagesToArchive.contains(where: { $0.id == message.id })
        }
        updatedAt = Date()
    }
}