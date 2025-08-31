import Foundation
import os.log

struct ContextWindowManager {
    private let logger = Logger(subsystem: "com.oneoffrepo.lfm2onios", category: "context")
    
    // Model context limits (in tokens)
    private let modelContextLimits: [String: Int] = [
        "lfm2-350m": 4096,
        "lfm2-700m": 4096,
        "lfm2-1.2b": 4096
        // Add more models as needed
    ]
    
    func getContextLimit(for modelSlug: String) -> Int {
        let limit = modelContextLimits[modelSlug] ?? 4096
        logger.debug("context: { event: \"getLimit\", model: \"\(modelSlug)\", limit: \(limit) }")
        return limit
    }
    
    func estimateTokenCount(_ text: String) -> Int {
        // Simple estimation: words * 1.3 (rough approximation for English)
        let wordCount = text.split(separator: " ").count
        let estimate = Int(Double(wordCount) * 1.3)
        return max(estimate, 1) // Ensure minimum 1 token
    }
    
    func shouldArchiveMessages(in conversation: ChatConversation) -> Bool {
        let contextLimit = getContextLimit(for: conversation.modelSlug)
        let reservedForResponse = Int(Double(contextLimit) * 0.30) // Reserve 30%
        let availableForHistory = contextLimit - reservedForResponse
        let currentTokens = calculateCurrentTokens(in: conversation)
        
        let shouldArchive = currentTokens > Int(Double(availableForHistory) * 0.70) // Archive at 70%
        
        if shouldArchive {
            logger.info("context: { event: \"shouldArchive\", current: \(currentTokens), available: \(availableForHistory), threshold: \(Int(Double(availableForHistory) * 0.70)) }")
        }
        
        return shouldArchive
    }
    
    func getMessagesToArchive(from conversation: ChatConversation) -> [ChatMessageModel] {
        let contextLimit = getContextLimit(for: conversation.modelSlug)
        let reservedForResponse = Int(Double(contextLimit) * 0.30)
        let targetHistoryTokens = Int(Double(contextLimit - reservedForResponse) * 0.50) // Keep 50% of available
        
        var tokensToKeep = 0
        var messagesToKeep: [ChatMessageModel] = []
        
        // Keep recent messages, working backwards
        for message in conversation.messages.reversed() {
            let messageTokens = message.tokenCount ?? estimateTokenCount(message.content)
            if tokensToKeep + messageTokens <= targetHistoryTokens {
                messagesToKeep.insert(message, at: 0)
                tokensToKeep += messageTokens
            } else {
                break
            }
        }
        
        let messagesToArchive = conversation.messages.filter { message in
            !messagesToKeep.contains(where: { $0.id == message.id })
        }
        
        logger.info("context: { event: \"archivePlan\", toArchive: \(messagesToArchive.count), toKeep: \(messagesToKeep.count) }")
        return messagesToArchive
    }
    
    private func calculateCurrentTokens(in conversation: ChatConversation) -> Int {
        return conversation.messages.reduce(0) { total, message in
            total + (message.tokenCount ?? estimateTokenCount(message.content))
        }
    }
}