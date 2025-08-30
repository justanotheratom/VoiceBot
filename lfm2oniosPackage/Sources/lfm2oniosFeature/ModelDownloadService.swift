import Foundation
import LeapSDK
@preconcurrency import LeapModelDownloader

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
        print("download: { event: \"ENTRY\", modelSlug: \"\(entry.slug)\" }")
        print("download: { event: \"resolve\", modelSlug: \"\(entry.slug)\" }")

        // Parse the filename from the download URL
        guard let urlString = entry.downloadURLString,
              let filename = _extractFilename(from: urlString) else {
            print("download: { event: \"failed\", error: \"invalidURL\", url: \"\(entry.downloadURLString ?? "nil")\" }")
            throw ModelDownloadError.invalidURL
        }
        
        print("download: { event: \"creatingHuggingFaceModel\", filename: \"\(filename)\" }")
        
        // Create HuggingFace downloadable model
        let hfModel = HuggingFaceDownloadableModel(
            ownerName: "LiquidAI",
            repoName: "LeapBundles", 
            filename: filename
        )
        
        print("download: { event: \"startingLeapDownload\", ownerName: \"LiquidAI\", repoName: \"LeapBundles\", filename: \"\(filename)\" }")
        
        // Use LeapModelDownloader
        do {
            let result = try await _downloadWithLeapDownloader(model: hfModel, progress: progress)
            let storage = ModelStorageService()
            
            // Move to expected location for consistency with storage service
            let expectedURL = try storage.expectedBundleURL(for: entry)
            let fm = FileManager.default
            
            // Remove existing if present
            if fm.fileExists(atPath: expectedURL.path) {
                try fm.removeItem(at: expectedURL)
            }
            
            // Create parent directory if needed
            try fm.createDirectory(at: expectedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            
            // Move downloaded bundle to expected location
            try fm.moveItem(at: result, to: expectedURL)
            
            print("download: { event: \"complete\", modelSlug: \"\(entry.slug)\", localPath: \"\(expectedURL.path)\" }")
            return ModelDownloadResult(localURL: expectedURL)
        } catch {
            print("download: { event: \"failed\", modelSlug: \"\(entry.slug)\", error: \"\(String(describing: error))\" }")
            throw ModelDownloadError.underlying("LeapModelDownloader failed: \(error.localizedDescription)")
        }
    }
    
    private func _downloadWithLeapDownloader(model: HuggingFaceDownloadableModel, progress: @Sendable @escaping (Double) -> Void) async throws -> URL {
        print("download: { event: \"creatingDownloader\", model: \"\(model.filename)\" }")
        
        // Create a LeapModelDownloader instance  
        let downloader = ModelDownloader()
        
        print("download: { event: \"requestingDownload\", model: \"\(model.filename)\" }")
        
        // Start the download request
        downloader.requestDownloadModel(model)
        
        // Poll for progress updates
        var lastProgress: Double = 0
        while true {
            let status = await downloader.queryStatus(model)
            
            switch status {
            case .notOnLocal:
                print("download: { event: \"statusNotOnLocal\", model: \"\(model.filename)\" }")
                // Continue polling - download may still be starting
                try await Task.sleep(for: .milliseconds(500))
                
            case .downloadInProgress(let currentProgress):
                if currentProgress != lastProgress {
                    lastProgress = currentProgress
                    progress(currentProgress)
                    print("download: { event: \"progress\", model: \"\(model.filename)\", progress: \(Int(currentProgress * 100))% }")
                }
                try await Task.sleep(for: .milliseconds(200)) // Poll every 200ms
                
            case .downloaded:
                progress(1.0)
                print("download: { event: \"statusDownloaded\", model: \"\(model.filename)\" }")
                let url = downloader.getModelFile(model)
                print("download: { event: \"leapDownloadSuccess\", url: \"\(url.path)\" }")
                return url
                
            @unknown default:
                print("download: { event: \"unknownStatus\", model: \"\(model.filename)\" }")
                try await Task.sleep(for: .milliseconds(500))
            }
            
            // Check for task cancellation
            if Task.isCancelled {
                throw ModelDownloadError.cancelled
            }
        }
    }
}

// MARK: - Helper functions

private func _extractFilename(from urlString: String) -> String? {
    // Extract filename from HuggingFace URL
    // URL format: https://huggingface.co/LiquidAI/LeapBundles/resolve/main/LFM2-350M-8da4w_output_8da8w-seq_4096.bundle?download=true
    guard let url = URL(string: urlString) else { return nil }
    
    let pathComponents = url.pathComponents
    // Find the component that ends with .bundle
    for component in pathComponents.reversed() {
        if component.hasSuffix(".bundle") {
            return component
        }
    }
    
    return nil
}

