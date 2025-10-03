# Gemma 3 Support Proposal

## Objective
Extend the existing LFM2 on-device chatbot to support downloading and running Gemma 3 instruction-tuned models using Apple MLX runtime while keeping LFM2 + Leap SDK flows fully functional. The enhancement should let users pick Gemma models from the same catalog UI, manage their assets under Application Support, and stream chat responses through the shared conversation stack.

## Current State Snapshot
- The catalog (`ModelCatalog.swift`) lists only Leap-delivered LFM2 bundles with straight HTTPS URLs and metadata tailored for Leap's bundle format.
- Downloads (`ModelDownloadService`) rely on `LeapModelDownloader` to fetch `.bundle` archives and move them into `ModelStorageService`'s `Models/<slug>.bundle` path.
- `ModelRuntimeService` is an actor around Leap's `ModelRunner`, handling load/stream via `Leap.load(url:)` and `Conversation.generateResponse`.
- Chat flow (e.g., `ChatView`, `ConversationManager`) assumes Leap-backed generation and expects streaming text chunks.

## Research Highlights
- **Gemma sample app** (`~/GitHub/oneoff_repo/gemma3onios`):
  - Uses a `ModelAssetDescriptor` + `ModelDownloadController` stack to fetch Gemma assets from Hugging Face (via the `Hub` Swift package) with checksum and resume support.
  - Stores assets under `Application Support/Models/<identifier>/` (matching our storage location conventions).
  - Streams inference with `GemmaInferenceService`, wrapping `MLXLMCommon.generate` to produce token events from a prepared conversation.
  - Adds MLX dependencies in `Package.swift` (`MLX`, `MLXLLM`, `MLXLMCommon`, `Hub`) and links `sqlite3` as required by MLX runtime.
- **MLX Swift Examples docs** (`https://swiftpackageindex.com/ml-explore/mlx-swift-examples/main/documentation/mlxlmcommon`): highlight the `MLXLMCommon.generate` API and conversation preparation utilities we can reuse for consistent prompt construction and token streaming.

## Proposed Approach
### 1. Catalog & Domain Model Enhancements
- Introduce a `ModelFamily`/`RuntimeKind` enum on `ModelCatalogEntry` to distinguish Leap vs MLX-backed models and allow future additions.
- Extend catalog metadata to capture Gemma-specific descriptors (e.g., Hugging Face repo ID, revision, primary file, estimated size). Persist those details so the download/runtime layers can branch without extra lookups.
- Update `PersistenceService` and `SelectedModel` to persist the runtime kind plus any extra identifier needed to reopen Gemma assets.

### 2. Storage Strategy
- Generalize `ModelStorageService` to support both `.bundle` archives (Leap) and directory/file layouts (Gemma/MLX). Provide helpers:
  - `expectedBundleURL` for Leap bundles (current behavior).
  - `expectedDirectoryURL` / `assetDirectory(for:)` for Gemma identifiers alongside pointer to primary weights/tokenizer.
- Ensure directory creation, deletion, and "is downloaded" checks respect both layouts and avoid accidental removal of shared subdirectories.

### 3. Download Pipeline Abstraction
- Define a `ModelDownloadAdapter` protocol (download, cancel, progress) with concrete implementations:
  - `LeapDownloadAdapter` - wrap existing `ModelDownloadService` logic.
  - `GemmaDownloadAdapter` - port the relevant pieces of `ModelDownloadController`/`ModelStorage` from the sample repo, trimming advanced UI hooks but keeping resume, checksum, and `Hub` powered snapshot downloads.
- Add a coordinator (e.g., `UnifiedModelDownloadService`) that picks the adapter based on `ModelCatalogEntry.runtime` and exposes the current `ModelDownloadServicing` API to views.
- Reuse sample helpers (`ModelAssetDescriptor`, `ModelHubClient`, `HubTokenProvider`) in a new `GemmaRuntime` namespace under `lfm2oniosPackage/Sources/lfm2oniosFeature/`.
- Support progress reporting in the same shape (0...1) to avoid UI churn. Translate file progress metrics into normalized percentages for Gemma downloads.

### 4. Runtime Execution Layer
- Introduce a runtime adapter protocol (e.g., `ModelRuntimeAdapter`) that defines `load(at:)` and `streamResponse(prompt:onToken:)`.
- Keep the existing Leap-specific logic inside a `LeapRuntimeAdapter` (wrapping `Leap.load` and `Conversation.generateResponse`).
- Add a `GemmaRuntimeAdapter` leveraging the sample's `GemmaInferenceService`. Key steps:
  - Build an inference service per Gemma asset that reuses cached `ModelContainer` and shares conversation -> `HubChat` conversion utilities.
  - Convert our internal `Message`/`ChatMessageModel` into the format expected by MLX (likely `[ChatMessage]` with `.system/.user/.assistant`).
  - Normalize streaming callbacks so UI remains agnostic (handle `.token` events only, ignoring prompt token counts unless we want to log them).
- Refactor `ModelRuntimeService` to own a dictionary of adapters keyed by runtime kind or slug, dispatching load/stream to the correct adapter while maintaining cancellation, logging, and concurrency semantics.

### 5. Chat Flow & UI Updates
- Update `ModelCatalog.all` to include Gemma 3 variants (start with 270M IT, optionally larger SKUs once stable). Provide accurate descriptions and sizes.
- Ensure `ModelSelectionView` surfaces Gemma entries, shows download/resume/cancel states, and allows deletion via the generalized storage APIs.
- Extend `ChatView` to show model provenance (e.g., provider badge) and handle runtime-specific errors (e.g., missing tokenizer) gracefully.
- Maintain parity for streaming UX (typing indicator, send-button disable) regardless of runtime.

### 6. Configuration & Build System
- Update `lfm2oniosPackage/Package.swift` with MLX + Hub dependencies and linker flag for `sqlite3`. Assess whether the host app target also needs bridging headers or embedded resources.
- Add xcconfig toggles (e.g., optional Hugging Face token `GEMMA_HF_TOKEN`) following the sample's `HubTokenProvider` strategy, defaulting to empty for public models.
- Document any minimum OS bumps (MLX currently targets iOS 18; verify we can keep iOS 17 compatibility or gate Gemma availability behind runtime checks).

### 7. Diagnostics & Telemetry
- Extend logging categories to tag Gemma download/runtime events (e.g., `download: { runtime: "mlx" ... }`).
- Persist lightweight download metadata (timestamps, file sizes) to aid support.
- Surface user-friendly error banners for common MLX issues (missing weights, incompatible device) mirroring gemma sample messaging.

### 8. Testing & Validation
- Add Swift Testing cases covering:
  - Catalog persistence for new runtime fields.
  - Storage path resolution for Gemma assets.
  - Download adapter behavior (unit-testable pieces using temporary directories and stubbed Hub clients).
  - Runtime adapter input transformation (ensure conversation history produces expected MLX chat messages).
- Provide smoke-script guidance for manual validation (`xcodebuild ...`, simulator steps to send/receive responses on both Leap/Gemma models).

## Risks & Considerations
- **Binary size & build time:** MLX dependencies will increase package size; confirm no App Store constraints.
- **Device support:** MLX currently requires A17/M-series class hardware; we may need to conditionally expose Gemma models based on runtime checks.
- **Download footprint:** Gemma weights are large; ensure disk space checks and clear retry UX.
- **Concurrency & memory:** Running different runtimes side-by-side could exhaust memory; implement unload/teardown paths when switching models.
- **Token management:** Hugging Face rate limits require configurable tokens; provide Info.plist overrides but avoid shipping secrets.

## Implementation Checklist
1. **Domain & Persistence groundwork** *(completed)*
   - Add runtime/model-type metadata to `ModelCatalogEntry`, `SelectedModel`, and persistence migrations.
   - Update catalog definitions with Gemma entries and ensure UI renders provider/runtime hints.
2. **Storage generalization** *(completed)*
   - Extend `ModelStorageService` to compute paths/checks for both bundle and directory assets; update delete/isDownloaded logic accordingly.
   - Migrate existing code paths (downloads, selection) to use the generalized helpers.
3. **Download adapters**
   - Extract current Leap download flow into `LeapDownloadAdapter` satisfying a new `ModelDownloadAdapter` protocol.
   - Port `ModelAssetDescriptor`, `ModelStorage`, `ModelHubClient`, and simplified `ModelDownloadController` from the sample into the package; wrap in `GemmaDownloadAdapter` with normalized progress callbacks.
   - Implement a unified `ModelDownloadService` facade that selects the correct adapter and maintains task cancellation bookkeeping for the UI.
4. **Runtime adapters**
   - Move Leap-specific logic into `LeapRuntimeAdapter` and introduce `GemmaRuntimeAdapter` built on `GemmaInferenceService` (adapted from sample).
   - Refactor `ModelRuntimeService` to route load/stream requests to the active adapter, handle unloading when switching models, and normalize error surfaces.
5. **Chat integration & UX polish**
   - Update `ChatView`, `ConversationManager`, and related types to pass runtime context into streaming (e.g., convert conversation history for Gemma, maintain compatibility with Leap).
   - Add provider/runtime indicators in UI and surface runtime-specific error messages or requirements.
6. **Configuration & build updates**
   - Amend `Package.swift` and xcconfigs with MLX/Hub dependencies, linker settings, and optional HF token plumbing.
   - Document environment variables / Info.plist keys for Gemma token overrides.
7. **Testing & verification**
   - Expand Swift Testing coverage around catalog, storage, and adapter logic.
   - Create manual QA scripts covering mixed-runtime switching, download resume/cancel, and chat streaming on simulator and supported hardware.
8. **Docs & handoff**
   - Update `docs/README.md` and PR templates with Gemma instructions, requirements, and troubleshooting notes.
   - Provide release notes summarizing new capabilities and any device/OS caveats.
