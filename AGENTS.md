# Repository Guidelines

## Project Structure & Module Organization
This workspace keeps the app shell thin while centralizing feature work in Swift Package modules. Prioritize edits in `lfm2oniosPackage/Sources/lfm2oniosFeature/`; add assets via a `Resources/` folder processed in `Package.swift`. Unit tests live beside the package code in `lfm2oniosPackage/Tests/lfm2oniosFeatureTests/`, while UI automation targets sit in `lfm2oniosUITests/`. Configuration is stored in `Config/*.xcconfig`, and the minimal app target (`lfm2onios/`) hosts `lfm2oniosApp.swift` plus shared assets.

## Build, Test, and Development Commands
- `open lfm2onios.xcworkspace` — launch the workspace in Xcode; use the `lfm2onios` scheme.
- `xcodebuild -workspace lfm2onios.xcworkspace -scheme lfm2onios -destination 'name=iPhone 16' build` — command-line build that mirrors CI.
- `xcodebuild -workspace lfm2onios.xcworkspace -scheme lfm2onios -destination 'name=iPhone 16' test` — run the full test plan (unit + UI where configured).
- `swift test --package-path lfm2oniosPackage` — execute Swift Testing targets quickly during package development.

## Coding Style & Naming Conventions
Swift 6.1 strict concurrency is mandatory: use async/await, actors, and `@MainActor` isolation as needed. Stick to SwiftUI-native data flow—`@State`, `@Binding`, and `@Observable` types—rather than adding view models. Format with Xcode defaults (4-space indentation, trailing commas where SwiftFormat would place them) and prefer `UpperCamelCase` types with `lowerCamelCase` members. Keep views stateless where possible, favor `struct` over `class`, and express states via enums with associated values.

## Testing Guidelines
Write new coverage with the Swift Testing macros (`@Test`, `#expect`, `#require`) in `lfm2oniosFeatureTests.swift`, mirroring the existing 9-case suite. Name tests after the behavior under check (`test_downloadProgressUpdates()`), and isolate services for unit coverage. For UI regressions, extend `lfm2oniosUITests/` and run `xcodebuild ... test` before merging. Maintain zero failing tests in CI and include regression cases whenever adding a bug fix.

## Commit & Pull Request Guidelines
Follow the established short, imperative summaries seen in `git log` (e.g., "Remove UI test data seeding utilities"). Group related changes per commit and avoid WIP noise. Pull requests should describe the change, note impacted services or screens, link associated issues, and attach relevant screenshots or simulator videos for UI work. Confirm local builds and tests in the PR description so reviewers can focus on behavior.

## Configuration Tips
Align new build settings with the xcconfig files rather than editing project files directly. When introducing external assets or model bundles, document their expected location under `Application Support/Models/` and ensure any secrets remain out of source control.
