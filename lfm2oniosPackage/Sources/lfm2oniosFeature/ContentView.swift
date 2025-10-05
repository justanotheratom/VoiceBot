import SwiftUI

enum MicrophonePermissionState: Equatable {
    case granted
    case denied
    case undetermined
}

@available(iOS 18.0, macOS 13.0, *)
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
                    }, onSelectModel: { model in
                        selected = model
                    }, onDeleteModel: { entry in
                        do {
                            try storage.deleteDownloadedModel(entry: entry)
                            if let current = selected, current.slug == entry.slug {
                                // Clear selection if we deleted the active model
                                persistence.clearSelectedModel()
                                selected = nil
                            }
                        } catch {
                            AppLogger.download().logError(event: "deleteFailed", error: error, data: ["modelSlug": entry.slug])
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
                            localURL: localURL,
                            runtime: entry.runtime,
                            runtimeIdentifier: entry.gemmaMetadata?.assetIdentifier
                        )
                        persistence.saveSelectedModel(model)
                        selected = model
                    } onDelete: { entry in
                        do {
                            try storage.deleteDownloadedModel(entry: entry)
                            if let current = selected, current.slug == entry.slug {
                                // Clear selection if we deleted the active model
                                persistence.clearSelectedModel()
                                selected = nil
                            }
                        } catch {
                            AppLogger.download().logError(event: "deleteFailed", error: error, data: ["modelSlug": entry.slug])
                        }
                    } onCancel: {
                        if let prev = previousSelected {
                            selected = prev
                            persistence.saveSelectedModel(prev)
                            previousSelected = nil
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

@available(iOS 18.0, macOS 13.0, *)
@MainActor
struct ChatView: View {
    let selected: SelectedModel
    let onSwitch: () -> Void
    let onSelectModel: (SelectedModel) -> Void
    let onDeleteModel: (ModelCatalogEntry) -> Void
    let persistence: PersistenceService

    @State private var runtime = ModelRuntimeService()
    @State private var voiceInputStore = VoiceInputStore()
    @State private var conversationStore: ConversationStore?
    @State private var messages: [Message] = []
    @State private var isStreaming: Bool = false
    @State private var userRequestedStop: Bool = false
    @State private var didAutoSend: Bool = false
    @State private var showSettings = false
    @State private var streamingTask: Task<Void, Never>?
    @State private var shouldScrollToBottom = false
    @State private var currentPairIndex = 0
    @State private var scrollTimer: Timer?
    @State private var showingConversationHistory = false
    private let storage = ModelStorageService()
    private let contextManager = ContextWindowManager()
    
    @ViewBuilder
    private var emptyStateView: some View {
        EmptyStateView(onSuggestionTap: sendTranscript)
    }
    
    @ViewBuilder
    private var messagesView: some View {
        TabView(selection: $currentPairIndex) {
            ForEach(Array(messagePairs.enumerated()), id: \.offset) { pairIndex, pair in
                VStack(spacing: 0) {
                    // Pinned user message at top
                    if let userMessage = pair.first(where: { $0.role == .user }) {
                        VStack(spacing: 12) {
                            ChatMessageView(message: userMessage, isStreaming: false)
                                .accessibilityIdentifier("message_\(userMessage.id.uuidString)")
                            Divider()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .background(Color(uiColor: .systemBackground))
                    }

                    // Scrollable assistant response
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(pair.filter { $0.role == .assistant }, id: \.id) { msg in
                                ChatMessageView(message: msg, isStreaming: isStreaming && msg.id == messages.last?.id)
                                    .accessibilityIdentifier("message_\(msg.id.uuidString)")
                                    .id(msg.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                }
                .tag(pairIndex)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.smooth(duration: 0.4), value: currentPairIndex)
        .onChange(of: messages.count) { oldCount, newCount in
            // Smooth transition to latest pair when new message is added
            withAnimation(.smooth(duration: 0.4)) {
                currentPairIndex = messagePairs.count - 1
            }
        }
        .onAppear {
            // Start at the latest pair
            currentPairIndex = max(0, messagePairs.count - 1)
        }
    }

    private var messagePairs: [[Message]] {
        var pairs: [[Message]] = []
        var i = 0

        while i < messages.count {
            let msg = messages[i]

            if msg.role == .user {
                // Check if there's an assistant response
                if i + 1 < messages.count && messages[i + 1].role == .assistant {
                    pairs.append([msg, messages[i + 1]])
                    i += 2
                } else {
                    // User message without response (likely streaming)
                    pairs.append([msg])
                    i += 1
                }
            } else {
                // Standalone assistant message (shouldn't happen normally)
                pairs.append([msg])
                i += 1
            }
        }

        return pairs.isEmpty ? [] : pairs
    }

    private var latestMessagePair: [Message] {
        messagePairs.last ?? []
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if messages.isEmpty {
                    emptyStateView
                } else {
                    messagesView
                }
            }
            VStack(spacing: 0) {
                Spacer()
                VoiceInputBar(
                    controller: voiceInputStore,
                    isStreaming: isStreaming,
                    modelSlug: selected.slug,
                    onSendText: sendTranscript,
                    onStopStreaming: { stopStreaming(userInitiated: true) },
                    onVoiceTranscript: sendTranscript
                )
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
                    Text("\(selected.provider) • \(selected.runtime.displayName)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
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
                    if isStreaming {
                        // Clear messages immediately for instant visual feedback
                        messages.removeAll()
                        // Cancel the streaming task to stop further updates
                        stopStreaming(userInitiated: false)
                        // Fully reload the model to ensure clean state after cancellation
                        Task {
                            if let currentURL = await runtime.currentModelURL {
                                await runtime.unloadModel()
                                if let entry = ModelCatalog.entry(forSlug: selected.slug) {
                                    try? await runtime.loadModel(entry: entry, at: currentURL)
                                }
                            }
                        }
                    } else {
                        // If not streaming, clear immediately as before
                        messages.removeAll()
                    }

                    // Start a new conversation
                    conversationStore?.startNewConversation(modelSlug: selected.slug)
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
                        let model = SelectedModel(
                            slug: entry.slug,
                            displayName: entry.displayName,
                            provider: entry.provider,
                            quantizationSlug: entry.quantizationSlug,
                            localURL: url,
                            runtime: entry.runtime,
                            runtimeIdentifier: entry.gemmaMetadata?.assetIdentifier
                        )
                        persistence.saveSelectedModel(model)
                        onSelectModel(model)
                        // Don't manually unload - ModelRuntimeService.loadModel handles it
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
            }
        }
        .task {
            await voiceInputStore.prefetchPermissionsIfNeeded()
        }
        .task(id: selected.slug) {
            // Load the model when selection changes
            do {
                guard let entry = ModelCatalog.entry(forSlug: selected.slug) else {
                    AppLogger.ui().log(event: "task:noCatalogEntry", data: ["slug": selected.slug], level: .error)
                    messages.append(Message(role: .assistant, text: "⚠️ No catalog entry found for \(selected.slug). Please select a different model."))
                    return
                }
                let isDownloaded = storage.isDownloaded(entry: entry)

                let urlToLoad: URL
                if isDownloaded {
                    // Always use the current expected URL for downloaded models to avoid container UUID mismatches
                    do {
                        urlToLoad = try storage.expectedResourceURL(for: entry)
                    } catch {
                        AppLogger.storage().logError(event: "expectedURLFailed", error: error, data: [
                            "modelSlug": entry.slug
                        ])
                        messages.append(Message(role: .assistant, text: "⚠️ Failed to locate model files for \(selected.slug). Please try downloading the model again."))
                        return
                    }
                } else if let persistedURL = selected.localURL {
                    // Use the persisted URL only if the model is not showing as downloaded
                    urlToLoad = persistedURL
                } else {
                    AppLogger.runtime().log(event: "load:failed", data: [
                        "slug": selected.slug,
                        "reason": "missingURL"
                    ], level: .error)
                    messages.append(Message(role: .assistant, text: "⚠️ Model \(selected.slug) is not downloaded. Please download it first."))
                    return
                }

                AppLogger.runtime().log(event: "load:attempting", data: [
                    "slug": selected.slug,
                    "url": urlToLoad.path,
                    "urlExists": FileManager.default.fileExists(atPath: urlToLoad.path)
                ])
                try await runtime.loadModel(entry: entry, at: urlToLoad)
                AppLogger.runtime().log(event: "load:success", data: ["slug": selected.slug])

                // Initialize conversation store after successful model load
                conversationStore = ConversationStore(modelRuntimeService: runtime)
                conversationStore?.startNewConversation(modelSlug: selected.slug)
            } catch {
                AppLogger.runtime().logError(event: "load:failed", error: error, data: ["slug": selected.slug])
                // Show error to user - no fallback to simulation
                messages.append(Message(role: .assistant, text: "⚠️ Failed to load model: \(error.localizedDescription)"))
            }
            
            // Auto-send for automation when flag is present
            let args = ProcessInfo.processInfo.arguments
            if let idx = args.firstIndex(of: "--ui-test-autosend"), args.indices.contains(idx + 1), didAutoSend == false {
                didAutoSend = true
                let prompt = args[idx + 1]
                await MainActor.run {
                    sendTranscript(prompt)
                }
            }
        }
    }

    private func stopStreaming(userInitiated: Bool) {
        userRequestedStop = userInitiated

        // Cancel the task but don't nil it out - let it finish cleanup naturally
        streamingTask?.cancel()

        scrollTimer?.invalidate()
        scrollTimer = nil

        // Don't set isStreaming here - let the task cleanup handle it
        // to avoid race conditions
    }

    private func sendTranscript(_ rawPrompt: String) {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        // CRITICAL: Cancel and wait for previous streaming task to fully complete
        // before starting a new one to avoid race conditions
        if let existingTask = streamingTask {
            existingTask.cancel()

            // Start the new message in a task that waits for cleanup
            Task { @MainActor in
                // Wait for the old task to finish its cleanup
                await existingTask.value

                // Now safe to proceed
                startNewMessage(prompt: prompt)
            }
            return
        }

        startNewMessage(prompt: prompt)
    }

    private func startNewMessage(prompt: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            messages.append(Message(role: .user, text: prompt))
            messages.append(Message(role: .assistant, text: ""))
        }

        // Add user message to conversation manager
        conversationStore?.addUserMessage(prompt)

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
        let tokenBudget = contextManager.responseTokenBudget(for: selected.slug)

        streamingTask = Task { @MainActor in
            let startTime = Date()
            var firstTokenTime: Date?
            var tokenCount = 0

            do {
                let llmMessages = conversationStore?.getMessagesForLLM() ?? []

                try await runtime.streamResponse(
                    prompt: prompt,
                    conversation: llmMessages,
                    tokenLimit: tokenBudget
                ) { token in
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
                if !Task.isCancelled, assistantIndex < messages.count {
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
                        await conversationStore?.addAssistantMessage(assistantResponse)
                    }
                    userRequestedStop = false
                }
            } catch is CancellationError {

                if assistantIndex < messages.count {
                    let partialResponse = messages[assistantIndex].text
                    if !partialResponse.isEmpty, userRequestedStop {
                        Task { @MainActor in
                            await conversationStore?.addAssistantMessage(partialResponse)
                        }
                    }
                }
                userRequestedStop = false
            } catch {
                AppLogger.runtime().logError(event: "stream:failed", error: error)
                // Only update if messages still exist and index is valid
                if assistantIndex < messages.count {
                    messages[assistantIndex].text = "❌ Error generating response: \(error.localizedDescription)\n\nPlease ensure the model is properly downloaded and loaded."
                }
            }

            // CRITICAL: Always reset streaming state, even if task was cancelled early
            // This must run regardless of early returns above
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
        conversationStore?.loadConversation(conversation)
        
        // Convert ChatMessageModel to UI Message format and display
        let conversationMessages = conversationStore?.getAllMessagesForDisplay() ?? []
        messages = conversationMessages.compactMap { chatMessage in
            switch chatMessage.role {
            case .user:
                return Message(role: .user, text: chatMessage.content)
            case .assistant:
                return Message(role: .assistant, text: chatMessage.content)
            case .system:
                return nil
            }
        }
    }
}

// MARK: - Chat models

public struct TokenStats: Equatable, Sendable {
    public let tokens: Int
    public let timeToFirstToken: TimeInterval?
    public let tokensPerSecond: Double?

    public init(tokens: Int, timeToFirstToken: TimeInterval? = nil, tokensPerSecond: Double? = nil) {
        self.tokens = tokens
        self.timeToFirstToken = timeToFirstToken
        self.tokensPerSecond = tokensPerSecond
    }
}

public struct Message: Identifiable, Equatable, Sendable {
    public enum Role: String, Sendable { case user, assistant }
    public let id: UUID
    public let role: Role
    public var text: String
    public var stats: TokenStats?

    public init(id: UUID = UUID(), role: Role, text: String, stats: TokenStats? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.stats = stats
    }
}

// MARK: - Helper Views
// Note: ChatMessageView, SuggestionPill, and EmptyStateView are now in UIComponents/
