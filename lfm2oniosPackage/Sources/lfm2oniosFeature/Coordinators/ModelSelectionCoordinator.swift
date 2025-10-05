import Foundation
import Observation

/// Coordinates model selection, deletion, and navigation state
@available(iOS 18.0, macOS 13.0, *)
@MainActor
@Observable
final class ModelSelectionCoordinator {
    // MARK: - Published State

    var currentModel: SelectedModel?
    var previousModel: SelectedModel?

    // MARK: - Dependencies

    @ObservationIgnored private let persistence: PersistenceService
    @ObservationIgnored private let storage: ModelStorageService

    // MARK: - Initialization

    init(persistence: PersistenceService = PersistenceService(), storage: ModelStorageService = ModelStorageService()) {
        self.persistence = persistence
        self.storage = storage
        self.currentModel = persistence.loadSelectedModel()
    }

    // MARK: - Public API

    /// Select a model and persist the selection
    func selectModel(_ model: SelectedModel) {
        currentModel = model
        persistence.saveSelectedModel(model)
        AppLogger.ui().log(event: "coordinator:selectModel", data: ["slug": model.slug])
    }

    /// Request to change the current model (for navigating to model selection)
    func requestModelChange() {
        previousModel = currentModel
        persistence.clearSelectedModel()
        currentModel = nil
        AppLogger.ui().log(event: "coordinator:requestChange", data: ["previousSlug": previousModel?.slug ?? "none"])
    }

    /// Cancel model change and restore previous selection
    func cancelModelChange() {
        if let prev = previousModel {
            currentModel = prev
            persistence.saveSelectedModel(prev)
            previousModel = nil
            AppLogger.ui().log(event: "coordinator:cancelChange", data: ["restoredSlug": prev.slug])
        }
    }

    /// Delete a model and clear selection if it was the active model
    func deleteModel(_ entry: ModelCatalogEntry) throws {
        try storage.deleteDownloadedModel(entry: entry)

        // Clear selection if we deleted the active model
        if let current = currentModel, current.slug == entry.slug {
            persistence.clearSelectedModel()
            currentModel = nil
        }

        AppLogger.ui().log(event: "coordinator:deleteModel", data: ["slug": entry.slug])
    }

    /// Refresh current model from persistence (useful on app resume)
    func refreshModel() {
        currentModel = persistence.loadSelectedModel()
    }
}
