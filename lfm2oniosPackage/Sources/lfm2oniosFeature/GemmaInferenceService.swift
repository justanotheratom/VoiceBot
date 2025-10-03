import Foundation
import MLXLLM
import MLXLMCommon

actor GemmaInferenceService {
    enum InferenceError: LocalizedError {
        case emptyConversation
        case modelUnavailable

        var errorDescription: String? {
            switch self {
            case .emptyConversation:
                return "Conversation is empty"
            case .modelUnavailable:
                return "Model files are not available yet"
            }
        }
    }

    private let modelDirectory: URL
    private var container: ModelContainer?
    private var loadingTask: Task<ModelContainer, Error>?

    init(modelDirectory: URL) {
        self.modelDirectory = modelDirectory
    }

    func tokenStream(
        conversation: [ChatMessageModel],
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

        let (_, generationStream) = try await container.perform { context in
            let preparedInput = try await context.processor.prepare(input: userInput)
            let stream = try MLXLMCommon.generate(
                input: preparedInput,
                parameters: parameters,
                context: context
            )
            return (preparedInput.text.tokens.size, stream)
        }

        return AsyncThrowingStream { continuation in
            Task {
                for await result in generationStream {
                    if let chunk = result.chunk, !chunk.isEmpty {
                        continuation.yield(chunk)
                    }
                }
                continuation.finish()
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
            return try await LLMModelFactory.shared.loadContainer(
                hub: GemmaHubClient.shared,
                configuration: configuration
            )
        }
        loadingTask = task
        let result = try await task.value
        loadingTask = nil
        container = result
        return result
    }
}
