# lfm2 iOS — Onboarding & Run Guide (Phase 4)

## Overview
This repository contains an iOS SwiftUI application scaffolded for iOS 17.2+. Phase 0–4 are complete:
– App builds and runs on Simulator (tested on iPhone 16 Pro).
– Phase 2 adds a curated model catalog and selection UI with persistence.
– Phase 3 added a mock download flow.
– Phase 4 replaces the mock with real downloads of LFM2 bundles (no API key), shows inline progress with cancel, and supports delete for downloaded models.
– Unified logging via `os.Logger` with subsystem `com.oneoffrepo.lfm2onios` and categories `app`, `download`, `runtime`, `ui`.
– Leap iOS SDK (v0.5.0) integrated via SPM and linkage verified at startup.

## Prerequisites
- Xcode 15+ (with iOS 17.2+ SDK; tests also run on iOS 18.x simulators)
- macOS with command line tools installed
- Internet access for SPM to resolve the Leap SDK

## Project Structure
- `lfm2onios/` — App target sources (entry point, logging)
- `lfm2oniosPackage/` — Swift Package with feature code (`ContentView`, `LeapIntegration`)
- `Config/` — Xcode configuration files
- `docs/` — PRD and docs

## Running in Simulator (iPhone 16 Pro)
1. Open the workspace:
   - `lfm2onios.xcworkspace`
2. Select scheme `lfm2onios` and simulator `iPhone 16 Pro`.
3. Run (Cmd+R).

### Expected UI (Phase 4)
– First run shows `ModelSelectionView` with three curated LFM2 models (350M, 700M, 1.2B).
– Tap the download icon to start a real download (from Leap Model Library via HTTPS). Progress appears inline; a cancel icon is available during download.
– After completion, the row shows a downloaded indicator and a delete icon. Selecting a downloaded model persists and navigates to a stub `Chat` screen.
– The `Chat` screen includes a "Switch Model" button that clears selection and returns to the catalog.

### Expected Logs
Unified logging markers (filter by subsystem `com.oneoffrepo.lfm2onios`):
```
app: { event: "launch", build: "1.0 (1)" }
app: { event: "leap:sdkLinked", sdkVersion: "unknown" }
ui: { event: "rootAppear" }
download: { event: "resolve", modelSlug: "lfm2-350m" }
download: { event: "progress", pct: 40 }
download: { event: "failed", error: "network.transient" }
download: { event: "retry" }
download: { event: "complete" }
```
If Console filtering hides structured logs, you can also see stdout prints in Xcode's debug console.

Note: `sdkVersion` may be reported as "unknown" if the embedded binary does not expose a marketing version through its bundle. This still confirms linkage.

## Real Downloads (Phase 4)
The catalog points to the smallest three LFM2 bundles, sourced from the Leap Model Library:
– LFM2 350M
– LFM2 700M
– LFM2 1.2B

Implementation details:
– Real downloads use `URLSession` with a delegate for progress updates and cancellation.
– Files are stored under Application Support: `~/Library/Application Support/<bundle-id>/Models/`.
– The persisted `SelectedModel` includes the local URL; delete removes the bundle directory.
– No API key is required for these public bundle URLs.

To add or change models, edit:
`lfm2oniosPackage/Sources/lfm2oniosFeature/ModelCatalog.swift`
and update the `downloadURLString`, `slug`, `quantizationSlug`, and metadata.

## Key Files
- `lfm2onios/lfm2oniosApp.swift` — App entry point; emits launch log and attaches UI appear log.
- `lfm2onios/Logging.swift` — Logging scaffolding via `os.Logger`, with legacy `os_log` and print fallbacks. Emits Leap SDK linkage status on startup.
- `lfm2oniosPackage/Sources/lfm2oniosFeature/ContentView.swift` — Routes between `ModelSelectionView` and a stub `Chat` view; loads/saves selection.
- `lfm2oniosPackage/Sources/lfm2oniosFeature/ModelCatalog.swift` — Curated list of models and metadata (includes HTTPS bundle URLs).
- `lfm2oniosPackage/Sources/lfm2oniosFeature/ModelSelectionView.swift` — Model selection UI with inline progress, cancel, delete, and downloaded indicator.
- `lfm2oniosPackage/Sources/lfm2oniosFeature/PersistenceService.swift` — Persists `SelectedModel` (including `localURL`) in `UserDefaults`.
- `lfm2oniosPackage/Sources/lfm2oniosFeature/LeapIntegration.swift` — Helper for checking Leap SDK linkage and version string.
- `lfm2oniosPackage/Sources/lfm2oniosFeature/ModelDownloadService.swift` — Real URL download implementation with progress & cancellation.
- `lfm2oniosPackage/Sources/lfm2oniosFeature/ModelStorageService.swift` — Computes bundle locations and handles deletion.
- `lfm2oniosPackage/Tests/lfm2oniosFeatureTests/lfm2oniosFeatureTests.swift` — Basic catalog and persistence tests.

## Next Phase (Preview)
Phase 5 will load a downloaded model with `Leap.load(url:)`, bring up a `Conversation`, and stream tokens into a chat UI. See `docs/PRD.md` for details.

## SPM Notes (Leap SDK)
- Package URL: `https://github.com/Liquid4All/leap-ios.git`
- Version: `from: 0.5.0`
- Product to link: `LeapSDK`
- Optional companion for downloads (used in Phase 4): `LeapModelDownloader`

### Package Testing Note (macOS)
The Swift package declares `.macOS(.v12)` to satisfy Leap binary requirements so package tests can run locally. This does not change the iOS deployment target.
