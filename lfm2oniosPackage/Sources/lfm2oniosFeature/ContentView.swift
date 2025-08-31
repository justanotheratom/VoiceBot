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
    @State private var conversationManager: ConversationManager?
    @State private var messages: [Message] = []
    @State private var input: String = ""
    @State private var isStreaming: Bool = false
    @State private var didAutoSend: Bool = false
    @State private var showSettings = false
    @State private var streamingTask: Task<Void, Never>?
    @State private var shouldScrollToBottom = false
    @State private var scrollTimer: Timer?
    @State private var showingConversationHistory = false
    private let storage = ModelStorageService()
    
    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
    }
    
    @ViewBuilder
    private var emptyStateView: some View {
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
            
            suggestionPillsView
            
            Spacer()
        }
        .padding()
    }
    
    @ViewBuilder
    private var suggestionPillsView: some View {
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
    }
    
    @ViewBuilder
    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, msg in
                        VStack(spacing: 12) {
                            ChatMessageView(message: msg, isStreaming: isStreaming && msg.id == messages.last?.id)
                                .accessibilityIdentifier("message_\(msg.id.uuidString)")
                            
                            // Add separator after user messages (before assistant response)
                            if msg.role == .user && index < messages.count - 1 {
                                Divider()
                            }
                        }
                        .id(msg.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                // Scroll to bottom when new message is added
                withAnimation(.easeInOut(duration: 0.3)) {
                    if let lastMessage = messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: shouldScrollToBottom) { _, shouldScroll in
                // Scroll to bottom during streaming with smooth spring animation
                if shouldScroll, let lastMessage = messages.last {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                    shouldScrollToBottom = false
                }
            }
        }
    }
    
    @ViewBuilder
    private var inputBarView: some View {
        VStack(spacing: 0) {
            // Subtle top border
            Rectangle()
                .fill(.separator.opacity(0.3))
                .frame(height: 0.5)
            
            VStack(spacing: 12) {
                HStack(alignment: .bottom, spacing: 12) {
                    inputFieldView
                    sendButtonView
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background {
                inputBarBackground
            }
        }
    }
    
    @ViewBuilder
    private var inputFieldView: some View {
        HStack(spacing: 12) {
            TextField("Type your message...", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .disabled(isStreaming)
                .font(.body)
            
            if isStreaming {
                ProgressView()
                    .scaleEffect(0.8)
                    .accessibilityIdentifier("typingIndicator")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(.quaternary.opacity(0.5))
                .stroke(.separator.opacity(0.3), lineWidth: 1)
        }
    }
    
    @ViewBuilder
    private var sendButtonView: some View {
        Button(action: { send() }) {
            Image(systemName: canSend ? "arrow.up.circle.fill" : "circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(canSend ? .blue : .secondary)
                .symbolEffect(.bounce, value: input)
                .background {
                    Circle()
                        .fill(.background)
                        .stroke(.separator.opacity(0.2), lineWidth: canSend ? 0 : 1)
                }
        }
        .disabled(!canSend)
        .accessibilityLabel("Send message")
        .accessibilityIdentifier("sendButton")
        .animation(.easeInOut(duration: 0.2), value: canSend)
    }
    
    @ViewBuilder
    private var inputBarBackground: some View {
        Rectangle()
            .fill(.regularMaterial)
            .background {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            if messages.isEmpty {
                emptyStateView
            } else {
                messagesView
            }
            inputBarView
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
                HStack(spacing: 16) {
                    #if DEBUG
                    Button(action: { 
                        Task { @MainActor in
                            await UITestDataCreator.createTestConversations()
                        }
                    }) {
                        Image(systemName: "testtube.2")
                            .font(.body)
                            .foregroundStyle(.orange)
                    }
                    .accessibilityLabel("Create Test Data")
                    .accessibilityIdentifier("createTestDataButton")
                    #endif
                    
                    Button(action: { showingConversationHistory = true }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.body)
                            .foregroundStyle(.blue)
                    }
                    .accessibilityLabel("Conversation History")
                    .accessibilityIdentifier("historyButton")
                    
                    Button(action: { showSettings = true }) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.body)
                            .foregroundStyle(.blue)
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("settingsButton")
                }
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
                    
                    // Start a new conversation
                    conversationManager?.startNewConversation(modelSlug: selected.slug)
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
        .sheet(isPresented: $showingConversationHistory) {
            ConversationListView { conversation in
                loadConversation(conversation)
                showingConversationHistory = false
                print("ui: { event: \"conversationSelected\", id: \"\(conversation.id)\", title: \"\(conversation.title)\" }")
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
                
                // Initialize conversation manager after successful model load
                conversationManager = ConversationManager(modelRuntimeService: runtime)
                conversationManager?.startNewConversation(modelSlug: selected.slug)
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
        
        // Add user message to conversation manager
        conversationManager?.addUserMessage(prompt)
        
        let assistantIndex = messages.count - 1
        isStreaming = true

        // Start smooth scroll timer during streaming
        scrollTimer?.invalidate()
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                if isStreaming {
                    shouldScrollToBottom = true
                }
            }
        }

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
                
                // Add assistant response to conversation manager
                let assistantResponse = messages[assistantIndex].text
                Task { @MainActor in
                    await conversationManager?.addAssistantMessage(assistantResponse)
                }
                
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
            scrollTimer?.invalidate()
            scrollTimer = nil
            isStreaming = false
            streamingTask = nil
        }
    }
    
    private func loadConversation(_ conversation: ChatConversation) {
        // Clear current messages
        messages.removeAll()
        
        // Load conversation in manager
        conversationManager?.loadConversation(conversation)
        
        // Convert ChatMessageModel to UI Message format and display
        let conversationMessages = conversationManager?.getAllMessagesForDisplay() ?? []
        messages = conversationMessages.map { chatMessage in
            Message(role: chatMessage.role == .user ? .user : .assistant, text: chatMessage.content)
        }
        
        print("ui: { event: \"conversationLoaded\", id: \"\(conversation.id)\", messageCount: \(messages.count) }")
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
    let isStreaming: Bool
    
    init(message: Message, isStreaming: Bool = false) {
        self.message = message
        self.isStreaming = isStreaming
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // Avatar
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
                .frame(width: 28, height: 28)
                
                VStack(alignment: .leading, spacing: 6) {
                    // Role label
                    Text(message.role == .user ? "You" : "Assistant")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)
                    
                    // Message content
                    Text(message.text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Streaming indicator for assistant messages
                    if message.role == .assistant && isStreaming {
                        HStack(spacing: 8) {
                            HStack(spacing: 3) {
                                ForEach(0..<3) { index in
                                    Circle()
                                        .fill(.secondary)
                                        .frame(width: 5, height: 5)
                                        .opacity(0.4)
                                        .animation(
                                            .easeInOut(duration: 0.6)
                                            .repeatForever(autoreverses: true)
                                            .delay(Double(index) * 0.15),
                                            value: isStreaming
                                        )
                                        .scaleEffect(isStreaming ? 1.3 : 1.0)
                                }
                            }
                            
                            Text("Assistant is typing...")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
            }
            
            // Performance stats for assistant messages
            if message.role == .assistant, let stats = message.stats {
                HStack {
                    Spacer()
                        .frame(width: 40)
                    HStack(spacing: 12) {
                        Label("\(stats.tokens) tokens", systemImage: "number.circle")
                        if let ttft = stats.timeToFirstToken {
                            Label("\(String(format: "%.2f", ttft))s", systemImage: "clock")
                        }
                        if let tps = stats.tokensPerSecond {
                            Label("\(String(format: "%.1f", tps))/s", systemImage: "speedometer")
                        }
                    }
                    .labelStyle(.titleAndIcon)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    Spacer()
                }
            }
        }
    }
}
