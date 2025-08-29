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
    case downloaderUnavailable
    case invalidURL
}

public struct ModelDownloadService: ModelDownloadServicing {
    public init() {}

    public func downloadModel(
        entry: ModelCatalogEntry,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> ModelDownloadResult {
        print("download: { event: \"resolve\", modelSlug: \"\(entry.slug)\" }")

        #if canImport(LeapModelDownloader)
        // Real integration using Leap Model Downloader (to be wired with actual APIs)
        do {
            let resolved: Any
            if let quant = entry.quantizationSlug, !quant.isEmpty {
                resolved = try await _resolveLeapModel(slug: entry.slug, quantizationSlug: quant)
            } else {
                resolved = try await _resolveLeapModel(slug: entry.slug, quantizationSlug: nil)
            }
            let localURL = try await _downloadResolvedModel(resolved: resolved) { pct in
                progress(pct)
                if Int(pct * 100) % 10 == 0 { print("download: { event: \"progress\", pct: \(Int(pct * 100)) }") }
            }
            print("download: { event: \"complete\", modelSlug: \"\(entry.slug)\", localPath: \"\(localURL.path)\" }")
            return ModelDownloadResult(localURL: localURL)
        } catch {
            print("download: { event: \"failed\", error: \"\(String(describing: error))\" }")
            throw ModelDownloadError.underlying(String(describing: error))
        }
        #else
        // URL-based download path (requires entry.downloadURLString)
        guard let urlString = entry.downloadURLString, let url = URL(string: urlString) else {
            throw ModelDownloadError.downloaderUnavailable
        }
        let localURL = try await _downloadFile(from: url, bundleName: _preferredBundleName(for: entry), progress: progress)
        print("download: { event: \"complete\", modelSlug: \"\(entry.slug)\", localPath: \"\(localURL.path)\" }")
        return ModelDownloadResult(localURL: localURL)
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
private func _resolveLeapModel(slug: String, quantizationSlug: String?) async throws -> Any {
    // Hypothetical resolver: replace with real API from LeapModelDownloader
    // e.g., return try await LeapDownloadableModel.resolve(slug: slug, quantization: quantizationSlug)
    struct Unimplemented: Error {}
    throw Unimplemented()
}

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

// URLSession-based download with progress and cancellation
private final class _DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    nonisolated(unsafe) let progressHandler: (Double) -> Void
    nonisolated(unsafe) var continuation: CheckedContinuation<URL, Error>?
    nonisolated(unsafe) var destinationURL: URL?

    init(progressHandler: @escaping (Double) -> Void) {
        self.progressHandler = progressHandler
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let pct = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler(pct)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let dest = destinationURL else {
            continuation?.resume(throwing: ModelDownloadError.underlying("Missing destination URL"))
            continuation = nil
            return
        }
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.moveItem(at: location, to: dest)
            continuation?.resume(returning: dest)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

private func _downloadFile(from remoteURL: URL, bundleName: String, progress: @escaping (Double) -> Void) async throws -> URL {
    let fm = FileManager.default
    let appSupport = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let modelsDir = appSupport.appendingPathComponent("Models", isDirectory: true)
    if !fm.fileExists(atPath: modelsDir.path) {
        try fm.createDirectory(at: modelsDir, withIntermediateDirectories: true)
    }
    let destURL = modelsDir.appendingPathComponent(bundleName, isDirectory: false)

    let delegate = _DownloadDelegate(progressHandler: { pct in
        progress(pct)
        if Int(pct * 100) % 10 == 0 { print("download: { event: \"progress\", pct: \(Int(pct * 100)) }") }
    })
    let cfg = URLSessionConfiguration.default
    let session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
    let task = session.downloadTask(with: remoteURL)

    return try await withTaskCancellationHandler(operation: {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            delegate.continuation = continuation
            delegate.destinationURL = destURL
            task.resume()
        }
    }, onCancel: {
        task.cancel()
    })
}


