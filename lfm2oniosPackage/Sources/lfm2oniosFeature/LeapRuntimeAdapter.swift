import Foundation
@preconcurrency import LeapSDK

final actor LeapRuntimeAdapter: ModelRuntimeAdapting {
    private var modelRunner: ModelRunner?
    private var currentURL: URL?

    func loadModel(at url: URL, entry: ModelCatalogEntry) async throws {
        if currentURL == url, modelRunner != nil {
            print("runtime: { event: \"leap:load:skipped\", reason: \"alreadyLoaded\" }")
            return
        }

        try validateModel(at: url)

        do {
            let runner = try await Leap.load(url: url)
            modelRunner = runner
            currentURL = url
            print("runtime: { event: \"leap:load:success\", slug: \"\(entry.slug)\" }")
        } catch {
            print("runtime: { event: \"leap:load:failed\", error: \"\(error.localizedDescription)\" }")
            throw ModelRuntimeError.underlying(error.localizedDescription)
        }
    }

    func unload() async {
        modelRunner = nil
        currentURL = nil
    }

    func resetConversation() async {
        // Conversation state is derived from provided history; nothing to reset.
    }

    func streamResponse(
        prompt: String,
        conversation: [ChatMessageModel],
        tokenLimit: Int,
        onToken: @Sendable @escaping (String) async -> Void
    ) async throws {
        guard let runner = modelRunner else {
            throw ModelRuntimeError.notLoaded
        }

        let (history, userPrompt) = splitHistoryAndPrompt(from: conversation, fallbackPrompt: prompt)
        let historyMessages = history.map(convertToLeapMessage)
        let conversation = Conversation(modelRunner: runner, history: historyMessages)
        let userMessage = ChatMessage(role: .user, content: [.text(userPrompt)])
        var generatedTokenEstimate = 0

        do {
            for try await response in conversation.generateResponse(message: userMessage) {
                try Task.checkCancellation()
                switch response {
                case .chunk(let text):
                    guard !text.isEmpty else { continue }
                    await onToken(text)
                    generatedTokenEstimate += Self.estimateTokenCount(for: text)
                    if generatedTokenEstimate >= tokenLimit {
                        print("runtime: { event: \"leap:tokenLimitReached\", limit: \(tokenLimit), estimatedTokens: \(generatedTokenEstimate) }")
                        return
                    }
                case .reasoningChunk(_), .functionCall(_):
                    continue
                case .complete(_, _):
                    continue
                @unknown default:
                    continue
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ModelRuntimeError.underlying(String(describing: error))
        }
    }

    private static func estimateTokenCount(for chunk: String) -> Int {
        let components = chunk.split { $0.isWhitespace }
        return max(components.count, 1)
    }

    private func validateModel(at url: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw ModelRuntimeError.fileMissing
        }

        if isDir.boolValue {
            let contents = try fm.contentsOfDirectory(atPath: url.path)
            guard !contents.isEmpty else {
                throw ModelRuntimeError.fileMissing
            }
        } else {
            let attributes = try fm.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            guard fileSize > 1024 else {
                throw ModelRuntimeError.fileMissing
            }
        }
    }

    private func convertToLeapMessage(_ message: ChatMessageModel) -> ChatMessage {
        let role: ChatMessageRole
        switch message.role {
        case .user: role = .user
        case .assistant: role = .assistant
        case .system: role = .system
        }
        return ChatMessage(role: role, content: [.text(message.content)])
    }

    private func splitHistoryAndPrompt(from messages: [ChatMessageModel], fallbackPrompt: String) -> ([ChatMessageModel], String) {
        guard let last = messages.last, last.role == .user else {
            return (messages, fallbackPrompt)
        }
        return (Array(messages.dropLast()), last.content)
    }
}
