import Foundation
import os.log

@Observable
class ConversationService {
    private let logger = Logger(subsystem: "com.oneoffrepo.lfm2onios", category: "conversation")
    private let conversationsDirectory: URL
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, 
                                                in: .userDomainMask).first!
        conversationsDirectory = appSupport.appendingPathComponent("Conversations")
        createConversationsDirectoryIfNeeded()
    }
    
    private func createConversationsDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: conversationsDirectory.path) {
            try? FileManager.default.createDirectory(at: conversationsDirectory, 
                                                   withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Persistence
    
    func saveConversation(_ conversation: ChatConversation) throws {
        let fileURL = conversationFileURL(for: conversation.id)
        let data = try JSONEncoder().encode(conversation)
        try data.write(to: fileURL)
        logger.info("conversation: { event: \"saved\", id: \"\(conversation.id)\", messageCount: \(conversation.messages.count) }")
    }
    
    func loadConversation(id: UUID) throws -> ChatConversation {
        let fileURL = conversationFileURL(for: id)
        let data = try Data(contentsOf: fileURL)
        let conversation = try JSONDecoder().decode(ChatConversation.self, from: data)
        logger.info("conversation: { event: \"loaded\", id: \"\(id)\", messageCount: \(conversation.messages.count) }")
        return conversation
    }
    
    func loadAllConversations() -> [ChatConversation] {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: conversationsDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension == "json" }
            
            let conversations = fileURLs.compactMap { url -> ChatConversation? in
                try? JSONDecoder().decode(ChatConversation.self, from: Data(contentsOf: url))
            }
            
            logger.info("conversation: { event: \"loadedAll\", count: \(conversations.count) }")
            return conversations.sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            logger.error("conversation: { event: \"loadAllFailed\", error: \"\(error.localizedDescription)\" }")
            return []
        }
    }
    
    func deleteConversation(id: UUID) throws {
        let fileURL = conversationFileURL(for: id)
        try FileManager.default.removeItem(at: fileURL)
        logger.info("conversation: { event: \"deleted\", id: \"\(id)\" }")
    }
    
    private func conversationFileURL(for id: UUID) -> URL {
        conversationsDirectory.appendingPathComponent("\(id.uuidString).json")
    }
}