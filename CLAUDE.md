# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Project Overview

**VoiceBot** is a native iOS application (iOS 18.0+) that runs on-device LLM inference using Liquid AI's Leap SDK and MLX Swift. The app supports both LFM2 models (via Leap SDK) and Gemma models (via MLX Swift), with a chat interface featuring streaming responses, model management, and speech-to-text input.

- **Tech Stack:** Swift 6.1+, SwiftUI, Swift Concurrency (async/await, actors)
- **Architecture:** Model-View (MV) pattern with native SwiftUI state management (@State, @Observable, @Environment)
- **LLM Engines:** Leap SDK for LFM2 models, MLX Swift for Gemma models
- **Testing:** Swift Testing framework with @Test macros
- **Project Structure:** Workspace + SPM package architecture

## Key Features

- **Multi-Model Support:** LFM2 (350M, 700M, 1.2B) and Gemma (2B, 2.6B) models
- **On-Demand Downloads:** Models downloaded as needed with progress tracking
- **Streaming Chat:** Token-by-token streaming responses with typing indicators
- **Speech Input:** Real-time speech-to-text via iOS Speech framework
- **Model Management:** Settings UI for downloading, switching, and deleting models
- **Conversation History:** Persisted chat sessions with SwiftData

# Project Architecture

```
VoiceBot/
├── VoiceBot.xcworkspace/              # Open this in Xcode
├── VoiceBot.xcodeproj/                # App shell (minimal)
├── VoiceBot/                          # App target entry point
│   └── VoiceBotApp.swift              # @main app lifecycle
├── VoiceBotPackage/                   # 🚀 All development happens here
│   ├── Package.swift                   # Dependencies (LeapSDK, MLX, etc.)
│   ├── Sources/VoiceBotFeature/       # Feature code
│   │   ├── ContentView.swift           # Root view & chat UI
│   │   ├── ModelCatalog.swift          # Model metadata
│   │   ├── *Service.swift              # Core business logic
│   │   ├── *RuntimeAdapter.swift       # LLM engine adapters
│   │   ├── MicrophoneInputBar.swift    # Speech input UI
│   │   ├── Conversations/              # Chat history models
│   │   └── ...
│   └── Tests/VoiceBotFeatureTests/    # Unit tests
├── Config/                              # Build settings
│   ├── Shared.xcconfig                 # Bundle ID, versions
│   └── VoiceBot.entitlements          # Speech, microphone permissions
└── docs/                                # Design docs, PRD
```

**Important:** All feature development happens in `VoiceBotPackage/Sources/VoiceBotFeature/`. The app target only imports and displays the package.

# Common Development Commands

## Building and Running

**Use XcodeBuildMCP tools** (preferred over raw xcodebuild):

```javascript
// List simulators
list_sims({ enabled: true })

// Build and run on iPhone 16 simulator
build_run_sim({
    workspacePath: "/path/to/VoiceBot.xcworkspace",
    scheme: "VoiceBot",
    simulatorName: "iPhone 16"
})

// Build for device
build_dev_ws({
    workspacePath: "/path/to/VoiceBot.xcworkspace",
    scheme: "VoiceBot",
    configuration: "Debug"
})
```

## Testing

```javascript
// Run all tests on simulator
test_sim_name_ws({
    workspacePath: "/path/to/VoiceBot.xcworkspace",
    scheme: "VoiceBot",
    simulatorName: "iPhone 16"
})

// IMPORTANT: Use test_sim_name_ws, NOT swift_package_test
```

## Simulator Automation

```javascript
// Get UI hierarchy for testing
describe_ui({ simulatorUuid: "UUID" })

// Tap at coordinates
tap({ simulatorUuid: "UUID", x: 100, y: 200 })

// Type text
type_text({ simulatorUuid: "UUID", text: "Hello" })

// Take screenshot
screenshot({ simulatorUuid: "UUID" })

// Capture logs
start_sim_log_cap({ simulatorUuid: "UUID", bundleId: "com.oneoffrepo.VoiceBot" })
stop_sim_log_cap({ logSessionId: "SESSION_ID" })
```

# Core Architecture Patterns

## Service Layer

The app uses **actor-based services** for thread-safe LLM operations:

- **ModelCatalog**: Static catalog of LFM2 and Gemma models with metadata
- **ModelDownloadService**: Handles model downloads with progress tracking
- **ModelStorageService**: Manages downloaded bundles (ZIP and directory formats)
- **ModelRuntimeService** (actor): Thread-safe model loading and inference coordination
- **PersistenceService**: UserDefaults for selected model preferences
- **SpeechRecognitionService**: Speech-to-text via iOS Speech framework

## Runtime Adapters Pattern

The app abstracts LLM engines using the **Adapter pattern**:

```swift
protocol ModelRuntimeAdapter {
    func loadModel(url: URL) async throws
    func unloadModel() async
    func generateResponse(prompt: String, stream: AsyncStream<String>) async throws
}

// Implementations:
class LeapRuntimeAdapter: ModelRuntimeAdapter { /* Leap SDK */ }
class GemmaRuntimeAdapter: ModelRuntimeAdapter { /* MLX Swift */ }
```

`ModelRuntimeService` (actor) selects the correct adapter based on model provider:
- LFM2 models → `LeapRuntimeAdapter`
- Gemma models → `GemmaRuntimeAdapter`

## State Management (MV Pattern)

Uses SwiftUI's native state management:

```swift
@Observable
class ChatState {
    var messages: [Message] = []
    var isGenerating = false
    var currentModel: ModelInfo?
}

struct ChatView: View {
    @State private var chatState = ChatState()
    @Environment(ModelRuntimeService.self) private var runtime

    var body: some View {
        // View is pure representation of state
    }
}
```

**Key principles:**
- `@State` for view-local state
- `@Observable` for shared models (not ViewModels!)
- `@Environment` for app-wide services
- `.task` modifier for async operations (auto-cancels on disappear)

## Conversation History (SwiftData)

Chat sessions persist using SwiftData:

```swift
@Model
final class Conversation {
    var id: UUID
    var title: String
    var modelSlug: String
    @Relationship(deleteRule: .cascade) var messages: [Message]
}

// Usage in views
@Query private var conversations: [Conversation]
@Environment(\.modelContext) private var context
```

# LLM Integration Details

## Leap SDK (LFM2 Models)

- **SDK Version:** 0.5.0+
- **Models:** LFM2-350M, LFM2-700M, LFM2-1.2B (8DA4W quantization)
- **Download:** `LeapModelDownloader.requestDownloadModel()` + polling
- **Inference:** `Conversation.generateResponse(prompt:)` for streaming

## MLX Swift (Gemma Models)

- **SDK Version:** 0.25.6+ (mlx-swift, mlx-swift-examples)
- **Models:** Gemma-2B-IT, Gemma-2.6B-IT (4-bit quantized)
- **Download:** Hugging Face Hub API (`HubApi.snapshot()`)
- **Inference:** `MLXLLM.generate(prompt:)` with custom streaming

## Bundle Format Support

Both ZIP and directory bundles are supported:
- **Leap SDK:** Downloads ZIP bundles (`.bundle` files)
- **MLX/Gemma:** Downloads directory bundles from Hugging Face
- Storage/runtime services auto-detect format

# Speech Recognition Integration

Uses iOS Speech framework for microphone input:

- **Service:** `SpeechRecognitionService` (actor) handles speech requests
- **Permissions:** `NSSpeechRecognitionUsageDescription` and `NSMicrophoneUsageDescription` in Info.plist
- **UI:** `MicrophoneInputBar` with visual feedback during recording
- **Entitlements:** `Config/VoiceBot.entitlements` includes microphone access

# Key Implementation Notes

## Model Download Progress

Leap SDK uses **polling-based progress**:

```swift
// Start download
downloader.requestDownloadModel(model)

// Poll for progress
while true {
    let status = await downloader.queryStatus(model)
    switch status {
    case .downloadInProgress(let progress):
        updateUI(progress) // 0.0 to 1.0
    case .downloaded:
        break
    }
}
```

## Gemma Model Normalization

Gemma models require **config normalization** due to safetensors format issues:

- `GemmaConfigNormalizer`: Rewrites safetensor headers with sanitized keys
- Fixes "missingKey" errors during model load
- Backfills index keys from safetensors header

## Safe Model Switching

Always unload before switching models:

```swift
await runtimeService.unloadModel() // Cleans up ModelRunner/Conversation
await runtimeService.loadModel(newModelURL)
```

## Concurrency Patterns

- **Actor isolation:** `ModelRuntimeService` is an actor for thread safety
- **@MainActor:** All UI updates use `@MainActor` isolation
- **Structured concurrency:** Use `.task` modifier, not `Task { }` in `onAppear`
- **Sendable conformance:** All types crossing actor boundaries are Sendable

# Testing

Uses **Swift Testing framework** (not XCTest):

```swift
import Testing

@Test func modelCatalogHasModels() {
    #expect(ModelCatalog.allModels.count > 0)
}

@Test("Download service handles progress")
func downloadProgress() async throws {
    let service = ModelDownloadService()
    // Test implementation
    #expect(progress >= 0.0 && progress <= 1.0)
}
```

**Test files:** `VoiceBotPackage/Tests/VoiceBotFeatureTests/`

**Run tests:** Use `test_sim_name_ws` tool (NOT `swift_package_test`)

# Logging

Uses Apple Unified Logging with structured JSON:

```swift
import os
let logger = Logger(subsystem: "com.oneoffrepo.VoiceBot", category: "runtime")

logger.info("{ event: \"load:start\", url: \"\(url.path)\" }")
logger.info("{ event: \"stream:complete\", tokens: \(count), usage: \(tps) }")
```

**Categories:** `app`, `download`, `runtime`, `ui`, `storage`, `speech`

# Development Workflow

1. **Make changes** in `VoiceBotPackage/Sources/VoiceBotFeature/`
2. **Write tests** in `VoiceBotPackage/Tests/VoiceBotFeatureTests/`
3. **Build & test** using XcodeBuildMCP tools
4. **Deploy to simulator** for manual testing
5. **Verify with automation** (describe_ui, tap, screenshot)
6. **IMPORTANT:** After functional changes, deploy to simulator and test using XcodeBuildMCP

# Common Tasks

## Add New Model

1. Update `ModelCatalog.swift` with model metadata
2. Add download adapter in `ModelDownloadAdapters.swift`
3. Update runtime adapter selection logic if new provider

## Add New Feature

1. Create SwiftUI view in `VoiceBotPackage/Sources/VoiceBotFeature/`
2. Add `@Observable` models if needed (no ViewModels!)
3. Use `.task` for async operations
4. Write tests in `Tests/` directory
5. Mark public types/methods as `public` if exposed to app target

## Add SPM Dependency

Edit `VoiceBotPackage/Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/example/Package", from: "1.0.0")
],
targets: [
    .target(
        name: "VoiceBotFeature",
        dependencies: ["Package"]
    )
]
```

## Add Entitlements

Edit `Config/VoiceBot.entitlements` (XML format):

```xml
<key>com.apple.developer.some-capability</key>
<true/>
```

Common entitlements table in template documentation applies.

# Performance Characteristics

- **Model Load Time:** ~0.33s (LFM2-350M), ~1.5s (Gemma-2B)
- **Inference Speed:** ~127 tokens/sec (LFM2 on simulator), ~45 tokens/sec (Gemma)
- **Memory Usage:** 300-900MB depending on model size
- **Context Window:** 4096 tokens (LFM2), 8192 tokens (Gemma)
- **Storage:** 320MB (LFM2-350M), 920MB (LFM2-1.2B), 1.5GB (Gemma-2B)

# Troubleshooting

## Common Issues

**Download stuck at 0%:** Use `requestDownloadModel()` + polling (not `downloadModel()`)

**Model load failures:** Check bundle format (ZIP vs directory), verify normalizer for Gemma

**Speech recognition not working:** Verify entitlements and Info.plist permissions

**Build errors:** Clean build folder (`clean_ws`) and rebuild SPM packages

## Error Handling

- Download failures: Retry logic with exponential backoff
- Model load failures: Safe fallback to model selection screen
- Speech errors: Graceful degradation to text input only
- Storage issues: Pre-download space checks

# Code Style

- **Naming:** UpperCamelCase types, lowerCamelCase properties/functions
- **Immutability:** Prefer `let` over `var`
- **Early returns:** Avoid nested conditionals
- **No force-unwrap:** Use `guard let` or `if let`
- **Accessibility:** All interactive elements need `accessibilityLabel`
- **No ViewModels:** Use SwiftUI native state management

# References

- **Leap SDK Docs:** https://leap.liquid.ai/docs/edge-sdk/ios/ios-quick-start-guide
- **MLX Swift:** https://github.com/ml-explore/mlx-swift
- **Swift Testing:** https://developer.apple.com/documentation/testing
- **Project PRD:** `docs/PRD.md`
- **Cursor Rules:** `.cursor/rules/*.mdc` for detailed patterns
