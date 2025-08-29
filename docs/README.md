# lfm2 iOS — Onboarding & Run Guide (Phase 2)

## Overview
This repository contains an iOS SwiftUI application scaffolded for iOS 17.2+. Phase 0–2 are complete:
- App builds and runs on Simulator (iPhone 16).
- Phase 2 adds a curated model catalog and selection UI with persistence.
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

## Running in Simulator
1. Open the workspace:
   - `lfm2onios.xcworkspace`
2. Select scheme `lfm2onios` and an iPhone simulator (e.g., iPhone 16).
3. Run (Cmd+R).

### Expected UI (Phase 2)
- First run shows `ModelSelectionView` with 3 curated models and a "Download" button.
- Tapping "Download" persists the selection and navigates to a stub `Chat` screen.
- "Switch Model" on the chat screen clears the selection and returns to the catalog.

### Expected Logs
Unified logging markers (filter by subsystem `com.oneoffrepo.lfm2onios`):
```
app: { event: "launch", build: "1.0 (1)" }
app: { event: "leap:sdkLinked", sdkVersion: "unknown" }
ui: { event: "rootAppear" }
ui: { event: "select", modelSlug: "qwen-0.6b" }
```
If Console filtering hides structured logs, you can also see stdout prints in Xcode's debug console.

Note: `sdkVersion` may be reported as "unknown" if the embedded binary does not expose a marketing version through its bundle. This still confirms linkage.

## Key Files
- `lfm2onios/lfm2oniosApp.swift` — App entry point; emits launch log and attaches UI appear log.
- `lfm2onios/Logging.swift` — Logging scaffolding via `os.Logger`, with legacy `os_log` and print fallbacks. Emits Leap SDK linkage status on startup.
- `lfm2oniosPackage/Sources/lfm2oniosFeature/ContentView.swift` — Routes between `ModelSelectionView` and a stub `Chat` view; loads/saves selection.
- `lfm2oniosPackage/Sources/lfm2oniosFeature/ModelCatalog.swift` — Curated list of models and metadata.
- `lfm2oniosPackage/Sources/lfm2oniosFeature/ModelSelectionView.swift` — Model selection UI.
- `lfm2oniosPackage/Sources/lfm2oniosFeature/PersistenceService.swift` — Persists `SelectedModel` in `UserDefaults`.
- `lfm2oniosPackage/Sources/lfm2oniosFeature/LeapIntegration.swift` — Helper for checking Leap SDK linkage and version string.

## Next Phase (Preview)
Phase 3 will add a mock download flow with progress and error states to validate UX. See `docs/PRD.md` for the phased plan.

## SPM Notes (Leap SDK)
- Package URL: `https://github.com/Liquid4All/leap-ios.git`
- Version: `from: 0.5.0`
- Product to link: `LeapSDK`
- Optional companion for downloads (used in Phase 4): `LeapModelDownloader`

### Package Testing Note (macOS)
The Swift package declares `.macOS(.v12)` to satisfy Leap binary requirements so package tests can run locally. This does not change the iOS deployment target.
