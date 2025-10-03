import Foundation
import LeapSDK
@preconcurrency import LeapModelDownloader

protocol RuntimeModelDownloadAdapting: Sendable {
    func download(
        entry: ModelCatalogEntry,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> URL
}

struct LeapModelDownloadAdapter: RuntimeModelDownloadAdapting {
    func download(
        entry: ModelCatalogEntry,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> URL {
        print("download: { event: \"ENTRY\", modelSlug: \"\(entry.slug)\" }")
        print("download: { event: \"resolve\", modelSlug: \"\(entry.slug)\" }")

        guard let urlString = entry.downloadURLString,
              let filename = extractFilename(from: urlString) else {
            print("download: { event: \"failed\", error: \"invalidURL\", url: \"\(entry.downloadURLString ?? "nil")\" }")
            throw ModelDownloadError.invalidURL
        }

        print("download: { event: \"creatingHuggingFaceModel\", filename: \"\(filename)\" }")

        let hfModel = HuggingFaceDownloadableModel(
            ownerName: "LiquidAI",
            repoName: "LeapBundles",
            filename: filename
        )

        print("download: { event: \"startingLeapDownload\", ownerName: \"LiquidAI\", repoName: \"LeapBundles\", filename: \"\(filename)\" }")

        do {
            let result = try await downloadWithLeapDownloader(model: hfModel, progress: progress)
            let storage = ModelStorageService()

            let expectedURL = try storage.expectedBundleURL(for: entry)
            let fm = FileManager.default

            if fm.fileExists(atPath: expectedURL.path) {
                try fm.removeItem(at: expectedURL)
            }

            try fm.createDirectory(at: expectedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: result, to: expectedURL)

            print("download: { event: \"complete\", modelSlug: \"\(entry.slug)\", localPath: \"\(expectedURL.path)\" }")
            return expectedURL
        } catch {
            print("download: { event: \"failed\", modelSlug: \"\(entry.slug)\", error: \"\(String(describing: error))\" }")
            throw ModelDownloadError.underlying("LeapModelDownloader failed: \(error.localizedDescription)")
        }
    }

    private func downloadWithLeapDownloader(
        model: HuggingFaceDownloadableModel,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> URL {
        print("download: { event: \"creatingDownloader\", model: \"\(model.filename)\" }")

        let downloader = ModelDownloader()

        print("download: { event: \"requestingDownload\", model: \"\(model.filename)\" }")
        downloader.requestDownloadModel(model)

        var lastProgress: Double = 0
        while true {
            let status = await downloader.queryStatus(model)

            switch status {
            case .notOnLocal:
                print("download: { event: \"statusNotOnLocal\", model: \"\(model.filename)\" }")
                try await Task.sleep(nanoseconds: 500_000_000)

            case .downloadInProgress(let currentProgress):
                if currentProgress != lastProgress {
                    lastProgress = currentProgress
                    progress(currentProgress)
                    print("download: { event: \"progress\", model: \"\(model.filename)\", progress: \(Int(currentProgress * 100))% }")
                }
                try await Task.sleep(nanoseconds: 200_000_000)

            case .downloaded:
                progress(1.0)
                print("download: { event: \"statusDownloaded\", model: \"\(model.filename)\" }")
                let url = downloader.getModelFile(model)
                print("download: { event: \"leapDownloadSuccess\", url: \"\(url.path)\" }")
                return url

            @unknown default:
                print("download: { event: \"unknownStatus\", model: \"\(model.filename)\" }")
                try await Task.sleep(nanoseconds: 500_000_000)
            }

            if Task.isCancelled {
                throw ModelDownloadError.cancelled
            }
        }
    }

    private func extractFilename(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let pathComponents = url.pathComponents
        for component in pathComponents.reversed() {
            if component.hasSuffix(".bundle") {
                return component
            }
        }
        return nil
    }
}

struct GemmaModelDownloadAdapter: RuntimeModelDownloadAdapting {
    func download(
        entry: ModelCatalogEntry,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> URL {
        // TODO: Implement MLX/Hub-backed download flow for Gemma assets.
        print("download: { event: \"gemma:adapterMissing\", slug: \"\(entry.slug)\" }")
        throw ModelDownloadError.downloaderUnavailable
    }
}
