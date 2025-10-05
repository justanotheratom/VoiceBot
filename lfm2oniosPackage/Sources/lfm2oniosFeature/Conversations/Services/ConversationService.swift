import Foundation
import os.log

/// Stateless service for conversation file persistence
struct ConversationService: Sendable {
    private let logger = Logger(subsystem: "com.oneoffrepo.lfm2onios", category: "conversation")

    init() {}

    // MARK: - Persistence

    func saveConversation(_ conversation: ChatConversation) throws {
        let conversationsDirectory = Self.conversationsDirectory()
        Self.createConversationsDirectoryIfNeeded(at: conversationsDirectory)
        let fileURL = Self.conversationFileURL(for: conversation.id, in: conversationsDirectory)
        let data = try JSONEncoder().encode(conversation)
        try data.write(to: fileURL)
        logger.info("conversation: { event: \"saved\", id: \"\(conversation.id)\", messageCount: \(conversation.messages.count) }")
    }
    
    func loadConversation(id: UUID) throws -> ChatConversation {
        let conversationsDirectory = Self.conversationsDirectory()
        let fileURL = Self.conversationFileURL(for: id, in: conversationsDirectory)
        let data = try Data(contentsOf: fileURL)
        let conversation = try JSONDecoder().decode(ChatConversation.self, from: data)
        logger.info("conversation: { event: \"loaded\", id: \"\(id)\", messageCount: \(conversation.messages.count) }")
        return conversation
    }
    
    func loadAllConversations() -> [ChatConversation] {
        let conversationsDirectory = Self.conversationsDirectory()
        Self.createConversationsDirectoryIfNeeded(at: conversationsDirectory)

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
        let conversationsDirectory = Self.conversationsDirectory()
        let fileURL = Self.conversationFileURL(for: id, in: conversationsDirectory)
        try FileManager.default.removeItem(at: fileURL)
        logger.info("conversation: { event: \"deleted\", id: \"\(id)\" }")
    }

    // MARK: - Private Helpers

    private static func conversationsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Conversations")
    }

    private static func createConversationsDirectoryIfNeeded(at directory: URL) {
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory,
                                                     withIntermediateDirectories: true)
        }
    }

    private static func conversationFileURL(for id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}