import Foundation

protocol ModelRuntimeAdapting: Sendable {
    func loadModel(at url: URL, entry: ModelCatalogEntry) async throws
    func unload() async
    func resetConversation() async
    func streamResponse(
        prompt: String,
        conversation: [ChatMessageModel],
        tokenLimit: Int,
        onToken: @Sendable @escaping (String) async -> Void
    ) async throws
}

enum ModelRuntimeAdapterFactory {
    static func makeAdapter(for runtime: ModelRuntimeKind) -> any ModelRuntimeAdapting {
        switch runtime {
        case .leap:
            return LeapRuntimeAdapter()
        case .mlx:
            return GemmaRuntimeAdapter()
        }
    }
}
