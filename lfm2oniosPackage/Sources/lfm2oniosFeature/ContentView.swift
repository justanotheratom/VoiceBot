import SwiftUI
#if os(iOS)
import AVFoundation
import AVFAudio
#endif

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

    private enum SpeechPermissionState: Equatable { case unknown, granted, denied }

    @State private var runtime = ModelRuntimeService()
    @State private var speechService = SpeechRecognitionService()
    @State private var conversationManager: ConversationManager?
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
    @State private var isRecording = false
    @State private var isRequestingSpeechPermission = false
    @State private var isTranscribingSpeech = false
    @State private var microphoneErrorMessage: String?
    @State private var errorDismissTask: Task<Void, Never>?
    @State private var speechPermissionState: SpeechPermissionState = .unknown
    @State private var recordingStartTime: Date? = nil
    @State private var hasPrefetchedSpeechPermission = false
#if os(iOS)
    @State private var isRequestingRecordPermission = false
    @State private var recordPermission: MicrophonePermissionState = .undetermined
#else
    @State private var isRequestingRecordPermission = false
    @State private var recordPermission: MicrophonePermissionState = .granted
#endif
    private let storage = ModelStorageService()
    private let contextManager = ContextWindowManager()
    
    private var microphoneStatus: MicrophoneInputBar.Status {
        if let message = microphoneErrorMessage {
            return .error(message: message)
        }
        if isTranscribingSpeech {
            return .transcribing
        }
        if isRecording {
            return .recording
        }
        let requestingPermission = isRequestingSpeechPermission || isRequestingRecordPermission
        if requestingPermission {
            return .requestingPermission
        }
        if recordPermission == .denied {
            return .disabled(message: "Enable microphone access in Settings")
        }
        switch speechPermissionState {
        case .denied:
            return .disabled(message: "Enable microphone & speech access in Settings")
        case .unknown, .granted:
            return .idle
        }
    }

    private var microphoneIsEnabled: Bool {
        let base = !isStreaming && speechPermissionState != .denied && !isTranscribingSpeech && !isRequestingSpeechPermission
        return base && !isRequestingRecordPermission && recordPermission == .granted
    }

    private func localeForRecognition() -> Locale {
        Locale.current
    }

    private func setMicrophoneError(_ message: String, autoDismiss: Bool = true) {
        errorDismissTask?.cancel()
        microphoneErrorMessage = message

        if autoDismiss {
            errorDismissTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.5))
                if !Task.isCancelled {
                    clearMicrophoneError()
                }
            }
        }
    }

    private func clearMicrophoneError() {
        errorDismissTask?.cancel()
        microphoneErrorMessage = nil
    }

    private var microphoneFeedback: (text: String, color: Color)? {
        switch microphoneStatus {
        case .disabled(let message):
            return (message, .secondary)
        case .error(let message):
            return (message, .orange)
        default:
            return nil
        }
    }

    private func requestInitialSpeechPermissionsIfNeeded() async {
        guard !hasPrefetchedSpeechPermission else { return }
        hasPrefetchedSpeechPermission = true

        let currentStatus = await speechService.authorizationStatus()
        await MainActor.run {
            updatePermissionState(with: currentStatus)
            clearMicrophoneError()
        }

        switch currentStatus {
        case .authorized, .denied, .restricted:
            AppLogger.ui().log(event: "mic:permissionPrefetch", data: ["status": String(describing: currentStatus)])
        case .notDetermined:
            await MainActor.run { isRequestingSpeechPermission = true }
            let requestedStatus = await speechService.requestAuthorization()
            await MainActor.run {
                isRequestingSpeechPermission = false
                updatePermissionState(with: requestedStatus)
                clearMicrophoneError()
            }
            AppLogger.ui().log(event: "mic:permissionPrefetch", data: ["status": String(describing: requestedStatus)])
        }

        await requestRecordPermissionIfNeeded()
    }

#if os(iOS)
    nonisolated private func requestRecordPermissionIfNeeded() async {
        let permission = AVAudioApplication.shared.recordPermission

        switch permission {
        case .granted:
            await MainActor.run {
                recordPermission = .granted
            }
            AppLogger.ui().log(event: "mic:recordPermission", data: ["status": "granted"])
            return
        case .denied:
            await MainActor.run {
                recordPermission = .denied
                microphoneErrorMessage = "Enable microphone access in Settings."
            }
            AppLogger.ui().log(event: "mic:recordPermission", data: ["status": "denied"])
            return
        case .undetermined:
            await MainActor.run {
                recordPermission = .undetermined
            }
        @unknown default:
            await MainActor.run {
                recordPermission = .denied
                microphoneErrorMessage = "Enable microphone access in Settings."
            }
            AppLogger.ui().log(event: "mic:recordPermission", data: ["status": "unknown"])
            return
        }

        await MainActor.run {
            isRequestingRecordPermission = true
        }

        // Note: AVAudioApplication.requestRecordPermission completion runs on background queue
        let granted: Bool = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        await MainActor.run {
            isRequestingRecordPermission = false
            recordPermission = granted ? .granted : .denied
            microphoneErrorMessage = granted ? nil : "Enable microphone access in Settings."
        }
        AppLogger.ui().log(event: "mic:recordPermission", data: ["status": granted ? "granted" : "denied"])
    }
#else
    private func requestRecordPermissionIfNeeded() async {}
#endif
    
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
        .contentShape(Rectangle())
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
                    sendTranscript("Can you explain quantum computing in simple terms?")
                }
                SuggestionPill(text: "Write code") {
                    sendTranscript("Write a SwiftUI view that displays a list")
                }
                SuggestionPill(text: "Creative writing") {
                    sendTranscript("Write a short story about space exploration")
                }
                SuggestionPill(text: "Problem solving") {
                    sendTranscript("Help me debug this Swift code")
                }
            }
        }
        .padding(.horizontal, 20)
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
    
    @ViewBuilder
    private var inputBarView: some View {
        VStack(spacing: 0) {
            // Subtle top divider
            Divider()
                .opacity(0.5)

            HStack(spacing: 16) {
                // Compact microphone button with state-aware design
                microphoneButton

                // Stop button (replaces mic during streaming)
                if isStreaming {
                    stopButton
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .background {
                inputBarBackground
                    .ignoresSafeArea(edges: .bottom)
            }
            .overlay(alignment: .top) {
                // Status banner that overlays above input bar
                if let feedback = microphoneFeedback {
                    statusBanner(text: feedback.text, color: feedback.color)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    @ViewBuilder
    private var microphoneButton: some View {
        let gesture = DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard microphoneIsEnabled, microphoneStatus.allowsInteraction else { return }
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                startRecordingFromUser()
            }
            .onEnded { _ in
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                finishRecordingFromUser()
            }

        HStack(spacing: 12) {
            // Icon with pulsing animation during recording
            microphoneIcon
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(microphoneIconColor)
                .frame(width: 44, height: 44)
                .background {
                    Circle()
                        .fill(microphoneBackgroundColor)
                }
                .overlay {
                    if case .recording = microphoneStatus {
                        Circle()
                            .stroke(Color.red.opacity(0.5), lineWidth: 2)
                            .scaleEffect(1.2)
                            .opacity(0.8)
                            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: microphoneStatus)
                    }
                }

            // Compact text - single line with dynamic content
            VStack(alignment: .leading, spacing: 2) {
                Text(microphonePrimaryText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(microphonePrimaryColor)

                if let detail = microphoneDetailText {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            // Progress indicator for permission/transcription states
            if microphoneShowsProgress {
                ProgressView()
                    .controlSize(.small)
                    .tint(.blue)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            microphoneContainerBackground
        }
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .opacity(microphoneIsEnabled ? 1.0 : 0.6)
        .gesture(gesture)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: microphoneStatus)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(microphoneAccessibilityLabel)
        .accessibilityHint(microphoneAccessibilityHint)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func statusBanner(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .strokeBorder(color.opacity(0.3), lineWidth: 1)
                    }
            }
            .offset(y: -8)
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }

    // MARK: - Microphone Button Helpers

    private var microphoneIcon: Image {
        switch microphoneStatus {
        case .idle:
            return Image(systemName: "mic.fill")
        case .requestingPermission:
            return Image(systemName: "exclamationmark.circle.fill")
        case .recording:
            return Image(systemName: "waveform")
        case .transcribing:
            return Image(systemName: "arrow.triangle.2.circlepath")
        case .disabled:
            return Image(systemName: "mic.slash.fill")
        case .error:
            return Image(systemName: "exclamationmark.triangle.fill")
        }
    }

    private var microphoneIconColor: Color {
        switch microphoneStatus {
        case .idle:
            return .white
        case .requestingPermission:
            return .white
        case .recording:
            return .white
        case .transcribing:
            return .white
        case .disabled:
            return .white.opacity(0.6)
        case .error:
            return .white
        }
    }

    private var microphoneBackgroundColor: Color {
        switch microphoneStatus {
        case .idle:
            return .blue
        case .requestingPermission:
            return .blue
        case .recording:
            return .red
        case .transcribing:
            return .blue
        case .disabled:
            return .gray
        case .error:
            return .orange
        }
    }

    private var microphonePrimaryColor: Color {
        switch microphoneStatus {
        case .idle, .requestingPermission, .transcribing:
            return .primary
        case .recording:
            return .red
        case .disabled:
            return .secondary
        case .error:
            return .orange
        }
    }

    private var microphonePrimaryText: String {
        switch microphoneStatus {
        case .idle:
            return "Tap & hold to speak"
        case .requestingPermission:
            return "Requesting access…"
        case .recording:
            return "Recording…"
        case .transcribing:
            return "Processing speech…"
        case .disabled:
            return "Microphone unavailable"
        case .error:
            return "Error occurred"
        }
    }

    private var microphoneDetailText: String? {
        switch microphoneStatus {
        case .idle:
            return nil // Removed redundant detail text
        case .requestingPermission:
            return "Grant permissions to continue"
        case .recording:
            return "Release to send"
        case .transcribing:
            return nil
        case .disabled(let message):
            return message.isEmpty ? nil : message
        case .error(let message):
            return message.isEmpty ? nil : message
        }
    }

    private var microphoneShowsProgress: Bool {
        switch microphoneStatus {
        case .requestingPermission, .transcribing:
            return true
        default:
            return false
        }
    }

    private var microphoneContainerBackground: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(.ultraThickMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(.separator.opacity(0.5), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }

    private var microphoneAccessibilityLabel: String {
        switch microphoneStatus {
        case .idle:
            return "Microphone button. Tap and hold to record your message."
        case .requestingPermission:
            return "Requesting microphone permission."
        case .recording:
            return "Recording in progress. Release to send."
        case .transcribing:
            return "Transcribing your speech."
        case .disabled:
            return "Microphone unavailable."
        case .error:
            return "Microphone error. Tap and hold to retry."
        }
    }

    private var microphoneAccessibilityHint: String {
        switch microphoneStatus {
        case .idle:
            return "Double tap and hold to record, release to send your voice message."
        case .recording:
            return "Release to send your voice message."
        case .requestingPermission:
            return "Grant microphone permissions in Settings."
        case .transcribing:
            return "Please wait while processing completes."
        case .disabled:
            return "Enable microphone in Settings to use voice input."
        case .error:
            return "Tap and hold again to retry."
        }
    }
    
    private var stopButton: some View {
        Button(action: { stopStreaming(userInitiated: true) }) {
            Image(systemName: "stop.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.red)
                .background {
                    Circle()
                        .fill(.background)
                        .stroke(.separator.opacity(0.2), lineWidth: 0)
                }
        }
        .accessibilityLabel("Stop response")
        .accessibilityIdentifier("stopButton")
        .animation(.easeInOut(duration: 0.2), value: isStreaming)
    }

    @ViewBuilder
    private var inputBarBackground: some View {
        Rectangle()
            .fill(.thinMaterial)
            .background {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
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
                inputBarView
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
                            localURL: url,
                            runtime: entry.runtime,
                            runtimeIdentifier: entry.gemmaMetadata?.assetIdentifier
                        )
                        persistence.saveSelectedModel(model)
                        onSelectModel(model)
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
            await requestInitialSpeechPermissionsIfNeeded()
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

                // Initialize conversation manager after successful model load
                conversationManager = ConversationManager(modelRuntimeService: runtime)
                conversationManager?.startNewConversation(modelSlug: selected.slug)
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

    private func startRecordingFromUser() {
        guard microphoneIsEnabled else { return }
        clearMicrophoneError()

        Task { @MainActor in
            await beginRecordingFlow()
        }
    }

    private func finishRecordingFromUser() {
        Task { @MainActor in
            await completeRecordingFlow()
        }
    }

    private func beginRecordingFlow() async {
        if isStreaming || isRecording || isTranscribingSpeech {
            return
        }

#if os(iOS)
        if recordPermission == .undetermined && !isRequestingRecordPermission {
            await requestRecordPermissionIfNeeded()
        }
        guard recordPermission == .granted else {
            microphoneErrorMessage = "Enable microphone access in Settings."
            AppLogger.ui().log(event: "mic:record:permissionDenied", data: ["type": "record"])
            return
        }
#endif

        recordingStartTime = nil
        let status = await speechService.authorizationStatus()
        updatePermissionState(with: status)

        if speechPermissionState == .unknown {
            isRequestingSpeechPermission = true
            let requestedStatus = await speechService.requestAuthorization()
            isRequestingSpeechPermission = false
            updatePermissionState(with: requestedStatus)
        }

        guard speechPermissionState == .granted else {
            microphoneErrorMessage = "Microphone access is required to capture your voice."
            AppLogger.ui().log(event: "mic:permissionDenied", data: ["state": String(describing: speechPermissionState)])
            return
        }

        do {
            try await speechService.start(locale: localeForRecognition())
            isRecording = true
            clearMicrophoneError()
            recordingStartTime = Date()
            AppLogger.ui().log(event: "mic:record:start", data: ["model": selected.slug])
        } catch {
            isRecording = false
            await handleSpeechRecognitionError(error)
        }
    }

    private func completeRecordingFlow() async {
        if isRequestingSpeechPermission {
            isRequestingSpeechPermission = false
            if speechPermissionState != .granted {
                microphoneErrorMessage = "Enable microphone & speech recognition in Settings to use voice input."
                return
            }
        }

        guard isRecording else { return }

        isRecording = false
        isTranscribingSpeech = true

        do {
            let transcript = try await speechService.stop()
            isTranscribingSpeech = false

            let elapsedMs: Int?
            if let start = recordingStartTime {
                let duration = Date().timeIntervalSince(start)
                elapsedMs = Int(duration * 1000)
                if duration < 0.5 {
                    recordingStartTime = nil
                    setMicrophoneError("Hold the microphone a bit longer.")
                    #if os(iOS)
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    #endif
                    AppLogger.ui().log(event: "mic:record:tooShort", data: ["durationMs": elapsedMs ?? 0])
                    return
                }
            } else {
                elapsedMs = nil
            }

            recordingStartTime = nil

            let cleaned = transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !cleaned.isEmpty else {
                setMicrophoneError("I didn't catch that. Try speaking again.")
                #if os(iOS)
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                #endif
                AppLogger.ui().log(event: "mic:record:empty", data: [:])
                return
            }

            clearMicrophoneError()
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            AppLogger.ui().log(event: "mic:record:transcript", data: [
                "characters": cleaned.count,
                "durationMs": elapsedMs ?? -1
            ])
            sendTranscript(cleaned)
        } catch {
            isTranscribingSpeech = false
            await handleSpeechRecognitionError(error)
        }
    }

    private func updatePermissionState(with status: SpeechRecognitionService.AuthorizationStatus) {
        switch status {
        case .authorized:
            speechPermissionState = .granted
        case .denied, .restricted:
            speechPermissionState = .denied
        case .notDetermined:
            speechPermissionState = .unknown
        }
    }

    private func handleSpeechRecognitionError(_ error: Error) async {
        recordingStartTime = nil
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif

        if let serviceError = error as? SpeechRecognitionService.ServiceError {
            switch serviceError {
            case .authorizationDenied:
                speechPermissionState = .denied
                setMicrophoneError("Microphone access is required to capture your voice.", autoDismiss: false)
            case .onDeviceRecognitionUnsupported:
                setMicrophoneError("On-device speech recognition isn't supported on this device.", autoDismiss: false)
            case .recognizerUnavailable:
                setMicrophoneError("Speech recognizer is currently unavailable.")
            case .audioEngineUnavailable:
                setMicrophoneError("Couldn't access the microphone. Please try again.")
            case .recognitionFailed(let message):
                setMicrophoneError(message)
            case .recognitionAlreadyRunning:
                setMicrophoneError("A recording session is already active.")
            case .noActiveRecognition:
                setMicrophoneError("No recording session to finish.")
            }
            AppLogger.ui().logError(event: "mic:record:error", error: serviceError)
        } else {
            setMicrophoneError(error.localizedDescription)
            AppLogger.ui().logError(event: "mic:record:error", error: error)
        }

        await speechService.cancel()
        isRecording = false
        isTranscribingSpeech = false
    }

    private func stopStreaming(userInitiated: Bool) {
        if userInitiated {
            userRequestedStop = true
        } else {
            userRequestedStop = false
        }

        streamingTask?.cancel()
        streamingTask = nil
        scrollTimer?.invalidate()
        scrollTimer = nil
        isStreaming = false
    }

    private func sendTranscript(_ rawPrompt: String) {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        stopStreaming(userInitiated: false)
        
        withAnimation(.easeInOut(duration: 0.2)) {
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
        let tokenBudget = contextManager.responseTokenBudget(for: selected.slug)
        AppLogger.runtime().log(event: "stream:start", data: [
            "modelSlug": selected.slug,
            "tokenLimit": tokenBudget
        ])

        streamingTask = Task { @MainActor in
            let startTime = Date()
            var firstTokenTime: Date?
            var tokenCount = 0
            
            do {
                let llmMessages = conversationManager?.getMessagesForLLM() ?? []
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
                userRequestedStop = false
            } catch is CancellationError {
                if assistantIndex < messages.count {
                    let partialResponse = messages[assistantIndex].text
                    if !partialResponse.isEmpty, userRequestedStop {
                        Task { @MainActor in
                            await conversationManager?.addAssistantMessage(partialResponse)
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
