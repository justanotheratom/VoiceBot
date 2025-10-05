import SwiftUI

@available(iOS 18.0, macOS 13.0, *)
@MainActor
public struct ContentView: View {
    @State private var persistence = PersistenceService()
    @State private var selected: SelectedModel? = nil
    @State private var previousSelected: SelectedModel? = nil
    private let storage = ModelStorageService()

    public init() {
        let p = PersistenceService()
        _persistence = State(initialValue: p)
        _selected = State(initialValue: p.loadSelectedModel())
    }

    public var body: some View {
        NavigationStack {
            Group {
                if let current = selected, current.localURL != nil {
                    ChatView(selected: current, onSwitch: {
                        previousSelected = current
                        persistence.clearSelectedModel()
                        selected = nil
                    }, onSelectModel: { model in
                        selected = model
                    }, onDeleteModel: { entry in
                        do {
                            try storage.deleteDownloadedModel(entry: entry)
                            if let current = selected, current.slug == entry.slug {
                                // Clear selection if we deleted the active model
                                persistence.clearSelectedModel()
                                selected = nil
                            }
                        } catch {
                            AppLogger.download().logError(event: "deleteFailed", error: error, data: ["modelSlug": entry.slug])
                        }
                    }, persistence: persistence)
                } else {
                    ModelSelectionView { entry, localURL in
                        // Persist with localURL when inline download completes
                        let model = SelectedModel(
                            slug: entry.slug,
                            displayName: entry.displayName,
                            provider: entry.provider,
                            quantizationSlug: entry.quantizationSlug,
                            localURL: localURL,
                            runtime: entry.runtime,
                            runtimeIdentifier: entry.gemmaMetadata?.assetIdentifier
                        )
                        persistence.saveSelectedModel(model)
                        selected = model
                    } onDelete: { entry in
                        do {
                            try storage.deleteDownloadedModel(entry: entry)
                            if let current = selected, current.slug == entry.slug {
                                // Clear selection if we deleted the active model
                                persistence.clearSelectedModel()
                                selected = nil
                            }
                        } catch {
                            AppLogger.download().logError(event: "deleteFailed", error: error, data: ["modelSlug": entry.slug])
                        }
                    } onCancel: {
                        if let prev = previousSelected {
                            selected = prev
                            persistence.saveSelectedModel(prev)
                            previousSelected = nil
                        }
                    }
                }
            }
            .task {
                // Ensure selection is up to date on appear as well
                selected = persistence.loadSelectedModel()
            }
        }
    }
}

// MARK: - Helper Views
// Note: ChatView is in Views/ChatView.swift
// Note: Message models are in Models/ChatMessage.swift
// Note: ChatMessageView, SuggestionPill, and EmptyStateView are in UIComponents/
