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
    @State private var streamingTask: Task<Void, Never>?
    private let storage = ModelStorageService()
    
    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
    }

    var body: some View {
        VStack(spacing: 0) {
            if messages.isEmpty {
                // Enhanced empty state with visual interest
                VStack(spacing: 20) {
                    Spacer()
                    
                    // AI Assistant Icon with animation
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue.gradient)
                        .symbolEffect(.pulse.wholeSymbol, options: .repeating.speed(0.5))
                    
                    VStack(spacing: 8) {
                        Text("Ready to Chat")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        
                        Text("Ask me anything or start a conversation")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Suggestion pills
                    VStack(spacing: 12) {
                        Text("Try asking:")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 8) {
                            SuggestionPill(text: "Explain a concept") {
                                input = "Can you explain quantum computing in simple terms?"
                            }
                            SuggestionPill(text: "Write code") {
                                input = "Write a SwiftUI view that displays a list"
                            }
                            SuggestionPill(text: "Creative writing") {
                                input = "Write a short story about space exploration"
                            }
                            SuggestionPill(text: "Problem solving") {
                                input = "Help me debug this Swift code"
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                }
                .padding()
            } else {
                List(messages) { msg in
                    ChatMessageView(message: msg)
                        .accessibilityIdentifier("message_\(msg.id.uuidString)")
                }
                .listStyle(.plain)
                .scrollDismissesKeyboard(.interactively)
            }

            // Enhanced input area with modern design
            VStack(spacing: 0) {
                Divider()
                
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        TextField("Type your message...", text: $input, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(1...4)
                            .disabled(isStreaming)
                        
                        if isStreaming {
                            ProgressView()
                                .scaleEffect(0.8)
                                .accessibilityIdentifier("typingIndicator")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    
                    Button(action: { send() }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(canSend ? .blue : .secondary)
                            .symbolEffect(.bounce, value: input)
                    }
                    .disabled(!canSend)
                    .accessibilityLabel("Send message")
                    .accessibilityIdentifier("sendButton")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .background(.regularMaterial)
            }
        }
        .navigationTitle("Chat")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "brain.head.profile")
                            .foregroundStyle(.blue)
                            .font(.caption)
                        Text("Chat")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    Text(selected.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showSettings = true }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.body)
                        .foregroundStyle(.blue)
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("settingsButton")
            }
            ToolbarItem(placement: .topBarLeading) {
                Button(action: { 
                    print("DEBUG: + button tapped, clearing \(messages.count) messages")
                    
                    if isStreaming {
                        // Clear messages immediately for instant visual feedback
                        messages.removeAll()
                        // Cancel the streaming task to stop further updates
                        streamingTask?.cancel()
                        streamingTask = nil
                        isStreaming = false
                        // Fully reload the model to ensure clean state after cancellation
                        Task {
                            if let currentURL = await runtime.currentModelURL {
                                print("DEBUG: Reloading model after streaming cancellation")
                                await runtime.unloadModel()
                                try? await runtime.loadModel(at: currentURL)
                            }
                        }
                        print("DEBUG: Messages cleared immediately during streaming, model will be reloaded")
                    } else {
                        // If not streaming, clear immediately as before
                        messages.removeAll()
                        print("DEBUG: Messages cleared immediately, now \(messages.count) messages")
                    }
                }) {
                    Image(systemName: "plus.message")
                        .font(.body)
                        .foregroundStyle(messages.isEmpty ? Color.secondary : Color.blue)
                }
                .disabled(messages.isEmpty)
                .accessibilityLabel("New Chat")
                .accessibilityIdentifier("newChatButton")
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
                    #if os(iOS)
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            showSettings = false
                        }
                    }
                    #else
                    ToolbarItem(placement: .primaryAction) {
                        Button("Done") {
                            showSettings = false
                        }
                    }
                    #endif
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
        
        withAnimation(.easeInOut(duration: 0.2)) {
            input = ""
            messages.append(Message(role: .user, text: prompt))
            messages.append(Message(role: .assistant, text: ""))
        }
        
        let assistantIndex = messages.count - 1
        isStreaming = true

        // Store and cancel any previous streaming task
        streamingTask?.cancel()
        streamingTask = Task { @MainActor in
            let startTime = Date()
            var firstTokenTime: Date?
            var tokenCount = 0
            
            do {
                try await runtime.streamResponse(prompt: prompt) { token in
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
                guard !Task.isCancelled, assistantIndex < messages.count else {
                    return
                }
                
                // Calculate statistics
                let endTime = Date()
                let totalTime = endTime.timeIntervalSince(startTime)
                let timeToFirstToken = firstTokenTime?.timeIntervalSince(startTime)
                let tokensPerSecond = tokenCount > 0 && totalTime > 0 ? Double(tokenCount) / totalTime : nil
                
                // Update message with stats
                messages[assistantIndex].stats = TokenStats(
                    tokens: tokenCount,
                    timeToFirstToken: timeToFirstToken,
                    tokensPerSecond: tokensPerSecond
                )
                
                print("runtime: { event: \"stream:userComplete\", prompt: \"\(prompt.prefix(50))...\", tokens: \(tokenCount), ttft: \(timeToFirstToken ?? 0), tps: \(tokensPerSecond ?? 0) }")
            } catch is CancellationError {
                print("runtime: { event: \"stream:cancelled\" }")
            } catch {
                print("runtime: { event: \"stream:failed\", error: \"\(String(describing: error))\" }")
                // Only update if messages still exist and index is valid
                if assistantIndex < messages.count {
                    messages[assistantIndex].text = "❌ Error generating response: \(error.localizedDescription)\n\nPlease ensure the model is properly downloaded and loaded."
                }
            }
            
            // Always reset streaming state, even if task was cancelled
            isStreaming = false
            streamingTask = nil
        }
    }
}

// MARK: - Chat models

struct TokenStats: Equatable, Sendable {
    let tokens: Int
    let timeToFirstToken: TimeInterval?
    let tokensPerSecond: Double?
    
    init(tokens: Int, timeToFirstToken: TimeInterval? = nil, tokensPerSecond: Double? = nil) {
        self.tokens = tokens
        self.timeToFirstToken = timeToFirstToken
        self.tokensPerSecond = tokensPerSecond
    }
}

struct Message: Identifiable, Equatable, Sendable {
    enum Role: String, Sendable { case user, assistant }
    let id: UUID
    let role: Role
    var text: String
    var stats: TokenStats?

    init(id: UUID = UUID(), role: Role, text: String, stats: TokenStats? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.stats = stats
    }
}

// MARK: - Helper Views

struct SuggestionPill: View {
    let text: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.caption)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct ChatMessageView: View {
    let message: Message
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                // User/Assistant avatar
                Group {
                    if message.role == .user {
                        Image(systemName: "person.circle.fill")
                            .foregroundStyle(.blue)
                    } else {
                        Image(systemName: "brain.head.profile")
                            .foregroundStyle(.green)
                    }
                }
                .font(.title3)
                .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(message.role == .user ? "You" : "Assistant")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    
                    Text(message.text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            
            // Performance stats for assistant messages
            if message.role == .assistant, let stats = message.stats {
                HStack {
                    Spacer()
                        .frame(width: 36)
                    HStack(spacing: 8) {
                        Label("\(stats.tokens)", systemImage: "number")
                        if let ttft = stats.timeToFirstToken {
                            Label("\(String(format: "%.2f", ttft))s", systemImage: "timer")
                        }
                        if let tps = stats.tokensPerSecond {
                            Label("\(String(format: "%.1f", tps))", systemImage: "speedometer")
                        }
                    }
                    .labelStyle(.titleAndIcon)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
    }
}
