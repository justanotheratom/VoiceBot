import SwiftUI
import lfm2oniosFeature

@main
struct lfm2oniosApp: App {
    init() {
        print("app: { event: \"launch\", build: \"1.0 (1)\" }")
        // Handle automation flags as early as possible so ContentView sees persisted state
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--ui-test-clean-reset") {
            let persistence = PersistenceService()
            persistence.clearSelectedModel()
            print("app: { event: \"cleanReset:init\" }")
        }
        if let idx = args.firstIndex(of: "--ui-test-autoselect") {
            let slug = args.indices.contains(idx + 1) ? args[idx + 1] : "lfm2-350m"
            if let entry = ModelCatalog.entry(forSlug: slug) {
                let storage = ModelStorageService()
                do {
                    let bundleURL = try storage.expectedBundleURL(for: entry)
                    try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
                    let model = SelectedModel(
                        slug: entry.slug,
                        displayName: entry.displayName,
                        provider: entry.provider,
                        quantizationSlug: entry.quantizationSlug,
                        localURL: bundleURL
                    )
                    let persistence = PersistenceService()
                    persistence.saveSelectedModel(model)
                    print("app: { event: \"autoSelect:init\", modelSlug: \"\(entry.slug)\" }")
                } catch {
                    print("app: { event: \"autoSelect:initFailed\", error: \"\(String(describing: error))\" }")
                }
            }
        }
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    print("ui: { event: \"rootAppear\" }")
                    // Optional clean reset for automated runs
                    if ProcessInfo.processInfo.arguments.contains("--ui-test-clean-reset") {
                        let persistence = PersistenceService()
                        persistence.clearSelectedModel()
                        print("app: { event: \"cleanReset\" }")
                    }

                    // Optional auto-select for automated runs: --ui-test-autoselect <slug>
                    let args = ProcessInfo.processInfo.arguments
                    if let idx = args.firstIndex(of: "--ui-test-autoselect") {
                        let slug = args.indices.contains(idx + 1) ? args[idx + 1] : "lfm2-350m"
                        if let entry = ModelCatalog.entry(forSlug: slug) {
                            let storage = ModelStorageService()
                            do {
                                let bundleURL = try storage.expectedBundleURL(for: entry)
                                // Ensure dummy bundle folder exists so loaders pass file check
                                try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
                                let model = SelectedModel(
                                    slug: entry.slug,
                                    displayName: entry.displayName,
                                    provider: entry.provider,
                                    quantizationSlug: entry.quantizationSlug,
                                    localURL: bundleURL
                                )
                                let persistence = PersistenceService()
                                persistence.saveSelectedModel(model)
                                print("app: { event: \"autoSelect\", modelSlug: \"\(entry.slug)\" }")
                            } catch {
                                print("app: { event: \"autoSelectFailed\", error: \"\(String(describing: error))\" }")
                            }
                        }
                    }
                }
        }
    }
}
