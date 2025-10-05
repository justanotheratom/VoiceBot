import SwiftUI

@available(iOS 18.0, macOS 13.0, *)
@MainActor
public struct ContentView: View {
    @State private var coordinator = ModelSelectionCoordinator()

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if let current = coordinator.currentModel, current.localURL != nil {
                    ChatView(
                        selected: current,
                        onSwitch: {
                            coordinator.requestModelChange()
                        },
                        onSelectModel: { model in
                            coordinator.selectModel(model)
                        },
                        onDeleteModel: { entry in
                            do {
                                try coordinator.deleteModel(entry)
                            } catch {
                                AppLogger.download().logError(event: "deleteFailed", error: error, data: ["modelSlug": entry.slug])
                            }
                        },
                        persistence: PersistenceService()
                    )
                } else {
                    ModelSelectionView(
                        onComplete: { entry, localURL in
                            let model = SelectedModel(
                                slug: entry.slug,
                                displayName: entry.displayName,
                                provider: entry.provider,
                                quantizationSlug: entry.quantizationSlug,
                                localURL: localURL,
                                runtime: entry.runtime,
                                runtimeIdentifier: entry.gemmaMetadata?.assetIdentifier
                            )
                            coordinator.selectModel(model)
                        },
                        onDelete: { entry in
                            do {
                                try coordinator.deleteModel(entry)
                            } catch {
                                AppLogger.download().logError(event: "deleteFailed", error: error, data: ["modelSlug": entry.slug])
                            }
                        },
                        onCancel: {
                            coordinator.cancelModelChange()
                        }
                    )
                }
            }
            .task {
                coordinator.refreshModel()
            }
        }
    }
}

// MARK: - Helper Views
// Note: ChatView is in Views/ChatView.swift
// Note: Message models are in Models/ChatMessage.swift
// Note: ChatMessageView, SuggestionPill, and EmptyStateView are in UIComponents/
