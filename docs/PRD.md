# lfm2 iOS (SwiftUI) — PRD and Implementation Plan

## Overview
Build a SwiftUI iOS application (iOS 17.2+) that runs local inference using the Leap Edge SDK. On first launch, the app offers a choice of on-device models and downloads the selected model bundle on demand. The app provides a text-based chatbot UI with streaming responses.

- Primary references:
  - iOS Quick Start Guide (Leap Edge SDK) — [link](https://leap.liquid.ai/docs/edge-sdk/ios/ios-quick-start-guide)
  - Leap iOS SDK repository — [link](https://github.com/Liquid4All/leap-ios?tab=readme-ov-file)
  - Leap Model Library — [link](https://leap.liquid.ai/models)

## Goals & Success Criteria
- iOS 17.2+ SwiftUI app builds and runs on Simulator and physical device.
- Uses LeapSDK v0.5.0+ via Swift Package Manager (link product `LeapSDK`).
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
  - Link product `LeapSDK` in the app’s Swift Package target. (Note: There is no separate `LeapSDKTypes` product in v0.5.0.)
  - Ref: Quick Start — [link](https://leap.liquid.ai/docs/edge-sdk/ios/ios-quick-start-guide)

- Model Downloading
  - Prefer dynamic, on-demand download over bundling, using Leap Model Downloader APIs (e.g., `LeapDownloadableModel.resolve` or `HuggingFaceDownloadableModel`).
  - Ref: Download On-Demand — [link](https://leap.liquid.ai/docs/edge-sdk/ios/ios-quick-start-guide)

### Downloader Packaging and ATS/Networking
- Downloader module import is `import LeapModelDownloader`. If this is not included with the core SPM, add the companion SPM package provided by Leap and pin to a compatible `~> 0.5.0` version.
- All downloads occur over HTTPS; no ATS exceptions expected. If any model source requires non-HTTPS (not recommended), we will add targeted ATS exceptions with justification.
- MVP uses foreground downloads with resume/retry; background transfer is out-of-scope.

- Model Catalog (initial curated set)
  - Example entries (subject to availability in the Leap Model Library):
    - Qwen 0.6B (8DA4W, 4K context) — slug: `qwen-0.6b`, quantization: `qwen-0.6b-20250610-8da4w`, filename: `qwen3-0_6b_8da4w_4096.bundle`.
    - TinyLM 0.5–1B class model (fast on mobile) — choose a small-capacity option from the model library.
    - Mid-size 1.5–3B class model — slower but better quality for testing trade-offs.
  - We’ll hardcode 3–5 options with metadata; future work can fetch catalog dynamically from the Leap Model Library — [link](https://leap.liquid.ai/models).

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

- Status: Done (2025-08-29)
- Run log snippet (launch):
```
app: { event: "launch", build: "1.0 (1)" }
```

Phase 1 — Integrate Leap SDK (Compile E2E)
- Add SPM dependency `https://github.com/Liquid4All/leap-ios.git` (v0.5.0+), link product `LeapSDK`.
- Verify the app still builds and runs (even if not yet using the SDK at runtime).
- Log successful SDK link at startup.

- Status: Done (2025-08-29)
- Run log snippet (launch):
```
app: { event: "launch", build: "1.0 (1)" }
app: { event: "leap:sdkLinked", sdkVersion: "unknown" }
```

Phase 2 — Model Catalog UI (E2E)
- Implement `ModelCatalog` (static list of 3–5 curated models with metadata from the model library).
- Implement `ModelSelectionView` showing the models and a “Download” action (no real download yet).
- Persist selection intent to `UserDefaults`.
- Run end-to-end; log selection events and navigation flows.

 - Status: Done (2025-08-29)
 - Run log snippet (selection flow):
 ```
 app: { event: "launch", build: "1.0 (1)" }
 app: { event: "leap:sdkLinked", sdkVersion: "unknown" }
 ui: { event: "rootAppear" }
 ui: { event: "select", modelSlug: "qwen-0.6b" }
 ```

Phase 3 — Download Flow (Mock, E2E)
- Implement `ModelDownloadService` with a mock downloader to simulate progress and completion; wire to the UI progress.
- Exercise cancel, retry, and error states with mock injections; log all state transitions.
- Run end-to-end in simulator to validate UX and state handling.

- Status: Done (2025-08-29) — validated on iPhone 16 Pro simulator
- Run log snippet (mock download + retry):
```
app: { event: "launch", build: "1.0 (1)" }
app: { event: "leap:sdkLinked", sdkVersion: "unknown" }
ui: { event: "rootAppear" }
download: { event: "resolve", modelSlug: "qwen-0.6b", quant: "qwen-0.6b-20250610-8da4w" }
download: { event: "progress", pct: 20 }
download: { event: "progress", pct: 50 }
download: { event: "failed", error: "network.transient" }
download: { event: "retry" }
download: { event: "progress", pct: 20 }
download: { event: "progress", pct: 50 }
download: { event: "progress", pct: 80 }
download: { event: "complete" }
```

Phase 4 — Real Download Integration (E2E)
- Replace mock with real downloads. For MVP we use public HTTPS bundle URLs from the Leap Model Library (no API key required). Inline progress + cancel in the catalog list.
- Persist downloaded model local URL.
- Add storage checks and user-friendly errors; log progress ticks at ~10% intervals and errors verbosely.
- Run end-to-end; confirm file presence post-download.

- Status: Done (2025-08-29) — validated on iPhone 16 Pro simulator
- Run log snippet (real download inline):
```
app: { event: "launch", build: "1.0 (1)" }
ui: { event: "rootAppear" }
download: { event: "resolve", modelSlug: "lfm2-350m" }
download: { event: "progress", pct: 20 }
download: { event: "progress", pct: 50 }
download: { event: "progress", pct: 80 }
download: { event: "complete", modelSlug: "lfm2-350m", localPath: ".../LFM2-350M-8da4w...bundle" }
```

Phase 5 — Runtime Load & Chat (E2E)
- Implement `ModelRuntimeService` using `Leap.load(url:)` to create a reusable `ModelRunner`.
- Create a `Conversation` on demand and integrate with `ChatStore`.
- Implement `ChatView` input and message list; stream tokens using `generateResponse` and update UI incrementally.
- Log: model load start/end, memory warnings, token streaming start/stop, completion reasons, and usage stats when available.
- Run end-to-end with a small model to validate streaming.

- Status: **BLOCKED** (2025-08-29) — ExecuTorch Error 34 "Failed to open bundle"
- Issue: LeapSDK's ExecuTorch backend cannot load the downloaded model files (LFM2-350M) 
- Error occurs on both iOS Simulator (ARM64) and physical device (iPhone)
- Model file appears valid: 302MB, proper .pte format, correct bundle structure, readable permissions
- Research indicates Error 34 is a model format compatibility issue with ExecuTorch runtime
- Potential causes: model compiled with incompatible ExecuTorch version, corrupted download, or LeapSDK version mismatch
- Next steps: Contact Liquid AI support for model compatibility, try different models, or investigate LeapSDK debug builds

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

Example log lines (format guidelines)
```
app: { event: "launch", sdkVersion: "0.5.0", build: "###" }
download: { event: "resolve", modelSlug: "qwen-0.6b", quant: "qwen-0.6b-20250610-8da4w" }
download: { event: "progress", modelSlug: "qwen-0.6b", pct: 35 }
download: { event: "complete", modelSlug: "qwen-0.6b", localPath: ".../qwen3-0_6b_8da4w_4096.bundle" }
runtime: { event: "load:start", url: "bundle://..." }
runtime: { event: "load:success", tokenPerSecond: 24.3 }
runtime: { event: "stream:start" }
runtime: { event: "stream:complete", tokens: 124, finishReason: "stop" }
ui: { event: "send", chars: 42 }
```

## Testing & Validation
- After each phase, execute simulator automation to detect compile/runtime issues:
  - List available simulators and choose a recent iPhone runtime.
  - Build for the selected simulator and run the app.
  - Capture console output and validate presence of expected log markers (`app`, `download`, `runtime`, `ui`).
- Validate first-run flow, download progress, successful `Leap.load`, and streaming responses using small prompts.
- Periodically build to device for performance checks once download/runtime phases are complete.

### Simulator Automation (xcodebuildmcp)
We will use our simulator automation helper to run and validate after each phase:
- List simulators: `list_sims`
- Build & run on simulator: `build_run_sim` (workspace/project path, scheme, simulatorName or simulatorId)
- Open Simulator app when needed: `open_sim`
- Launch installed app explicitly: `launch_app_sim` (bundleId)
- Capture logs during runs: `start_sim_log_cap` / `stop_sim_log_cap`
- Obtain simulator app path if needed: `get_sim_app_path`

We will assert that log output contains the expected structured markers defined above for the current phase.

### Device Performance Validation
- After Phase 5 (Runtime & Chat), perform a device build and test run to measure token speed and memory behavior.
- If available, capture `runtime` logs with token/sec statistics and any memory warnings. Address regressions before continuing.

## Open Questions / Assumptions
- Leap Model Downloader module import path: docs show `import LeapModelDownloader`. We assume it’s available via the Leap SPM or a companion package; if separate, we’ll add its SPM as well.
- Exact model slugs/quantization IDs will be confirmed from the model library at implementation time.

## References
- Leap iOS Quick Start — [link](https://leap.liquid.ai/docs/edge-sdk/ios/ios-quick-start-guide)
- Leap iOS SDK repo — [link](https://github.com/Liquid4All/leap-ios?tab=readme-ov-file)
- Leap Model Library — [link](https://leap.liquid.ai/models)
