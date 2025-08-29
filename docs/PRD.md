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

## Implementation Plan (Phased E2E Slices)
Each phase is independently buildable and runnable end-to-end in the iOS Simulator. After every phase, run the simulator automation to catch compile/runtime issues and review logs.

Phase 0 — Project Bootstrap (E2E)
- Create SwiftUI iOS app (iOS 17.2 minimum) with a single screen (“Hello lfm2”).
- Add basic logging scaffolding using `os.log` with subsystem `com.oneoffrepo.lfm2onios` and categories: `app`, `download`, `runtime`, `ui`.
- Simulator automation: list schemes, build for a simulator, run the app, verify launch and log output.

Phase 1 — Integrate Leap SDK (Compile E2E)
- Add SPM dependency `https://github.com/Liquid4All/leap-ios.git` (v0.5.0+), include products `LeapSDK` and `LeapSDKTypes`.
- Verify the app still builds and runs (even if not yet using the SDK at runtime).
- Log successful SDK link at startup.

Phase 2 — Model Catalog UI (E2E)
- Implement `ModelCatalog` (static list of 3–5 curated models with metadata from the model library).
- Implement `ModelSelectionView` showing the models and a “Download” action (no real download yet).
- Persist selection intent to `UserDefaults`.
- Run end-to-end; log selection events and navigation flows.

Phase 3 — Download Flow (Mock, E2E)
- Implement `ModelDownloadService` with a mock downloader to simulate progress and completion; wire to the UI progress.
- Exercise cancel, retry, and error states with mock injections; log all state transitions.
- Run end-to-end in simulator to validate UX and state handling.

Phase 4 — Real Download Integration (E2E)
- Replace mock with Leap downloader APIs (`import LeapModelDownloader`), using either `LeapDownloadableModel.resolve` or `HuggingFaceDownloadableModel` based on catalog entry.
- Persist downloaded model local URL or re-resolvable descriptor.
- Add storage checks and user-friendly errors; log progress ticks at ~10% intervals and errors verbosely.
- Run end-to-end; confirm file presence post-download.

Phase 5 — Runtime Load & Chat (E2E)
- Implement `ModelRuntimeService` using `Leap.load(url:)` to create a reusable `ModelRunner`.
- Create a `Conversation` on demand and integrate with `ChatStore`.
- Implement `ChatView` input and message list; stream tokens using `generateResponse` and update UI incrementally.
- Log: model load start/end, memory warnings, token streaming start/stop, completion reasons, and usage stats when available.
- Run end-to-end with a small model to validate streaming.

Phase 6 — Settings & Model Lifecycle (E2E)
- Implement `SettingsView`: show current model info, switch model (re-run selection/download if needed), and delete local bundles.
- Ensure safe teardown of `ModelRunner` and `Conversation` when switching models; log lifecycle events.
- Run end-to-end; validate switching and cleanup.

Phase 7 — Polishing & Hardening
- Empty/error states, accessibility, loading/typing indicators.
- Add lightweight unit tests for persistence and catalog mapping; stabilize logs (consistent keys/values).
- Final simulator/device passes for UX and stability.

For every phase above:
- Build and run the app in the iOS Simulator via the simulator automation.
- Capture and review logs; fix compile/runtime issues before moving to the next phase.

Definition of Done (per phase)
- The app launches on the simulator without crashes.
- The new capability is demonstrably usable from UI.
- Logs include expected markers for the implemented feature.

Rollbacks
- Feature flags or conditional code paths can disable in-progress features if needed for demos.

Contingencies
- If Leap downloader APIs require separate SPM package, add it during Phase 4.

Deliverables per Phase
- Code changes, updated PRD checkbox for phase completion, and a short run log snippet.

Owner’s Notes
- Always keep the model runner singleton-like for the app session; avoid reloading for every message.

## Observability & Logging
- Use Apple Unified Logging (`os.log`) with subsystem `com.oneoffrepo.lfm2onios` and categories:
  - `app`: app lifecycle, configuration, feature flags.
  - `download`: model resolution, progress, completion, failures, disk checks.
  - `runtime`: model load/unload, memory warnings, conversation lifecycle, token streaming.
  - `ui`: navigation, user actions (sanitized), view states.
- Include error domains/codes in logs and a compact, structured `userInfo` dictionary where helpful.
- Add a developer “Debug Info” sheet (hidden behind a long-press or gesture) that shows last errors and current states.
- Never log sensitive user content beyond what appears in UI; prefer redaction for prompts if needed.

## Testing & Validation
- After each phase, execute simulator automation to detect compile/runtime issues:
  - List available simulators and choose a recent iPhone runtime.
  - Build for the selected simulator and run the app.
  - Capture console output and validate presence of expected log markers (`app`, `download`, `runtime`, `ui`).
- Validate first-run flow, download progress, successful `Leap.load`, and streaming responses using small prompts.
- Periodically build to device for performance checks once download/runtime phases are complete.

## Open Questions / Assumptions
- Leap Model Downloader module import path: docs show `import LeapModelDownloader`. We assume it’s available via the Leap SPM or a companion package; if separate, we’ll add its SPM as well.
- Exact model slugs/quantization IDs will be confirmed from the model library at implementation time.

## References
- Leap iOS Quick Start — [link](https://leap.liquid.ai/docs/edge-sdk/ios/ios-quick-start-guide)
- Leap iOS SDK repo — [link](https://github.com/Liquid4All/leap-ios?tab=readme-ov-file)
- Leap Model Library — [link](https://leap.liquid.ai/models)
