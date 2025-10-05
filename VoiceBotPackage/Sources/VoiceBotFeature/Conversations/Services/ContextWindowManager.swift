import Foundation
import os.log

struct ContextWindowManager {
    private let logger = Logger(subsystem: "com.oneoffrepo.voicebot", category: "context")
    
    private let defaultContextLimit = 4096
    
    func getContextLimit(for modelSlug: String) -> Int {
        let limit = ModelCatalog.entry(forSlug: modelSlug)?.contextWindow ?? defaultContextLimit
        logger.debug("context: { event: \"getLimit\", model: \"\(modelSlug)\", limit: \(limit) }")
        return limit
    }

    func responseTokenBudget(for modelSlug: String) -> Int {
        let contextLimit = getContextLimit(for: modelSlug)
        let reserved = Int(Double(contextLimit) * 0.30)
        var budget = max(reserved, 128)

        if let entry = ModelCatalog.entry(forSlug: modelSlug) {
            switch entry.runtime {
            case .mlx:
                budget = min(budget, 512)
            case .leap:
                break
            }
        } else {
            budget = min(budget, 512)
        }
        logger.debug("context: { event: \"responseBudget\", model: \"\(modelSlug)\", budget: \(budget) }")
        return budget
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
