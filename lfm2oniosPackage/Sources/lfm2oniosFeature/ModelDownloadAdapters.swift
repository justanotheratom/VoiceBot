import Foundation
import LeapSDK
@preconcurrency import LeapModelDownloader
@preconcurrency import Hub

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
        guard let urlString = entry.downloadURLString,
              let filename = extractFilename(from: urlString) else {
            print("download: { event: \"failed\", error: \"invalidURL\", url: \"\(entry.downloadURLString ?? "nil")\" }")
            throw ModelDownloadError.invalidURL
        }
        let hfModel = HuggingFaceDownloadableModel(
            ownerName: "LiquidAI",
            repoName: "LeapBundles",
            filename: filename
        )

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
        let downloader = ModelDownloader()
        downloader.requestDownloadModel(model)

        var lastProgress: Double = 0
        while true {
            let status = await downloader.queryStatus(model)

            switch status {
            case .notOnLocal:
                try await Task.sleep(nanoseconds: 500_000_000)

            case .downloadInProgress(let currentProgress):
                if currentProgress != lastProgress {
                    lastProgress = currentProgress
                    progress(currentProgress)
                }
                try await Task.sleep(nanoseconds: 200_000_000)

            case .downloaded:
                progress(1.0)
                let url = downloader.getModelFile(model)
                return url

            @unknown default:
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
    private let hub: HubApi

    init(hub: HubApi = GemmaHubClient.shared) {
        self.hub = hub
    }

    func download(
        entry: ModelCatalogEntry,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> URL {
        guard let metadata = entry.gemmaMetadata else {
            throw ModelDownloadError.missingMetadata
        }

        let storage = ModelStorageService()
        let destinationDirectory = try storage.expectedGemmaDirectoryURL(for: entry)

        let fileManager = FileManager.default

        // Ensure parent directory exists and remove stale payloads
        let parent = destinationDirectory.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destinationDirectory.path) {
            try fileManager.removeItem(at: destinationDirectory)
        }

        progress(0)

        let repo = Hub.Repo(id: metadata.repoID)

        let snapshotURL: URL
        do {
            snapshotURL = try await hub.snapshot(
                from: repo,
                revision: metadata.revision,
                matching: metadata.matchingGlobs
            ) { hubProgress in
                let total = hubProgress.totalUnitCount
                let completed = hubProgress.completedUnitCount
                if total > 0 {
                    let fraction = min(max(Double(completed) / Double(total), 0), 1)
                    progress(fraction)
                }
            }
        } catch {
            print("download: { event: \"gemma:snapshotFailed\", error: \"\(error.localizedDescription)\" }")
            throw ModelDownloadError.underlying("Hub snapshot failed: \(error.localizedDescription)")
        }

        defer {
            try? fileManager.removeItem(at: snapshotURL)
        }

        try Task.checkCancellation()

        do {
            try promoteSnapshot(from: snapshotURL, to: destinationDirectory)
            try flattenPrivateDirectoryIfNeeded(at: destinationDirectory)
        } catch {
            print("download: { event: \"gemma:promoteFailed\", error: \"\(error.localizedDescription)\" }")
            throw ModelDownloadError.underlying("Failed to prepare Gemma assets: \(error.localizedDescription)")
        }

        let primaryFile = destinationDirectory.appendingPathComponent(metadata.primaryFilePath)
        if !fileManager.fileExists(atPath: primaryFile.path) {
            print("download: { event: \"gemma:primaryMissing\", slug: \"\(entry.slug)\", expected: \"\(primaryFile.path)\" }")
            throw ModelDownloadError.underlying("Gemma primary file missing after download")
        }

        progress(1.0)
        return destinationDirectory
    }

    private func promoteSnapshot(from snapshot: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(
            at: snapshot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        while let item = enumerator?.nextObject() as? URL {
            let relativePath = item.path.replacingOccurrences(of: snapshot.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            guard !relativePath.isEmpty else { continue }

            let target = destination.appendingPathComponent(relativePath, isDirectory: item.hasDirectoryPath)

            if item.hasDirectoryPath {
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                let parent = target.deletingLastPathComponent()
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: target.path) {
                    try fileManager.removeItem(at: target)
                }
                try fileManager.copyItem(at: item, to: target)
            }
        }

    }

    private func flattenPrivateDirectoryIfNeeded(at destination: URL) throws {
        let fileManager = FileManager.default
        let privateDir = destination.appendingPathComponent("private", isDirectory: true)
        guard fileManager.fileExists(atPath: privateDir.path) else { return }

        let items = try fileManager.contentsOfDirectory(at: privateDir, includingPropertiesForKeys: nil)
        for item in items {
            let target = destination.appendingPathComponent(item.lastPathComponent, isDirectory: item.hasDirectoryPath)
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.moveItem(at: item, to: target)
        }
        try fileManager.removeItem(at: privateDir)
    }
}
