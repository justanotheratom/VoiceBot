# lfm2 iOS (SwiftUI) — PRD and Implementation Plan

## Overview
Build a SwiftUI iOS application (iOS 17.2+) that runs local inference using the Leap Edge SDK. On first launch, the app offers a choice of on-device models and downloads the selected model bundle on demand. The app provides a text-based chatbot UI with streaming responses.

- Primary references:
  - iOS Quick Start Guide (Leap Edge SDK) — [link](https://leap.liquid.ai/docs/edge-sdk/ios/ios-quick-start-guide)
  - Leap iOS SDK repository — [link](https://github.com/Liquid4All/leap-ios?tab=readme-ov-file)
  - Leap Model Library — [link](https://leap.liquid.ai/models)

## Goals & Success Criteria
- iOS 17.2+ SwiftUI app builds and runs on Simulator and physical device.
- Uses LeapSDK v0.5.0+ via Swift Package Manager with both `LeapSDK` and `LeapSDKTypes` products added.
- First-run experience prompts user to select a model from a curated list, then downloads the model bundle on demand.
- Chatbot UI supports streaming tokens using `Conversation.generateResponse`.
- Model choice is persisted; app can switch models later from Settings.
- Minimal, robust error handling: download failures, insufficient storage, network loss, and model load failures.

## Non-Goals
- Cloud inference or online fallback.
- RAG, function calling, or constrained generation (can be future enhancements).
- Complex message history persistence or multimedia content types.

## Target Platforms
- iOS 17.2+
- Xcode 15+ with Swift 5.9+
- Works on Simulator; recommend testing on device for performance (per Leap docs).
  - Ref: Quick Start prerequisites — [link](https://leap.liquid.ai/docs/edge-sdk/ios/ios-quick-start-guide)

## User Experience
1. First Launch (no model):
   - Model selection screen with curated model list (name, size estimate, context window, short description).
   - User selects a model; app initiates download with visible progress and remaining size/time.
   - On completion, app loads the model and transitions to Chat.

2. Chat Screen:
   - Simple message list (user/assistant) and text input field.
   - Send triggers streaming response (token-by-token) with a typing indicator.
   - Error banner for transient failures; retry affordance.

3. Settings:
   - Show current model details and storage location.
   - Option to switch model (returns to selection screen and downloads if needed).
   - Option to remove downloaded models to reclaim space.

## Functional Requirements
- Model Management
  - Curated model catalog embedded in the app with display names and metadata.
  - Download via Leap’s downloader APIs; support resume/retry where available.
  - Persist selected model identifier and local file URL (or re-resolve on launch) in `UserDefaults`.
  - Allow switching/removal of models.

- Inference
  - Load model via `Leap.load(url:)` into a reusable `ModelRunner`.
  - Create a `Conversation` per chat session; support streaming responses and report token usage if available.

- State Management
  - Use `@Observable` or `ObservableObject` for app state: model loading, download progress, chat messages, generation state, and errors.

## Non-Functional Requirements
- Reliability: gracefully handle network failure during download; user-visible errors with retry.
- Performance: load model once and reuse; avoid blocking main thread; streaming UI updates.
- Storage: surface download sizes; detect and communicate low-space scenarios.
- Privacy: on-device inference; no network beyond model download source.

## Architecture
- UI: SwiftUI views: `ModelSelectionView`, `ChatView`, `SettingsView`.
- State: `AppStore`/`ChatStore` central observable models.
- Services:
  - `ModelCatalog` (static list of supported models).
  - `ModelDownloadService` (wraps Leap downloader).
  - `ModelRuntimeService` (wraps `Leap.load` and provides `Conversation`).
  - `PersistenceService` (selected model and paths).

## Key Technical Choices
- Leap SDK Integration
  - Add SPM package: `https://github.com/Liquid4All/leap-ios.git`, select v0.5.0+.
  - Add both `LeapSDK` and `LeapSDKTypes` products to target (as required in v0.5.0+).
  - Ref: Quick Start — [link](https://leap.liquid.ai/docs/edge-sdk/ios/ios-quick-start-guide)

- Model Downloading
  - Prefer dynamic, on-demand download over bundling, using Leap Model Downloader APIs (e.g., `LeapDownloadableModel.resolve` or `HuggingFaceDownloadableModel`).
  - Ref: Download On-Demand — [link](https://leap.liquid.ai/docs/edge-sdk/ios/ios-quick-start-guide)

- Model Catalog (initial curated set)
  - Example entries (subject to availability in the Leap Model Library):
    - Qwen 0.6B (8DA4W, 4K context) — slug: `qwen-0.6b`, quantization example: `qwen-0.6b-20250610-8da4w`, filename example: `qwen3-0_6b_8da4w_4096.bundle`.
    - Additional small/medium models from `https://leap.liquid.ai/models` with differing sizes/speeds.
  - We’ll hardcode 3–5 options with metadata; future work can fetch catalog dynamically.

- Persistence
  - Store selected model slug and local URL in `UserDefaults` (or compute URL from downloader on launch).

- Error Handling
  - Surface clear user-facing messages, retry on transient errors, and allow switching models if load fails.

## Data Model (App)
- `SelectedModel`: `{ id, displayName, provider, slug, quantizationSlug?, estDownloadMB, contextWindow }`.
- `DownloadState`: `.notStarted | .inProgress(progress: Double) | .downloaded(localURL: URL) | .failed(error: String)`.
- `Message`: `{ role: user|assistant, text: String, timestamp }`.

## UI Flows
- First run:
  - If no selected model or model not downloaded → `ModelSelectionView` → choose model → start download → show progress → on complete, `Leap.load` → go to `ChatView`.
- Relaunch:
  - If selected model resolved and present → `Leap.load` → `ChatView`.
  - If missing (deleted by user/OS) → prompt to redownload.

## Security & Privacy
- On-device inference; downloads from trusted sources (Leap Model Library or Hugging Face per docs).
- No end-user personal data sent to servers by default.

## Risks & Mitigations
- Download or resume not available on flaky networks → show retry and partial progress where supported.
- Large models on low-storage devices → preflight storage check and warn users.
- Simulator performance is slow → document recommendation to test on device.
- API surface changes across SDK versions → pin to `~> 0.5.0`.

## Implementation Plan
1. Project Scaffolding
   - Create SwiftUI iOS app (iOS 17.2 minimum).
   - Add SPM dependency for Leap iOS SDK (`LeapSDK` and `LeapSDKTypes`).
   - Prepare app targets and build settings.

2. Model Services
   - Implement `ModelCatalog` with curated options referencing slugs and quantizations from the model library.
   - Implement `ModelDownloadService` using Leap downloader (`LeapDownloadableModel` / `HuggingFaceDownloadableModel`).
   - Implement persistence for chosen model and local path.

3. Runtime & Chat
   - Implement `ModelRuntimeService` to `Leap.load(url:)` and create `Conversation`.
   - Implement `ChatStore` with streaming `generateResponse` integration.

4. UI
   - `ModelSelectionView` with list, details, and download progress UI.
   - `ChatView` with message list, input, send button, streaming updates.
   - `SettingsView` to switch or remove models.

5. Build, Run, and Iterate
   - Build for Simulator (for correctness) and device (for performance).
   - Handle errors surfaced in logs; refine UX.

6. Polishing
   - Basic empty/error states, accessibility labels, loading indicators.
   - Basic unit tests for persistence and catalog selection logic (time-permitting).

## Testing & Validation
- Build/Run via command-line automation to ensure repeatability and CI readiness.
  - Use `xcodebuild` workflow (via our automation helper) to:
    - List schemes
    - Build for iOS Simulator
    - Run on a chosen simulator and capture logs
  - Verify first-run flow, download progress, successful `Leap.load`, and streaming responses.

## Open Questions / Assumptions
- Leap Model Downloader module import path: docs show `import LeapModelDownloader`. We assume it’s available via the Leap SPM or a companion package; if separate, we’ll add its SPM as well.
- Exact model slugs/quantization IDs will be confirmed from the model library at implementation time.

## References
- Leap iOS Quick Start — [link](https://leap.liquid.ai/docs/edge-sdk/ios/ios-quick-start-guide)
- Leap iOS SDK repo — [link](https://github.com/Liquid4All/leap-ios?tab=readme-ov-file)
- Leap Model Library — [link](https://leap.liquid.ai/models)
