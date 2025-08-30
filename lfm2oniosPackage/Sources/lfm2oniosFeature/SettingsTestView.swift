import SwiftUI

@available(iOS 17.0, macOS 13.0, *)
@MainActor
public struct SettingsTestView: View {
    @State private var downloadStates: [String: DownloadState] = [
        "lfm2-350m": .downloaded(localURL: URL(string: "file://test")!),
        "lfm2-700m": .downloaded(localURL: URL(string: "file://test")!),
        "lfm2-1.2b": .downloaded(localURL: URL(string: "file://test")!)
    ]
    
    @State private var selectedModelSlug: String = "lfm2-350m"
    
    private var currentModel: SelectedModel? {
        guard let entry = ModelCatalog.all.first(where: { $0.slug == selectedModelSlug }) else {
            return nil
        }
        return SelectedModel(
            slug: entry.slug,
            displayName: entry.displayName,
            provider: entry.provider,
            quantizationSlug: entry.quantizationSlug,
            localURL: URL(string: "file://test")
        )
    }
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            List {
                // Current model section
                if let current = currentModel {
                    Section {
                        CurrentModelRow(model: current)
                    } header: {
                        Text("Current Model")
                    }
                }
                
                // Available models section
                Section {
                    ForEach(ModelCatalog.all) { entry in
                        CleanModelRow(
                            entry: entry,
                            isSelected: selectedModelSlug == entry.slug,
                            downloadState: downloadStates[entry.slug] ?? .notStarted,
                            onSelect: { selectModel(entry.slug) },
                            onDownload: { downloadModel(entry.slug) },
                            onDelete: { deleteModel(entry.slug) },
                            onCancel: { cancelDownload(entry.slug) }
                        )
                    }
                } header: {
                    Text("Available Models")
                }
            }
            .navigationTitle("Models")
            .navigationBarTitleDisplayMode(.large)
        }
    }
    
    private func selectModel(_ slug: String) {
        print("Selecting model: \(slug)")
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedModelSlug = slug
        }
    }
    
    private func downloadModel(_ slug: String) {
        print("Starting download: \(slug)")
        downloadStates[slug] = .inProgress(progress: 0.0)
        
        // Simulate download progress
        Task {
            for i in 1...10 {
                try? await Task.sleep(for: .milliseconds(200))
                await MainActor.run {
                    downloadStates[slug] = .inProgress(progress: Double(i) / 10.0)
                }
            }
            await MainActor.run {
                downloadStates[slug] = .downloaded(localURL: URL(string: "file://test")!)
            }
        }
    }
    
    private func deleteModel(_ slug: String) {
        print("Deleting model: \(slug)")
        withAnimation(.easeInOut(duration: 0.2)) {
            downloadStates[slug] = .notStarted
            // If we're deleting the currently selected model, switch to another
            if selectedModelSlug == slug {
                if let firstDownloadedSlug = downloadStates.first(where: { $0.value.isDownloaded })?.key {
                    selectedModelSlug = firstDownloadedSlug
                }
            }
        }
    }
    
    private func cancelDownload(_ slug: String) {
        print("Canceling download: \(slug)")
        downloadStates[slug] = .notStarted
    }
}

@available(iOS 17.0, macOS 13.0, *)
#Preview("Settings Test View") {
    SettingsTestView()
}