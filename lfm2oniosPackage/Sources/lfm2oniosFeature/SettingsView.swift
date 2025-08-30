import SwiftUI
import Foundation

@available(iOS 17.0, macOS 13.0, *)
@MainActor
public struct SettingsView: View {
    let currentModel: SelectedModel?
    let onSelectModel: (ModelCatalogEntry, URL?) -> Void
    let onDeleteModel: (ModelCatalogEntry) -> Void
    let persistence: PersistenceService
    
    @State private var storage = ModelStorageService()
    @State private var downloadService = ModelDownloadService()
    @State private var downloadStates: [String: DownloadState] = [:]
    @State private var showDeleteConfirmation = false
    @State private var modelToDelete: ModelCatalogEntry?
    
    public init(
        currentModel: SelectedModel?,
        onSelectModel: @escaping (ModelCatalogEntry, URL?) -> Void,
        onDeleteModel: @escaping (ModelCatalogEntry) -> Void,
        persistence: PersistenceService
    ) {
        self.currentModel = currentModel
        self.onSelectModel = onSelectModel
        self.onDeleteModel = onDeleteModel
        self.persistence = persistence
    }
    
    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(ModelCatalog.all) { entry in
                    ModelCardView(
                        entry: entry,
                        isSelected: currentModel?.slug == entry.slug,
                        downloadState: downloadStates[entry.slug] ?? .notStarted,
                        onSelect: { selectModel(entry) },
                        onDownload: { downloadModel(entry) },
                        onDelete: { 
                            modelToDelete = entry
                            showDeleteConfirmation = true
                        },
                        onCancel: { cancelDownload(entry) }
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadDownloadStates()
        }
        .alert("Delete Model", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                modelToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let model = modelToDelete {
                    deleteModel(model)
                }
                modelToDelete = nil
            }
        } message: {
            if let model = modelToDelete {
                Text("Delete \(model.displayName)? This will free up \(model.estDownloadMB) MB.")
            }
        }
    }
    
    private func loadDownloadStates() async {
        await MainActor.run {
            for entry in ModelCatalog.all {
                if storage.isDownloaded(entry: entry) {
                    if let url = try? storage.expectedBundleURL(for: entry) {
                        downloadStates[entry.slug] = .downloaded(localURL: url)
                    }
                } else {
                    downloadStates[entry.slug] = .notStarted
                }
            }
        }
    }
    
    private func selectModel(_ entry: ModelCatalogEntry) {
        guard let state = downloadStates[entry.slug],
              case .downloaded(let url) = state else { return }
        
        print("ui: { event: \"settings:selectModel\", modelSlug: \"\(entry.slug)\" }")
        onSelectModel(entry, url)
    }
    
    private func downloadModel(_ entry: ModelCatalogEntry) {
        print("ui: { event: \"settings:downloadModel\", modelSlug: \"\(entry.slug)\" }")
        downloadStates[entry.slug] = .inProgress(progress: 0.0)
        
        Task {
            do {
                let result = try await downloadService.downloadModel(entry: entry) { progress in
                    Task { @MainActor in
                        downloadStates[entry.slug] = .inProgress(progress: progress)
                    }
                }
                await MainActor.run {
                    downloadStates[entry.slug] = .downloaded(localURL: result.localURL)
                    print("ui: { event: \"settings:downloadComplete\", modelSlug: \"\(entry.slug)\" }")
                }
            } catch {
                await MainActor.run {
                    downloadStates[entry.slug] = .failed(error: error.localizedDescription)
                    print("ui: { event: \"settings:downloadFailed\", modelSlug: \"\(entry.slug)\", error: \"\(error.localizedDescription)\" }")
                }
            }
        }
    }
    
    private func cancelDownload(_ entry: ModelCatalogEntry) {
        print("ui: { event: \"settings:cancelDownload\", modelSlug: \"\(entry.slug)\" }")
        // Note: ModelDownloadService doesn't currently support cancellation
        // For now, just reset the state
        downloadStates[entry.slug] = .notStarted
    }
    
    private func deleteModel(_ entry: ModelCatalogEntry) {
        print("ui: { event: \"settings:deleteModel\", modelSlug: \"\(entry.slug)\" }")
        onDeleteModel(entry)
        downloadStates[entry.slug] = .notStarted
    }
}

@available(iOS 17.0, macOS 13.0, *)
struct ModelCardView: View {
    let entry: ModelCatalogEntry
    let isSelected: Bool
    let downloadState: DownloadState
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with name
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.displayName)
                        .font(.headline)
                    Text(entry.provider)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            // Details
            Text(entry.shortDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            HStack {
                Label("\(entry.estDownloadMB) MB", systemImage: "externaldrive")
                Spacer()
                Label("\(entry.contextWindow) tokens", systemImage: "text.alignleft")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            
            // Actions
            HStack(spacing: 12) {
                switch downloadState {
                case .notStarted:
                    Button(action: onDownload) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Download")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                case .inProgress(let progress):
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle")
                                Text("Downloading...")
                            }
                            .font(.caption)
                            Spacer()
                            Button(action: onCancel) {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                        }
                        ProgressView(value: progress)
                            .progressViewStyle(LinearProgressViewStyle())
                        Text("\(Int(progress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                case .downloaded:
                    if isSelected {
                        Button(action: {}) {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(true)
                        .foregroundColor(.green)
                    } else {
                        Button(action: onSelect) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle")
                                Text("Select")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    
                    if !isSelected {
                        Button(action: onDelete) {
                            Image(systemName: "trash.circle.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundColor(.red)
                    }
                    
                case .failed(let error):
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("Download failed")
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button(action: onDownload) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise.circle")
                                Text("Retry")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                
                Spacer()
            }
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 2)
        )
        .cornerRadius(12)
    }
}

enum DownloadState: Equatable {
    case notStarted
    case inProgress(progress: Double)
    case downloaded(localURL: URL)
    case failed(error: String)
}

// MARK: - Preview

@available(iOS 17.0, macOS 13.0, *)
#Preview {
    NavigationStack {
        SettingsView(
            currentModel: SelectedModel(
                slug: "lfm2-350m",
                displayName: "LFM2 350M",
                provider: "LiquidAI",
                quantizationSlug: "lfm2-350m-20250710-8da4w",
                localURL: URL(string: "file:///some/path")
            ),
            onSelectModel: { _, _ in },
            onDeleteModel: { _ in },
            persistence: PersistenceService()
        )
    }
}