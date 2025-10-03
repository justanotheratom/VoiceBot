import Foundation
import os.log

/// Actor to safely accumulate title tokens from the streaming response
private actor TitleAccumulator {
    private var title: String = ""
    
    func append(_ token: String) {
        title += token
    }
    
    func getTitle() -> String {
        return title
    }
}

@Observable
@MainActor
class TitleGenerationService {
    private let logger = Logger(subsystem: "com.oneoffrepo.lfm2onios", category: "title")
    private let modelRuntimeService: ModelRuntimeService
    
    init(modelRuntimeService: ModelRuntimeService) {
        self.modelRuntimeService = modelRuntimeService
    }
    
    func generateTitle(for conversation: ChatConversation) async -> String {
        // Only generate if we have at least one user message and one assistant response
        guard let userMessageModel = conversation.messages.first(where: { $0.role == .user }),
              let assistantMessageModel = conversation.messages.first(where: { $0.role == .assistant }) else {
            return fallbackTitle()
        }
        
        let userMessage = userMessageModel.content
        let assistantMessage = assistantMessageModel.content
        
        let prompt = createTitlePrompt(userMessage: userMessage, assistantMessage: assistantMessage)
        
        do {
            logger.info("title: { event: \"generateStart\", conversationId: \"\(conversation.id)\" }")
            
            // Check if model is loaded
            guard await modelRuntimeService.isModelLoaded else {
                logger.warning("title: { event: \"generateSkipped\", reason: \"modelNotLoaded\" }")
                return fallbackTitle()
            }
            
            // Use an actor to safely accumulate the title tokens
            let titleAccumulator = TitleAccumulator()
            
            // Use the existing streamResponse method to generate title
            try await modelRuntimeService.streamResponse(
                prompt: prompt,
                conversation: [],
                tokenLimit: 64
            ) { token in
                await titleAccumulator.append(token)
            }
            
            let generatedTitle = await titleAccumulator.getTitle()
            
            let cleanTitle = cleanTitleText(generatedTitle)
            logger.info("title: { event: \"generated\", title: \"\(cleanTitle)\" }")
            return cleanTitle
            
        } catch {
            logger.error("title: { event: \"generateFailed\", error: \"\(error.localizedDescription)\" }")
            return fallbackTitle()
        }
    }
    
    private func createTitlePrompt(userMessage: String, assistantMessage: String) -> String {
        return """
        Based on the following conversation, generate a short, descriptive title (3-6 words maximum). 
        Only respond with the title, no additional text.
        
        User: \(userMessage)
        Assistant: \(assistantMessage)
        
        Title:
        """
    }
    
    private func cleanTitleText(_ title: String) -> String {
        let cleaned = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "Title:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Limit to reasonable length
        if cleaned.count > 50 {
            return String(cleaned.prefix(50)) + "..."
        }
        
        return cleaned.isEmpty ? fallbackTitle() : cleaned
    }
    
    private func fallbackTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Chat from \(formatter.string(from: Date()))"
    }
}
