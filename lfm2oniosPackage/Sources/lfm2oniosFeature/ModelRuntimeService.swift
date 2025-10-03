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
            print("runtime: { event: \"preload:error\", slug: \"\(entry.slug)\", reason: \"adapterMissing\" }")
            throw ModelRuntimeError.notLoaded
        }

        try await currentAdapter.loadModel(at: url, entry: entry)
        loadedURL = url
        currentEntryID = entry.id

        print("runtime: { event: \"preload:start\", slug: \"\(entry.slug)\" }")
        do {
            try await currentAdapter.preload()
            print("runtime: { event: \"preload:complete\", slug: \"\(entry.slug)\" }")
        } catch {
            print("runtime: { event: \"preload:failed\", slug: \"\(entry.slug)\", error: \"\(error.localizedDescription)\" }")
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
        await adapter?.resetConversation()
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
        guard let adapter else {
            print("runtime: { event: \"stream:error\", reason: \"noModelLoaded\" }")
            throw ModelRuntimeError.notLoaded
        }

        try await adapter.streamResponse(
            prompt: prompt,
            conversation: conversation,
            tokenLimit: tokenLimit,
            onToken: onToken
        )
    }
}
