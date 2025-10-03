import Foundation
import MLXLLM
import MLXLMCommon

actor GemmaInferenceService {
    enum InferenceError: LocalizedError {
        case emptyConversation
        case modelUnavailable
        case missingToken

        var errorDescription: String? {
            switch self {
            case .emptyConversation:
                return "Conversation is empty"
            case .modelUnavailable:
                return "Model files are not available yet"
            case .missingToken:
                return "Hugging Face token is missing. Provide LFM2ONIOS_HF_TOKEN via Environment.plist, Info.plist, or environment"
            }
        }
    }

    private let modelDirectory: URL
    private var container: ModelContainer?
    private var loadingTask: Task<ModelContainer, Error>?

    init(modelDirectory: URL) {
        self.modelDirectory = modelDirectory
    }

    func preloadModel() async throws {
        print("runtime: { event: \"gemma:preload:start\" }")
        _ = try await loadContainer()
        print("runtime: { event: \"gemma:preload:ready\" }")
    }

    func tokenStream(
        conversation: [ChatMessageModel],
        maxTokens: Int? = nil,
        parameters: GenerateParameters = GenerateParameters()
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard !conversation.isEmpty else {
            throw InferenceError.emptyConversation
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: modelDirectory.path) else {
            throw InferenceError.modelUnavailable
        }

        let container = try await loadContainer()
        var generationParameters = parameters
        if let maxTokens {
            generationParameters.maxTokens = maxTokens
            print("runtime: { event: \"gemma:maxTokens\", value: \(maxTokens) }")
        }
        let chatMessages = conversation.map { message -> Chat.Message in
            let role: Chat.Message.Role
            switch message.role {
            case .user: role = .user
            case .assistant: role = .assistant
            case .system: role = .system
            }
            return Chat.Message(role: role, content: message.content)
        }

        let userInput = UserInput(chat: chatMessages)

        let parametersToUse = generationParameters

        let (_, generationStream) = try await container.perform { context in
            let preparedInput = try await context.processor.prepare(input: userInput)
            let stream = try MLXLMCommon.generate(
                input: preparedInput,
                parameters: parametersToUse,
                context: context
            )
            return (preparedInput.text.tokens.size, stream)
        }

        return AsyncThrowingStream { continuation in
            let streamingTask = Task {
                for await result in generationStream {
                    if Task.isCancelled {
                        break
                    }
                    if let chunk = result.chunk, !chunk.isEmpty {
                        continuation.yield(chunk)
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                streamingTask.cancel()
            }
        }
    }

    private func loadContainer() async throws -> ModelContainer {
        if let container {
            return container
        }

        if let loadingTask {
            return try await loadingTask.value
        }

        let task = Task { () throws -> ModelContainer in
            let configuration = ModelConfiguration(directory: modelDirectory)
            let hub = try GemmaHubClient.shared()
            return try await LLMModelFactory.shared.loadContainer(
                hub: hub,
                configuration: configuration
            )
        }
        loadingTask = task
        let result: ModelContainer
        do {
            result = try await task.value
        } catch is GemmaHubClient.Error {
            loadingTask = nil
            throw InferenceError.missingToken
        }
        loadingTask = nil
        container = result
        return result
    }
}
