import Foundation

final actor GemmaRuntimeAdapter: ModelRuntimeAdapting {
    private var inferenceService: GemmaInferenceService?
    private var modelDirectory: URL?

    func loadModel(at url: URL, entry: ModelCatalogEntry) async throws {
        guard entry.runtime == .mlx else {
            throw ModelRuntimeError.underlying("Unsupported runtime kind for Gemma adapter")
        }

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw ModelRuntimeError.fileMissing
        }

        guard let metadata = entry.gemmaMetadata else {
            throw ModelRuntimeError.underlying("Missing Gemma metadata for entry \(entry.slug)")
        }

        let primaryPath = url.appendingPathComponent(metadata.primaryFilePath)
        guard fm.fileExists(atPath: primaryPath.path) else {
            throw ModelRuntimeError.underlying("Gemma primary file missing at \(primaryPath.path)")
        }

        inferenceService = GemmaInferenceService(modelDirectory: url)
        modelDirectory = url
    }

    func unload() async {
        inferenceService = nil
        modelDirectory = nil
    }

    func resetConversation() async {
        // Stateless; nothing to reset.
    }

    func streamResponse(
        prompt: String,
        conversation: [ChatMessageModel],
        tokenLimit: Int,
        onToken: @Sendable @escaping (String) async -> Void
    ) async throws {
        guard let inferenceService else {
            throw ModelRuntimeError.notLoaded
        }

        // Ensure the latest user message matches the prompt; if not, append it.
        var conversationForModel = conversation
        if conversationForModel.last?.role != .user || conversationForModel.last?.content != prompt {
            conversationForModel.append(ChatMessageModel(role: .user, content: prompt))
        }

        let rolesSummary = conversationForModel.map { $0.role.rawValue }.joined(separator: ",")
        print("runtime: { event: \"gemma:conversation\", roles: \"\(rolesSummary)\", count: \(conversationForModel.count) }")

        let stream = try await inferenceService.tokenStream(conversation: conversationForModel, maxTokens: tokenLimit)
        for try await token in stream {
            try Task.checkCancellation()
            await onToken(token)
        }
    }
}
