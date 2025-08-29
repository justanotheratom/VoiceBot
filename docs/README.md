# lfm2 iOS — Onboarding & Run Guide (Phase 0)

## Overview
This repository contains an iOS SwiftUI application scaffolded for iOS 17.2+. Phase 0 is complete:
- App builds and runs on Simulator.
- Root view shows "Hello lfm2".
- Unified logging via `os.Logger` with subsystem `com.oneoffrepo.lfm2onios` and categories `app`, `download`, `runtime`, `ui`.

## Prerequisites
- Xcode 15+ (with iOS 17.2+ SDK; tests also run on iOS 18.x simulators)
- macOS with command line tools installed

## Project Structure
- `lfm2onios/` — App target sources (entry point, logging)
- `lfm2oniosPackage/` — Swift Package with feature code (`ContentView`)
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
```
If Console filtering hides structured logs, you can also see stdout prints in Xcode's debug console.

## Key Files
- `lfm2onios/lfm2oniosApp.swift` — App entry point; emits launch log and attaches UI appear log.
- `lfm2onios/Logging.swift` — Logging scaffolding via `os.Logger`, with legacy `os_log` and print fallbacks.
- `lfm2oniosPackage/Sources/lfm2oniosFeature/ContentView.swift` — Displays "Hello lfm2".

## Next Phase (Preview)
Phase 1 will add the Leap iOS SDK via SPM and log successful linkage at startup. See `docs/PRD.md` for the phased plan.
