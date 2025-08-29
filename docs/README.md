# lfm2 iOS — Onboarding & Run Guide (Phase 3)

## Overview
This repository contains an iOS SwiftUI application scaffolded for iOS 17.2+. Phase 0–3 are complete:
- App builds and runs on Simulator (tested on iPhone 16 Pro).
- Phase 2 adds a curated model catalog and selection UI with persistence.
- Phase 3 adds a mock download flow with progress, cancel, failure, and retry handling.
- Unified logging via `os.Logger` with subsystem `com.oneoffrepo.lfm2onios` and categories `app`, `download`, `runtime`, `ui`.
- Leap iOS SDK (v0.5.0) integrated via SPM and linkage verified at startup.

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

### Expected UI (Phase 3)
- First run shows `ModelSelectionView` with 3 curated models and a "Download" button.
- Tap "Download" on a model (e.g., TinyLM ~1B) to start a mock download.
- The first attempt will simulate a transient failure; tap "Retry" to continue.
- On completion, the app navigates to a stub `Chat` screen showing the selected model.
- "Switch Model" on the chat screen clears the selection and returns to the catalog.

### Expected Logs
Unified logging markers (filter by subsystem `com.oneoffrepo.lfm2onios`):
```
app: { event: "launch", build: "1.0 (1)" }
app: { event: "leap:sdkLinked", sdkVersion: "unknown" }
ui: { event: "rootAppear" }
download: { event: "resolve", modelSlug: "tiny-1b", quant: "-" }
download: { event: "progress", pct: 40 }
download: { event: "failed", error: "network.transient" }
download: { event: "retry" }
download: { event: "complete" }
```
If Console filtering hides structured logs, you can also see stdout prints in Xcode's debug console.

Note: `sdkVersion` may be reported as "unknown" if the embedded binary does not expose a marketing version through its bundle. This still confirms linkage.

## Key Files
- `lfm2onios/lfm2oniosApp.swift` — App entry point; emits launch log and attaches UI appear log.
- `lfm2onios/Logging.swift` — Logging scaffolding via `os.Logger`, with legacy `os_log` and print fallbacks. Emits Leap SDK linkage status on startup.
- `lfm2oniosPackage/Sources/lfm2oniosFeature/ContentView.swift` — Routes between `ModelSelectionView`, download progress view, and stub `Chat` view; loads/saves selection.
- `lfm2oniosPackage/Sources/lfm2oniosFeature/ModelCatalog.swift` — Curated list of models and metadata.
- `lfm2oniosPackage/Sources/lfm2oniosFeature/ModelSelectionView.swift` — Model selection UI.
- `lfm2oniosPackage/Sources/lfm2oniosFeature/PersistenceService.swift` — Persists `SelectedModel` in `UserDefaults`.
- `lfm2oniosPackage/Sources/lfm2oniosFeature/LeapIntegration.swift` — Helper for checking Leap SDK linkage and version string.
- `lfm2oniosPackage/Sources/lfm2oniosFeature/ModelDownloadService.swift` — Mock download service (`MockModelDownloadService`) and `DownloadState`.
- `lfm2oniosPackage/Sources/lfm2oniosFeature/DownloadProgressView.swift` — SwiftUI component for progress, retry, and cancel.
- `lfm2oniosPackage/Sources/lfm2oniosFeature/FeatureLogger.swift` — Package-level logger for categories.
- `lfm2oniosPackage/Tests/lfm2oniosFeatureTests/MockModelDownloadServiceTests.swift` — Swift Testing coverage for progress, cancel, and retry.

## Next Phase (Preview)
Phase 4 will integrate the real Leap model downloader APIs and replace the mock while keeping the same UI/UX. See `docs/PRD.md` for details.

## SPM Notes (Leap SDK)
- Package URL: `https://github.com/Liquid4All/leap-ios.git`
- Version: `from: 0.5.0`
- Product to link: `LeapSDK`
- Optional companion for downloads (used in Phase 4): `LeapModelDownloader`

### Package Testing Note (macOS)
The Swift package declares `.macOS(.v12)` to satisfy Leap binary requirements so package tests can run locally. This does not change the iOS deployment target.
