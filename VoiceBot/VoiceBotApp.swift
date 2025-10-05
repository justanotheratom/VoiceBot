import SwiftUI
import VoiceBotFeature

@main
struct VoiceBotApp: App {
    init() {
        AppLogger.logAppLaunch(build: "1.0 (1)")
        // Handle automation flags as early as possible so ContentView sees persisted state
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--ui-test-clean-reset") {
            let persistence = PersistenceService()
            persistence.clearSelectedModel()
            AppLogger.app().log(event: "cleanReset:init")
        }
        if let idx = args.firstIndex(of: "--ui-test-autoselect") {
            let slug = args.indices.contains(idx + 1) ? args[idx + 1] : "lfm2-350m"
            if let entry = ModelCatalog.entry(forSlug: slug) {
                let storage = ModelStorageService()
                do {
                    let bundleURL = try storage.expectedResourceURL(for: entry)
                    try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
                    let model = SelectedModel(
                        slug: entry.slug,
                        displayName: entry.displayName,
                        provider: entry.provider,
                        quantizationSlug: entry.quantizationSlug,
                        localURL: bundleURL,
                        runtime: entry.runtime,
                        runtimeIdentifier: entry.gemmaMetadata?.assetIdentifier
                    )
                    let persistence = PersistenceService()
                    persistence.saveSelectedModel(model)
                    AppLogger.app().log(event: "autoSelect:init", data: ["modelSlug": entry.slug])
                } catch {
                    AppLogger.app().logError(event: "autoSelect:initFailed", error: error)
                }
            }
        }
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    AppLogger.ui().log(event: "rootAppear")
                    // Optional clean reset for automated runs
                    if ProcessInfo.processInfo.arguments.contains("--ui-test-clean-reset") {
                        let persistence = PersistenceService()
                        persistence.clearSelectedModel()
                        AppLogger.app().log(event: "cleanReset")
                    }

                    // Optional auto-select for automated runs: --ui-test-autoselect <slug>
                    let args = ProcessInfo.processInfo.arguments
                    if let idx = args.firstIndex(of: "--ui-test-autoselect") {
                        let slug = args.indices.contains(idx + 1) ? args[idx + 1] : "lfm2-350m"
                        if let entry = ModelCatalog.entry(forSlug: slug) {
                            let storage = ModelStorageService()
                            do {
                                let bundleURL = try storage.expectedResourceURL(for: entry)
                                // Ensure dummy bundle folder exists so loaders pass file check
                                try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
                                let model = SelectedModel(
                                    slug: entry.slug,
                                    displayName: entry.displayName,
                                    provider: entry.provider,
                                    quantizationSlug: entry.quantizationSlug,
                                    localURL: bundleURL,
                                    runtime: entry.runtime,
                                    runtimeIdentifier: entry.gemmaMetadata?.assetIdentifier
                                )
                                let persistence = PersistenceService()
                                persistence.saveSelectedModel(model)
                                AppLogger.app().log(event: "autoSelect", data: ["modelSlug": entry.slug])
                            } catch {
                                AppLogger.app().logError(event: "autoSelectFailed", error: error)
                            }
                        }
                    }
                }
        }
    }
}
