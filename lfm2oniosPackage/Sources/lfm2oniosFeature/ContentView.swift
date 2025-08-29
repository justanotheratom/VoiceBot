import SwiftUI

@available(iOS 17.0, macOS 13.0, *)
@MainActor
public struct ContentView: View {
    @State private var persistence = PersistenceService()
    @State private var selected: SelectedModel? = nil

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if let current = selected {
                    ChatStubView(selected: current) {
                        persistence.clearSelectedModel()
                        selected = nil
                        print("ui: { event: \"switchModel\" }")
                    }
                } else {
                    ModelSelectionView { entry in
                        let model = SelectedModel(
                            slug: entry.slug,
                            displayName: entry.displayName,
                            provider: entry.provider,
                            quantizationSlug: entry.quantizationSlug
                        )
                        persistence.saveSelectedModel(model)
                        selected = model
                        print("ui: { event: \"select\", modelSlug: \"\(entry.slug)\" }")
                    }
                }
            }
            .task {
                // Load persisted selection on first appearance
                selected = persistence.loadSelectedModel()
            }
        }
    }
}

@available(iOS 17.0, macOS 13.0, *)
@MainActor
struct ChatStubView: View {
    let selected: SelectedModel
    let onSwitch: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Model selected:")
                .font(.headline)
            Text(selected.displayName)
            Text(selected.slug)
                .foregroundStyle(.secondary)
            Button("Switch Model") {
                onSwitch()
            }
            .accessibilityIdentifier("switchModelButton")
        }
        .navigationTitle("Chat")
        .padding()
    }
}
