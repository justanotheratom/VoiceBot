import Foundation
import ZIPFoundation
import LeapSDK

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
        // Try to use LeapModelDownloader first for official Leap models
        do {
            print("download: { event: \"attemptingLeapDownloader\", modelSlug: \"\(entry.slug)\" }")
            // Note: We'd need to check the correct API for LeapModelDownloader here
            // For now, fall through to URL-based download
            throw ModelDownloadError.downloaderUnavailable
        } catch {
            print("download: { event: \"leapDownloaderFailed\", error: \"\(String(describing: error))\" }")
            // Fall through to URL-based download
        }
        #endif
        
        // URL-based download path - downloads real Leap bundles from HuggingFace
        guard let urlString = entry.downloadURLString, let url = URL(string: urlString) else {
            throw ModelDownloadError.invalidURL
        }
        
        print("download: { event: \"startingURLDownload\", url: \"\(urlString)\" }")
        
        // Download to a temporary file first
        let tempFile = try await _downloadTempFile(from: url, progress: progress)
        
        // Extract and place in the proper location
        let storage = ModelStorageService()
        let fm = FileManager.default
        let finalURL: URL
        
        print("download: { event: \"processingArchive\", tempFile: \"\(tempFile.path)\", tempFileSize: \(try fm.attributesOfItem(atPath: tempFile.path)[.size] as? Int ?? -1) }")
        
        // Try to extract as ZIP archive first
        do {
            finalURL = try storage.extractArchive(tempFile, for: entry)
            print("download: { event: \"extracted\", from: \"\(tempFile.path)\", to: \"\(finalURL.path)\" }")
        } catch {
            print("download: { event: \"extractionFailed\", error: \"\(String(describing: error))\", attemptingDirectMove: true }")
            // If extraction fails, assume it's already a bundle and move it directly
            let dest = try storage.expectedBundleURL(for: entry)
            print("download: { event: \"directMove\", destination: \"\(dest.path)\" }")
            
            if fm.fileExists(atPath: dest.path) { 
                print("download: { event: \"removingExisting\", path: \"\(dest.path)\" }")
                try fm.removeItem(at: dest) 
            }
            
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: tempFile, to: dest)
            finalURL = dest
            print("download: { event: \"moved\", from: \"\(tempFile.path)\", to: \"\(finalURL.path)\" }")
        }
        
        // Verify the downloaded bundle is valid
        print("download: { event: \"verifyingBundle\", path: \"\(finalURL.path)\" }")
        let bundleContents = try fm.contentsOfDirectory(atPath: finalURL.path)
        guard !bundleContents.isEmpty else {
            print("download: { event: \"verificationFailed\", reason: \"emptyBundle\", path: \"\(finalURL.path)\" }")
            throw ModelDownloadError.underlying("Downloaded bundle is empty")
        }
        
        print("download: { event: \"complete\", modelSlug: \"\(entry.slug)\", localPath: \"\(finalURL.path)\", files: \(bundleContents.count), fileList: \(bundleContents.prefix(5)) }")
        return ModelDownloadResult(localURL: finalURL)
    }
}

// MARK: - URLSession-based download implementation

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

private func _downloadTempFile(from remoteURL: URL, progress: @escaping (Double) -> Void) async throws -> URL {
    let fm = FileManager.default
    let tempDir = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let destURL = tempDir.appendingPathComponent(UUID().uuidString)

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

