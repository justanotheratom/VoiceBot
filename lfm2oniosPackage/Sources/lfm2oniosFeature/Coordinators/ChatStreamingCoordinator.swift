import Foundation
import Observation

/// Coordinates chat message streaming and state management
@available(iOS 18.0, macOS 13.0, *)
@MainActor
@Observable
final class ChatStreamingCoordinator {
    // MARK: - Published State

    var messages: [Message] = []
    var isStreaming = false
    var userRequestedStop = false

    // MARK: - Dependencies

    @ObservationIgnored private let runtime: ModelRuntimeService
    @ObservationIgnored private let conversationStore: ConversationStore?
    @ObservationIgnored private let contextManager: ContextWindowManager
    @ObservationIgnored private let modelSlug: String

    // MARK: - Private State

    @ObservationIgnored private var streamingTask: Task<Void, Never>?
    @ObservationIgnored private var scrollTimer: Timer?

    // MARK: - Initialization

    init(
        runtime: ModelRuntimeService,
        conversationStore: ConversationStore?,
        contextManager: ContextWindowManager = ContextWindowManager(),
        modelSlug: String
    ) {
        self.runtime = runtime
        self.conversationStore = conversationStore
        self.contextManager = contextManager
        self.modelSlug = modelSlug
    }

    // MARK: - Public API

    /// Send a message and start streaming the response
    func sendMessage(_ prompt: String) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        // CRITICAL: Cancel and wait for previous streaming task to fully complete
        // before starting a new one to avoid race conditions
        if let existingTask = streamingTask {
            existingTask.cancel()

            // Start the new message in a task that waits for cleanup
            Task { @MainActor in
                // Wait for the old task to finish its cleanup
                await existingTask.value

                // Now safe to proceed
                startNewMessage(prompt: trimmedPrompt)
            }
            return
        }

        startNewMessage(prompt: trimmedPrompt)
    }

    /// Stop the current streaming task
    func stopStreaming(userInitiated: Bool) {
        userRequestedStop = userInitiated

        // Cancel the task but don't nil it out - let it finish cleanup naturally
        streamingTask?.cancel()

        scrollTimer?.invalidate()
        scrollTimer = nil

        // Don't set isStreaming here - let the task cleanup handle it
        // to avoid race conditions
    }

    /// Clear all messages and start a new conversation
    func clearMessages() {
        if isStreaming {
            // Clear messages immediately for instant visual feedback
            messages.removeAll()
            // Cancel the streaming task to stop further updates
            stopStreaming(userInitiated: false)
            // Fully reload the model to ensure clean state after cancellation
            Task {
                if let currentURL = await runtime.currentModelURL {
                    await runtime.unloadModel()
                    if let entry = ModelCatalog.entry(forSlug: modelSlug) {
                        try? await runtime.loadModel(entry: entry, at: currentURL)
                    }
                }
            }
        } else {
            // If not streaming, clear immediately as before
            messages.removeAll()
        }

        // Start a new conversation
        conversationStore?.startNewConversation(modelSlug: modelSlug)
    }

    /// Load messages from a conversation
    func loadConversation(_ conversation: ChatConversation) {
        // Clear current messages
        messages.removeAll()

        // Load conversation in manager
        conversationStore?.loadConversation(conversation)

        // Convert ChatMessageModel to UI Message format and display
        let conversationMessages = conversationStore?.getAllMessagesForDisplay() ?? []
        messages = conversationMessages.compactMap { chatMessage in
            switch chatMessage.role {
            case .user:
                return Message(role: .user, text: chatMessage.content)
            case .assistant:
                return Message(role: .assistant, text: chatMessage.content)
            case .system:
                return nil
            }
        }
    }

    // MARK: - Private Methods

    private func startNewMessage(prompt: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            messages.append(Message(role: .user, text: prompt))
            messages.append(Message(role: .assistant, text: ""))
        }

        // Add user message to conversation manager
        conversationStore?.addUserMessage(prompt)

        let assistantIndex = messages.count - 1
        isStreaming = true

        // Start smooth scroll timer during streaming
        scrollTimer?.invalidate()
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isStreaming else { return }
                // Trigger scroll via notification or delegate pattern if needed
            }
        }

        // Store and cancel any previous streaming task
        let tokenBudget = contextManager.responseTokenBudget(for: modelSlug)

        streamingTask = Task { @MainActor in
            let startTime = Date()
            var firstTokenTime: Date?
            var tokenCount = 0

            do {
                let llmMessages = conversationStore?.getMessagesForLLM() ?? []

                try await runtime.streamResponse(
                    prompt: prompt,
                    conversation: llmMessages,
                    tokenLimit: tokenBudget
                ) { token in
                    await MainActor.run {
                        // Check if task was cancelled or messages were cleared
                        guard !Task.isCancelled, assistantIndex < messages.count else {
                            return
                        }

                        if firstTokenTime == nil {
                            firstTokenTime = Date()
                        }
                        tokenCount += 1
                        messages[assistantIndex].text += token
                    }
                }

                // Check if task was cancelled before updating stats
                if !Task.isCancelled, assistantIndex < messages.count {
                    // Calculate statistics
                    let stats = TokenStatsCalculator.calculate(
                        tokenCount: tokenCount,
                        startTime: startTime,
                        firstTokenTime: firstTokenTime,
                        endTime: Date()
                    )

                    // Update message with stats
                    messages[assistantIndex].stats = stats

                    // Add assistant response to conversation manager
                    let assistantResponse = messages[assistantIndex].text
                    Task { @MainActor in
                        await conversationStore?.addAssistantMessage(assistantResponse)
                    }
                    userRequestedStop = false
                }
            } catch is CancellationError {

                if assistantIndex < messages.count {
                    let partialResponse = messages[assistantIndex].text
                    if !partialResponse.isEmpty, userRequestedStop {
                        Task { @MainActor in
                            await conversationStore?.addAssistantMessage(partialResponse)
                        }
                    }
                }
                userRequestedStop = false
            } catch {
                AppLogger.runtime().logError(event: "stream:failed", error: error)
                // Only update if messages still exist and index is valid
                if assistantIndex < messages.count {
                    messages[assistantIndex].text = "❌ Error generating response: \(error.localizedDescription)\n\nPlease ensure the model is properly downloaded and loaded."
                }
            }

            // CRITICAL: Always reset streaming state, even if task was cancelled early
            // This must run regardless of early returns above
            scrollTimer?.invalidate()
            scrollTimer = nil
            isStreaming = false
            streamingTask = nil
        }
    }
}
