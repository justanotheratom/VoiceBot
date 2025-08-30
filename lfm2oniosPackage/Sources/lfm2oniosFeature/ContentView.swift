import SwiftUI

@available(iOS 17.0, macOS 13.0, *)
@MainActor
public struct ContentView: View {
    @State private var persistence = PersistenceService()
    @State private var selected: SelectedModel? = nil
    @State private var previousSelected: SelectedModel? = nil
    private let storage = ModelStorageService()

    public init() {
        let p = PersistenceService()
        _persistence = State(initialValue: p)
        _selected = State(initialValue: p.loadSelectedModel())
    }

    public var body: some View {
        NavigationStack {
            Group {
                if let current = selected, current.localURL != nil {
                    ChatView(selected: current, onSwitch: {
                        previousSelected = current
                        persistence.clearSelectedModel()
                        selected = nil
                        print("ui: { event: \"switchModel\" }")
                    }, onSelectModel: { model in
                        selected = model
                        print("ui: { event: \"modelSelected\", modelSlug: \"\(model.slug)\" }")
                    }, onDeleteModel: { entry in
                        do {
                            try storage.deleteDownloadedModel(entry: entry)
                            print("download: { event: \"deleted\", modelSlug: \"\(entry.slug)\" }")
                            if let current = selected, current.slug == entry.slug {
                                // Clear selection if we deleted the active model
                                persistence.clearSelectedModel()
                                selected = nil
                            }
                        } catch {
                            print("download: { event: \"deleteFailed\", error: \"\(String(describing: error))\" }")
                        }
                    }, persistence: persistence)
                } else {
                    ModelSelectionView { entry, localURL in
                        // Persist with localURL when inline download completes
                        let model = SelectedModel(
                            slug: entry.slug,
                            displayName: entry.displayName,
                            provider: entry.provider,
                            quantizationSlug: entry.quantizationSlug,
                            localURL: localURL
                        )
                        persistence.saveSelectedModel(model)
                        selected = model
                        print("ui: { event: \"select:completed\", modelSlug: \"\(entry.slug)\" }")
                    } onDelete: { entry in
                        do {
                            try storage.deleteDownloadedModel(entry: entry)
                            print("download: { event: \"deleted\", modelSlug: \"\(entry.slug)\" }")
                            if let current = selected, current.slug == entry.slug {
                                // Clear selection if we deleted the active model
                                persistence.clearSelectedModel()
                                selected = nil
                            }
                        } catch {
                            print("download: { event: \"deleteFailed\", error: \"\(String(describing: error))\" }")
                        }
                    } onCancel: {
                        if let prev = previousSelected {
                            selected = prev
                            persistence.saveSelectedModel(prev)
                            previousSelected = nil
                            print("ui: { event: \"select:cancelled\" }")
                        }
                    }
                }
            }
            .task {
                // Ensure selection is up to date on appear as well
                selected = persistence.loadSelectedModel()
            }
        }
    }
}

@available(iOS 17.0, macOS 13.0, *)
@MainActor
struct ChatView: View {
    let selected: SelectedModel
    let onSwitch: () -> Void
    let onSelectModel: (SelectedModel) -> Void
    let onDeleteModel: (ModelCatalogEntry) -> Void
    let persistence: PersistenceService

    @State private var runtime = ModelRuntimeService()
    @State private var messages: [Message] = []
    @State private var input: String = ""
    @State private var isStreaming: Bool = false
    @State private var didAutoSend: Bool = false
    @State private var showSettings = false
    private let storage = ModelStorageService()

    var body: some View {
        VStack(spacing: 0) {
            List(messages) { msg in
                HStack(alignment: .top) {
                    Text(msg.role == .user ? "You" : "Assistant")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .leading)
                    Text(msg.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("message_\(msg.id.uuidString)")
            }
            .listStyle(.plain)

            HStack(spacing: 8) {
                TextField("Message", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("chatInputField")
                    .disabled(isStreaming)

                if isStreaming {
                    ProgressView()
                        .accessibilityIdentifier("typingIndicator")
                }

                Button("Send") { send() }
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isStreaming)
                    .accessibilityIdentifier("sendButton")
            }
            .padding()
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("Chat")
                        .font(.headline)
                    Text(selected.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showSettings = true }) {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityIdentifier("settingsButton")
            }
            ToolbarItem(placement: .topBarLeading) {
                Button(action: { 
                    print("ui: { event: \"clearAndRestart\" }")
                    messages.removeAll()
                }) {
                    Image(systemName: "plus.message")
                }
                .accessibilityIdentifier("newConversationButton")
            }
            #endif
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView(
                    currentModel: selected,
                    onSelectModel: { entry, url in
                        showSettings = false
                        Task {
                            await runtime.unloadModel()
                        }
                        let model = SelectedModel(
                            slug: entry.slug,
                            displayName: entry.displayName,
                            provider: entry.provider,
                            quantizationSlug: entry.quantizationSlug,
                            localURL: url
                        )
                        persistence.saveSelectedModel(model)
                        onSelectModel(model)
                        print("ui: { event: \"settings:modelSelected\", modelSlug: \"\(entry.slug)\" }")
                    },
                    onDeleteModel: onDeleteModel,
                    persistence: persistence
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            showSettings = false
                        }
                    }
                }
            }
        }
        .task(id: selected.slug) {
            // Load the model when selection changes
            print("ui: { event: \"task:modelLoad\", slug: \"\(selected.slug)\", selectedLocalURL: \"\(selected.localURL?.path ?? "nil")\" }")
            
            do {
                print("ui: { event: \"task:initialURL\", selectedLocalURL: \"\(selected.localURL?.path ?? "nil")\" }")
                
                guard let entry = ModelCatalog.entry(forSlug: selected.slug) else {
                    print("ui: { event: \"task:noCatalogEntry\", slug: \"\(selected.slug)\" }")
                    messages.append(Message(role: .assistant, text: "⚠️ No catalog entry found for \(selected.slug). Please select a different model."))
                    return
                }
                
                print("ui: { event: \"task:foundCatalogEntry\", slug: \"\(selected.slug)\", quantization: \"\(entry.quantizationSlug ?? "none")\" }")
                let isDownloaded = storage.isDownloaded(entry: entry)
                print("ui: { event: \"task:downloadCheck\", isDownloaded: \(isDownloaded) }")
                
                let urlToLoad: URL
                if isDownloaded {
                    // Always use the current expected URL for downloaded models to avoid container UUID mismatches
                    do {
                        urlToLoad = try storage.expectedBundleURL(for: entry)
                        print("ui: { event: \"task:usingExpectedURL\", url: \"\(urlToLoad.path)\" }")
                    } catch {
                        print("ui: { event: \"task:expectedURLFailed\", error: \"\(String(describing: error))\" }")
                        messages.append(Message(role: .assistant, text: "⚠️ Failed to locate model files for \(selected.slug). Please try downloading the model again."))
                        return
                    }
                } else if let persistedURL = selected.localURL {
                    // Use the persisted URL only if the model is not showing as downloaded
                    print("ui: { event: \"task:usingPersistedURL\", url: \"\(persistedURL.path)\" }")
                    urlToLoad = persistedURL
                } else {
                    print("runtime: { event: \"load:failed\", error: \"noURL\", slug: \"\(selected.slug)\", isDownloaded: false, selectedLocalURL: \"nil\" }")
                    messages.append(Message(role: .assistant, text: "⚠️ Model \(selected.slug) is not downloaded. Please download it first."))
                    return
                }
                
                print("runtime: { event: \"load:attempting\", slug: \"\(selected.slug)\", url: \"\(urlToLoad.path)\", urlExists: \(FileManager.default.fileExists(atPath: urlToLoad.path)) }")
                try await runtime.loadModel(at: urlToLoad)
                print("runtime: { event: \"load:success\", slug: \"\(selected.slug)\" }")
            } catch {
                print("runtime: { event: \"load:failed\", slug: \"\(selected.slug)\", error: \"\(String(describing: error))\", errorType: \"\(type(of: error))\" }")
                // Show error to user - no fallback to simulation
                messages.append(Message(role: .assistant, text: "⚠️ Failed to load model: \(error.localizedDescription)"))
            }
            
            // Auto-send for automation when flag is present
            let args = ProcessInfo.processInfo.arguments
            if let idx = args.firstIndex(of: "--ui-test-autosend"), args.indices.contains(idx + 1), didAutoSend == false {
                didAutoSend = true
                let prompt = args[idx + 1]
                await MainActor.run {
                    input = prompt
                    send()
                }
            }
        }
    }

    private func send() {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        input = ""
        messages.append(Message(role: .user, text: prompt))
        messages.append(Message(role: .assistant, text: ""))
        let assistantIndex = messages.count - 1
        isStreaming = true

        Task { @MainActor in
            do {
                try await runtime.streamResponse(prompt: prompt) { token in
                    await MainActor.run {
                        messages[assistantIndex].text += token
                    }
                }
                print("runtime: { event: \"stream:userComplete\", prompt: \"\(prompt.prefix(50))...\" }")
            } catch {
                print("runtime: { event: \"stream:failed\", error: \"\(String(describing: error))\" }")
                messages[assistantIndex].text = "❌ Error generating response: \(error.localizedDescription)\n\nPlease ensure the model is properly downloaded and loaded."
            }
            isStreaming = false
        }
    }
}

// MARK: - Chat models

struct Message: Identifiable, Equatable, Sendable {
    enum Role: String, Sendable { case user, assistant }
    let id: UUID
    let role: Role
    var text: String

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}
