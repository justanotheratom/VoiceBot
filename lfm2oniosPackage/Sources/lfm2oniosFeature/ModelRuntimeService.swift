import Foundation

public enum ModelRuntimeError: Error, Sendable {
    case invalidURL
    case fileMissing
    case notLoaded
    case cancelled
    case leapSDKUnavailable
    case underlying(String)
}

public actor ModelRuntimeService {
    private var adapter: (any ModelRuntimeAdapting)?
    private var currentRuntime: ModelRuntimeKind?
    private var currentEntryID: String?
    private var loadedURL: URL?

    public init() {}

    public func loadModel(entry: ModelCatalogEntry, at url: URL) async throws {
        if currentRuntime != entry.runtime {
            await adapter?.unload()
            adapter = nil
            loadedURL = nil
            currentEntryID = nil
        }

        if adapter == nil {
            adapter = ModelRuntimeAdapterFactory.makeAdapter(for: entry.runtime)
            currentRuntime = entry.runtime
        }

        if loadedURL == url, currentEntryID == entry.id {
            return
        }

        guard let currentAdapter = adapter else {
            AppLogger.runtime().log(event: "preload:error", data: [
                "slug": entry.slug,
                "reason": "adapterMissing"
            ], level: .error)
            throw ModelRuntimeError.notLoaded
        }

        try await currentAdapter.loadModel(at: url, entry: entry)
        loadedURL = url
        currentEntryID = entry.id

        AppLogger.runtime().log(event: "preload:start", data: ["slug": entry.slug])
        do {
            try await currentAdapter.preload()
            AppLogger.runtime().log(event: "preload:complete", data: ["slug": entry.slug])
        } catch {
            AppLogger.runtime().logError(event: "preload:failed", error: error, data: ["slug": entry.slug])
            throw error
        }
    }

    public func unloadModel() async {
        await adapter?.unload()
        adapter = nil
        currentRuntime = nil
        currentEntryID = nil
        loadedURL = nil
    }

    public func resetConversation() async {
        AppLogger.runtime().log(event: "service:resetConversation:called", data: [
            "hasAdapter": adapter != nil
        ])
        await adapter?.resetConversation()
        AppLogger.runtime().log(event: "service:resetConversation:complete", data: [:])
    }

    public var isModelLoaded: Bool {
        loadedURL != nil
    }

    public var currentModelURL: URL? {
        loadedURL
    }

    func streamResponse(
        prompt: String,
        conversation: [ChatMessageModel],
        tokenLimit: Int,
        onToken: @Sendable @escaping (String) async -> Void
    ) async throws {
        AppLogger.runtime().log(event: "service:streamResponse:called", data: [
            "hasAdapter": adapter != nil,
            "conversationLength": conversation.count,
            "tokenLimit": tokenLimit
        ])

        guard let adapter else {
            AppLogger.runtime().log(event: "stream:error", data: ["reason": "noModelLoaded"], level: .error)
            throw ModelRuntimeError.notLoaded
        }

        AppLogger.runtime().log(event: "service:streamResponse:delegatingToAdapter", data: [:])

        try await adapter.streamResponse(
            prompt: prompt,
            conversation: conversation,
            tokenLimit: tokenLimit,
            onToken: onToken
        )

        AppLogger.runtime().log(event: "service:streamResponse:adapterCompleted", data: [:])
    }
}
