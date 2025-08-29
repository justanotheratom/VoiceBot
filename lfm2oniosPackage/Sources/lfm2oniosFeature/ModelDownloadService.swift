import Foundation

#if canImport(LeapSDK)
import LeapSDK
#endif

#if canImport(LeapModelDownloader)
import LeapModelDownloader
#endif

public struct ModelDownloadResult: Sendable {
    public let localURL: URL
}

public protocol ModelDownloadServicing: Sendable {
    func downloadModel(
        entry: ModelCatalogEntry,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> ModelDownloadResult
}

public enum ModelDownloadError: Error, Sendable {
    case cancelled
    case insufficientStorage
    case underlying(String)
}

public struct ModelDownloadService: ModelDownloadServicing {
    public init() {}

    public func downloadModel(
        entry: ModelCatalogEntry,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> ModelDownloadResult {
        print("download: { event: \"resolve\", modelSlug: \"\(entry.slug)\" }")

        #if canImport(LeapModelDownloader)
        // Real integration using Leap Model Downloader
        do {
            // NOTE: API surface is assumed from docs and may differ slightly.
            // Replace with exact calls if available in your environment.
            let resolved: Any
            if let quant = entry.quantizationSlug, !quant.isEmpty {
                // Hypothetical quantized resolution path
                resolved = try await _resolveLeapModel(slug: entry.slug, quantizationSlug: quant)
            } else {
                resolved = try await _resolveLeapModel(slug: entry.slug, quantizationSlug: nil)
            }

            // Start download and bridge progress callbacks to our closure
            let localURL = try await _downloadResolvedModel(resolved: resolved) { pct in
                // Throttle to ~10% steps
                progress(pct)
                if Int(pct * 100) % 10 == 0 {
                    print("download: { event: \"progress\", pct: \(Int(pct * 100)) }")
                }
            }
            print("download: { event: \"complete\", modelSlug: \"\(entry.slug)\", localPath: \"\(localURL.path)\" }")
            return ModelDownloadResult(localURL: localURL)
        } catch {
            print("download: { event: \"failed\", error: \"\(String(describing: error))\" }")
            throw ModelDownloadError.underlying(String(describing: error))
        }
        #else
        // Mock fallback: simulate download and create a placeholder bundle directory
        let totalSteps = 20
        for step in 1...totalSteps {
            try await Task.sleep(for: .milliseconds(150))
            try Task.checkCancellation()
            let pct = Double(step) / Double(totalSteps)
            progress(pct)
            if step % 2 == 0 {
                print("download: { event: \"progress\", pct: \(Int(pct * 100)) }")
            }
        }

        // Simulate creating a local bundle URL under Application Support
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let bundleName = _preferredBundleName(for: entry)
        let bundleURL = appSupport.appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(bundleName, isDirectory: true)

        if !fm.fileExists(atPath: bundleURL.path) {
            try fm.createDirectory(at: bundleURL, withIntermediateDirectories: true)
            // Write a small marker file
            let markerURL = bundleURL.appendingPathComponent(".lfm2-placeholder.txt")
            try "placeholder for \(entry.displayName)".data(using: .utf8)!.write(to: markerURL)
        }
        print("download: { event: \"complete\", modelSlug: \"\(entry.slug)\", localPath: \"\(bundleURL.path)\" }")
        return ModelDownloadResult(localURL: bundleURL)
        #endif
    }
}

// MARK: - Private helpers

private func _preferredBundleName(for entry: ModelCatalogEntry) -> String {
    if let q = entry.quantizationSlug, !q.isEmpty {
        return "\(q).bundle"
    }
    return "\(entry.slug).bundle"
}

#if canImport(LeapModelDownloader)
// These shim functions isolate types from the main service implementation to keep compilation clean.
@Sendable
private func _resolveLeapModel(slug: String, quantizationSlug: String?) async throws -> Any {
    // Hypothetical resolver: replace with real API from LeapModelDownloader
    // e.g., return try await LeapDownloadableModel.resolve(slug: slug, quantization: quantizationSlug)
    struct Unimplemented: Error {}
    throw Unimplemented()
}

@Sendable
private func _downloadResolvedModel(
    resolved: Any,
    progress: @escaping (Double) -> Void
) async throws -> URL {
    // Hypothetical download API usage
    // e.g., for try await downloader.download(model: resolved) { progress($0.fractionCompleted) }
    struct Unimplemented: Error {}
    throw Unimplemented()
}
#endif


