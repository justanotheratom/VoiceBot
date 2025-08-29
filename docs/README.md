# lfm2 iOS — Onboarding & Run Guide (Phase 1)

## Overview
This repository contains an iOS SwiftUI application scaffolded for iOS 17.2+. Phase 0 and Phase 1 are complete:
- App builds and runs on Simulator.
- Root view shows "Hello lfm2".
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

### Expected UI
You should see a simple screen with the text: `Hello lfm2`.

### Expected Logs
Unified logging markers (filter by subsystem `com.oneoffrepo.lfm2onios`):
```
app: { event: "launch", build: "1.0 (1)" }
app: { event: "leap:sdkLinked", sdkVersion: "unknown" }
```
If Console filtering hides structured logs, you can also see stdout prints in Xcode's debug console.

Note: `sdkVersion` may be reported as "unknown" if the embedded binary does not expose a marketing version through its bundle. This still confirms linkage.

## Key Files
- `lfm2onios/lfm2oniosApp.swift` — App entry point; emits launch log and attaches UI appear log.
- `lfm2onios/Logging.swift` — Logging scaffolding via `os.Logger`, with legacy `os_log` and print fallbacks. Emits Leap SDK linkage status on startup.
- `lfm2oniosPackage/Sources/lfm2oniosFeature/ContentView.swift` — Displays "Hello lfm2".
- `lfm2oniosPackage/Sources/lfm2oniosFeature/LeapIntegration.swift` — Helper for checking Leap SDK linkage and version string.

## Next Phase (Preview)
Phase 2 will add a curated Model Catalog and selection UI (no real download yet). See `docs/PRD.md` for the phased plan.

## SPM Notes (Leap SDK)
- Package URL: `https://github.com/Liquid4All/leap-ios.git`
- Version: `from: 0.5.0`
- Product to link: `LeapSDK`
- Optional companion for downloads (used in Phase 4): `LeapModelDownloader`
