import Foundation

struct ChatConversation: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var messages: [ChatMessageModel]
    var archivedMessages: [ChatMessageModel]
    let createdAt: Date
    var updatedAt: Date
    var modelSlug: String
    
    init(modelSlug: String, initialMessages: [ChatMessageModel]) {
        self.id = UUID()
        self.title = "New Conversation"
        self.messages = initialMessages
        self.archivedMessages = []
        self.createdAt = Date()
        self.updatedAt = Date()
        self.modelSlug = modelSlug
    }

    init(modelSlug: String, initialMessage: ChatMessageModel) {
        self.init(modelSlug: modelSlug, initialMessages: [initialMessage])
    }

    init(modelSlug: String) {
        self.init(modelSlug: modelSlug, initialMessages: [])
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
