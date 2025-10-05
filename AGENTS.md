# Repository Guidelines

## Project Structure & Module Organization
Keep feature work inside `VoiceBotPackage/Sources/VoiceBotFeature/`; add assets via a `Resources/` folder processed in `Package.swift`. Unit tests live in `VoiceBotPackage/Tests/VoiceBotFeatureTests/`, UI automation in `VoiceBotUITests/`, configuration under `Config/*.xcconfig`, and the app shell in `VoiceBot/` (entry point plus shared assets).

## Build, Test, and Development Commands
- `open VoiceBot.xcworkspace` — launch the workspace in Xcode; use the `VoiceBot` scheme.
- `xcodebuild -workspace VoiceBot.xcworkspace -scheme VoiceBot -destination 'name=iPhone 16' build` — mirrors CI builds.
- `xcodebuild -workspace VoiceBot.xcworkspace -scheme VoiceBot -destination 'name=iPhone 16' test` — runs the test plan (unit + UI where configured).
- `swift test --package-path VoiceBotPackage` — fast Swift Testing loop while iterating on the package.

## Coding Style & Naming Conventions
Swift 6.1 strict concurrency is mandatory: use async/await, actors, and `@MainActor` isolation as needed. Stick to SwiftUI-native data flow—`@State`, `@Binding`, and `@Observable` types—rather than adding view models. Format with Xcode defaults (4-space indentation, trailing commas where SwiftFormat would place them) and prefer `UpperCamelCase` types with `lowerCamelCase` members. Keep views stateless where possible, favor `struct` over `class`, and express states via enums with associated values.

## Testing Guidelines
Write new coverage with Swift Testing macros (`@Test`, `#expect`, `#require`) in `VoiceBotFeatureTests.swift`; mirror the existing nine-case suite. Name tests for behavior (`test_downloadProgressUpdates()`), isolate services for unit work, and extend `VoiceBotUITests/` for UI regressions. Run `xcodebuild ... test` before merging and preserve a zero-failure CI baseline.

## Commit & Pull Request Guidelines
Follow the established short, imperative summaries seen in `git log` (e.g., "Remove UI test data seeding utilities"). Group related changes per commit and avoid WIP noise. Pull requests should describe the change, note impacted services or screens, link associated issues, and attach relevant screenshots or simulator videos for UI work. Confirm local builds and tests in the PR description so reviewers can focus on behavior.

## Simulator Smoke Test (Manual)
Use XcodeBuildMCP to refresh the iPhone 16 simulator quickly when you need an interactive sanity check.
- `npx xcodebuildmcp list_sims` → copy the iPhone 16 UUID (repository automation assumes iOS 18.5 images).
- `npx xcodebuildmcp boot_sim --simulatorUuid <UUID>` and `npx xcodebuildmcp open_sim` to surface the device.
- `npx xcodebuildmcp build_sim --workspace VoiceBot.xcworkspace --scheme VoiceBot --simulatorId <UUID>` to compile the latest sources.
- `npx xcodebuildmcp get_sim_app_path --workspace VoiceBot.xcworkspace --scheme VoiceBot --platform 'iOS Simulator' --simulatorId <UUID>` → copy the reported `.app` path, then run `npx xcodebuildmcp install_app_sim --simulatorUuid <UUID> --appPath <APP_PATH>`.
- `npx xcodebuildmcp launch_app_sim --simulatorUuid <UUID> --bundleId com.oneoffrepo.VoiceBot` to start the app; the first screen should show "Select Model" cards.
- Download "LFM2 350M" (`describe_ui` + `tap`), wait for the progress bar to reach 100%, then `tap` the cancel button to return to chat.
- Use `tap` on the message field, `type_text --text "Hello simulator test!"`, and `tap` the send button; confirm the assistant replies and the input clears.
- Re-run `describe_ui` to ensure the send button is disabled with an empty field, then stop the app if desired (`stop_app_sim`).

## Configuration Tips
Align new build settings with the xcconfig files rather than editing project files directly. When introducing external assets or model bundles, document the expected location under `Application Support/Models/` and keep secrets out of source control.
