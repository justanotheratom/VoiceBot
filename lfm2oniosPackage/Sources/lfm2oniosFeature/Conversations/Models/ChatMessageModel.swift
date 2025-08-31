import Foundation

struct ChatMessageModel: Codable, Identifiable, Equatable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date
    var tokenCount: Int?
    
    init(role: MessageRole, content: String, tokenCount: Int? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.tokenCount = tokenCount
    }
}