import Foundation
import Observation

/// Store managing model download state for SettingsView
@available(iOS 17.0, macOS 13.0, *)
@MainActor
@Observable
final class ModelDownloadStore {
    // MARK: - Published State

    var downloadStates: [String: DownloadState] = [:]
    var modelToDelete: ModelCatalogEntry?
    var showDeleteConfirmation = false

    // MARK: - Dependencies

    @ObservationIgnored private let storage: ModelStorageService
    @ObservationIgnored private let downloadService: ModelDownloadService

    // MARK: - Initialization

    init(
        storage: ModelStorageService = ModelStorageService(),
        downloadService: ModelDownloadService = ModelDownloadService()
    ) {
        self.storage = storage
        self.downloadService = downloadService
    }

    // MARK: - Public API

    /// Load initial download states for all models
    func loadDownloadStates() {
        // First, check for downloaded models in catalog
        for entry in ModelCatalog.all {
            if storage.isDownloaded(entry: entry) {
                if let url = try? storage.expectedResourceURL(for: entry) {
                    downloadStates[entry.slug] = .downloaded(localURL: url)
                }
            } else {
                downloadStates[entry.slug] = .notStarted
            }
        }

        // Second, clean up orphans (models on disk but not in catalog, e.g. renamed slugs)
        Task.detached {
            do {
                let fm = FileManager.default
                let root = try self.storage.modelsRootDirectory()
                guard fm.fileExists(atPath: root.path) else { return }

                let contents = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                let activeSlugs = Set(ModelCatalog.all.map { $0.slug })
                let activeQuants = Set(ModelCatalog.all.compactMap { $0.quantizationSlug })
                let activeAssetIDs = Set(ModelCatalog.all.compactMap { $0.gemmaMetadata?.assetIdentifier })

                for url in contents {
                    let name = url.lastPathComponent
                    let nameWithoutExt = url.deletingPathExtension().lastPathComponent

                    let isOrphan = !activeSlugs.contains(nameWithoutExt) &&
                                   !activeQuants.contains(nameWithoutExt) &&
                                   !activeAssetIDs.contains(name)

                    if isOrphan {
                        try fm.removeItem(at: url)
                        AppLogger.storage().log(event: "cleanup:orphan", data: ["name": name])
                    }
                }
            } catch {
                AppLogger.storage().logError(event: "cleanup:failed", error: error)
            }
        }
    }

    /// Start downloading a model
    func downloadModel(_ entry: ModelCatalogEntry) {
        AppLogger.logDownloadStart(modelSlug: entry.slug, quantization: entry.quantizationSlug)
        downloadStates[entry.slug] = .inProgress(progress: 0.0)

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let result = try await downloadService.downloadModel(entry: entry) { progress in
                    Task { @MainActor [weak self] in
                        self?.downloadStates[entry.slug] = .inProgress(progress: progress)
                        AppLogger.logDownloadProgress(modelSlug: entry.slug, progress: progress)
                    }
                }
                await MainActor.run {
                    self.downloadStates[entry.slug] = .downloaded(localURL: result.localURL)
                }
                AppLogger.logDownloadComplete(modelSlug: entry.slug, localPath: result.localURL.path)
            } catch {
                await MainActor.run {
                    self.downloadStates[entry.slug] = .failed(error: error.localizedDescription)
                }
                AppLogger.logDownloadFailed(modelSlug: entry.slug, error: error)
            }
        }
    }

    /// Cancel an ongoing download
    func cancelDownload(_ entry: ModelCatalogEntry) {
        AppLogger.logSettingsAction(action: "cancelDownload", modelSlug: entry.slug)
        // Note: ModelDownloadService doesn't currently support cancellation
        // For now, just reset the state
        downloadStates[entry.slug] = .notStarted
    }

    /// Request to delete a model (shows confirmation)
    func requestDelete(_ entry: ModelCatalogEntry) {
        modelToDelete = entry
        showDeleteConfirmation = true
    }

    /// Confirm and execute model deletion
    func confirmDelete(onDelete: (ModelCatalogEntry) -> Void) {
        guard let entry = modelToDelete else { return }
        AppLogger.logSettingsAction(action: "deleteModel", modelSlug: entry.slug)
        onDelete(entry)
        downloadStates[entry.slug] = .notStarted
        modelToDelete = nil
        showDeleteConfirmation = false
    }

    /// Cancel deletion
    func cancelDelete() {
        modelToDelete = nil
        showDeleteConfirmation = false
    }
}
