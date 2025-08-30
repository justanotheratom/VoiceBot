# lfm2onios - iOS App

A modern iOS application using a **workspace + SPM package** architecture for clean separation between app shell and feature code.

## AI Assistant Rules Files

This template includes **opinionated rules files** for popular AI coding assistants. These files establish coding standards, architectural patterns, and best practices for modern iOS development using the latest APIs and Swift features.

### Included Rules Files
- **Claude Code**: `CLAUDE.md` - Claude Code rules
- **Cursor**: `.cursor/*.mdc` - Cursor-specific rules
- **GitHub Copilot**: `.github/copilot-instructions.md` - GitHub Copilot rules

### Customization Options
These rules files are **starting points** - feel free to:
- ✅ **Edit them** to match your team's coding standards
- ✅ **Delete them** if you prefer different approaches
- ✅ **Add your own** rules for other AI tools
- ✅ **Update them** as new iOS APIs become available

### What Makes These Rules Opinionated
- **No ViewModels**: Embraces pure SwiftUI state management patterns
- **Swift 6+ Concurrency**: Enforces modern async/await over legacy patterns
- **Latest APIs**: Recommends iOS 18+ features with optional iOS 26 guidelines
- **Testing First**: Promotes Swift Testing framework over XCTest
- **Performance Focus**: Emphasizes @Observable over @Published for better performance

**Note for AI assistants**: You MUST read the relevant rules files before making changes to ensure consistency with project standards.

## Project Architecture

```
lfm2onios/
├── lfm2onios.xcworkspace/              # Open this file in Xcode
├── lfm2onios.xcodeproj/                # App shell project
├── lfm2onios/                          # App target (minimal)
│   ├── Assets.xcassets/                # App-level assets (icons, colors)
│   ├── lfm2oniosApp.swift              # App entry point
│   └── lfm2onios.xctestplan            # Test configuration
├── lfm2oniosPackage/                   # 🚀 Primary development area
│   ├── Package.swift                   # Package configuration
│   ├── Sources/lfm2oniosFeature/       # Your feature code
│   └── Tests/lfm2oniosFeatureTests/    # Unit tests
└── lfm2oniosUITests/                   # UI automation tests
```

## Key Architecture Points

### Workspace + SPM Structure
- **App Shell**: `lfm2onios/` contains minimal app lifecycle code
- **Feature Code**: `lfm2oniosPackage/Sources/lfm2oniosFeature/` is where most development happens
- **Separation**: Business logic lives in the SPM package, app target just imports and displays it

### Buildable Folders (Xcode 16)
- Files added to the filesystem automatically appear in Xcode
- No need to manually add files to project targets
- Reduces project file conflicts in teams

## Development Notes

### Code Organization
Most development happens in `lfm2oniosPackage/Sources/lfm2oniosFeature/` - organize your code as you prefer.

### Public API Requirements
Types exposed to the app target need `public` access:
```swift
public struct NewView: View {
    public init() {}
    
    public var body: some View {
        // Your view code
    }
}
```

### Adding Dependencies
Edit `lfm2oniosPackage/Package.swift` to add SPM dependencies:
```swift
dependencies: [
    .package(url: "https://github.com/example/SomePackage", from: "1.0.0")
],
targets: [
    .target(
        name: "lfm2oniosFeature",
        dependencies: ["SomePackage"]
    ),
]
```

## Project-Specific Implementation Details

### LLM Integration (Leap SDK)
This app integrates with [Liquid AI's Leap SDK](https://leap.liquid.ai/) for on-device LLM inference:

- **SDK**: LeapSDK v0.5.0+ via Swift Package Manager
- **Models**: LFM2 family models (350M, 700M, 1.2B parameters)
- **Download**: Uses `LeapModelDownloader` for on-demand model downloads
- **Inference**: Streaming chat responses via `Conversation.generateResponse`

### Key Services

#### Core Service Architecture
- `ModelCatalog`: Static catalog of available LFM2 models with metadata
- `ModelDownloadService`: Handles model downloads with progress tracking
- `ModelStorageService`: Manages downloaded model files and storage detection  
- `ModelRuntimeService`: Loads models and handles inference with LeapSDK
- `PersistenceService`: Saves/loads selected model preferences

#### Service Integration Patterns
- **Actor-Based Concurrency**: `ModelRuntimeService` uses actor pattern for thread-safe model operations
- **Async/Await**: All services use modern Swift Concurrency (no completion handlers)
- **Dependency Injection**: Services passed as parameters, not singleton globals
- **State Management**: SwiftUI `@State` and `@Observable` for reactive UI updates
- **Safe Model Lifecycle**: `unloadModel()` ensures proper cleanup during model switches

### Bundle Format Support
The app supports both directory and ZIP-based model bundles:
- **Directory bundles**: Traditional `.bundle` folders with model files
- **ZIP bundles**: Compressed `.bundle` files downloaded by LeapModelDownloader
- Storage and runtime services automatically detect and handle both formats

### Download Progress Implementation
Progress tracking uses LeapModelDownloader's polling API:
```swift
// Start download
downloader.requestDownloadModel(model)

// Poll for progress
let status = await downloader.queryStatus(model)
switch status {
case .downloadInProgress(let progress):
    updateProgressUI(progress) // 0.0 to 1.0
case .downloaded:
    // Download complete
}
```

### Model Storage
- **Location**: `Application Support/Models/`  
- **Format**: `{quantization-slug}.bundle` (e.g., `lfm2-350m-20250710-8da4w.bundle`)
- **Size**: Models range from ~320MB (350M) to ~920MB (1.2B)
- **Detection**: Handles both file and directory bundles transparently

### Performance Characteristics
- **Model Load Time**: ~0.33 seconds (LFM2-350M)
- **Inference Speed**: ~127 tokens/second (iPhone simulator)
- **Memory**: Models use ~300-900MB depending on size
- **Context Window**: 4,096 tokens for all LFM2 models

### Error Handling
Common issues and solutions:
- **Download stuck at 0%**: Fixed by using `requestDownloadModel()` + polling
- **Model load failures**: Ensure ZIP bundle support in storage/runtime services  
- **Network failures**: Download service includes retry logic
- **Storage issues**: App checks available space before downloads

### UI Architecture & Navigation

#### Current UI Flow (Phase 6)
The app uses a simplified, card-based interface for model management:

1. **Chat View**: Shows current model name in navigation bar with new conversation (+) and settings (⚙️) buttons
2. **Settings View**: Displays all models as cards with inline actions - no complex navigation flows
3. **Model Cards**: Each card shows model info with contextual buttons based on state

#### Settings UI Design Pattern
- **Visual Selection**: Selected model has blue background/border (no redundant text labels)
- **Icon-Based Actions**: SF Symbols for all actions (download ⬇️, select ✓, delete 🗑️)
- **State-Aware UI**: Buttons change based on model state (not downloaded → downloaded → selected)
- **Immediate Feedback**: Model switching happens instantly with automatic settings dismissal

#### Key UI Components
- `ContentView`: Root navigation and model state management
- `ChatView`: Conversation interface with model indicator and toolbar
- `SettingsView`: Simplified card-based model management
- `ModelCardView`: Individual model card with state-aware actions
- `ModelSelectionView`: First-run model selection (legacy, used for initial setup)

### Test Structure
- **Unit Tests**: `lfm2oniosPackage/Tests/lfm2oniosFeatureTests/` (Swift Testing framework)
- **UI Tests**: `lfm2oniosUITests/` (XCUITest framework)
- **Test Plan**: `lfm2onios.xctestplan` coordinates all tests

## Configuration

### XCConfig Build Settings
Build settings are managed through **XCConfig files** in `Config/`:
- `Config/Shared.xcconfig` - Common settings (bundle ID, versions, deployment target)
- `Config/Debug.xcconfig` - Debug-specific settings  
- `Config/Release.xcconfig` - Release-specific settings
- `Config/Tests.xcconfig` - Test-specific settings

### Entitlements Management
App capabilities are managed through a **declarative entitlements file**:
- `Config/lfm2onios.entitlements` - All app entitlements and capabilities
- AI agents can safely edit this XML file to add HealthKit, CloudKit, Push Notifications, etc.
- No need to modify complex Xcode project files

### Asset Management
- **App-Level Assets**: `lfm2onios/Assets.xcassets/` (app icon, accent color)
- **Feature Assets**: Add `Resources/` folder to SPM package if needed

### SPM Package Resources
To include assets in your feature package:
```swift
.target(
    name: "lfm2oniosFeature",
    dependencies: [],
    resources: [.process("Resources")]
)
```

### Generated with XcodeBuildMCP
This project was scaffolded using [XcodeBuildMCP](https://github.com/cameroncooke/XcodeBuildMCP), which provides tools for AI-assisted iOS development workflows.