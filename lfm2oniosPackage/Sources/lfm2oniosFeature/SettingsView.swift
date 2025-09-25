import SwiftUI
import Foundation

#if os(iOS)
import UIKit
#endif

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
        List {
            // Simplified current model section
            if let current = currentModel {
                Section {
                    CurrentModelRow(model: current)
                } header: {
                    Text("Current Model")
                }
            }
            
            // Clean model list
            Section {
                ForEach(ModelCatalog.all) { entry in
                    CleanModelRow(
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
                    .accessibilityIdentifier("modelCard_\(entry.slug)")
                }
            } header: {
                Text("Available Models")
            }
        }
        .navigationTitle("Models")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .accessibilityLabel("Models list. Choose a model to download and use for conversations.")
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
        
        AppLogger.logSettingsAction(action: "selectModel", modelSlug: entry.slug)
        onSelectModel(entry, url)
    }
    
    private func downloadModel(_ entry: ModelCatalogEntry) {
        AppLogger.logDownloadStart(modelSlug: entry.slug, quantization: entry.quantizationSlug)
        downloadStates[entry.slug] = .inProgress(progress: 0.0)
        
        Task {
            do {
                let result = try await downloadService.downloadModel(entry: entry) { progress in
                    Task { @MainActor in
                        downloadStates[entry.slug] = .inProgress(progress: progress)
                        AppLogger.logDownloadProgress(modelSlug: entry.slug, progress: progress)
                    }
                }
                await MainActor.run {
                    downloadStates[entry.slug] = .downloaded(localURL: result.localURL)
                    AppLogger.logDownloadComplete(modelSlug: entry.slug, localPath: result.localURL.path)
                }
            } catch {
                await MainActor.run {
                    downloadStates[entry.slug] = .failed(error: error.localizedDescription)
                    AppLogger.logDownloadFailed(modelSlug: entry.slug, error: error)
                }
            }
        }
    }
    
    private func cancelDownload(_ entry: ModelCatalogEntry) {
        AppLogger.logSettingsAction(action: "cancelDownload", modelSlug: entry.slug)
        // Note: ModelDownloadService doesn't currently support cancellation
        // For now, just reset the state
        downloadStates[entry.slug] = .notStarted
    }
    
    private func deleteModel(_ entry: ModelCatalogEntry) {
        AppLogger.logSettingsAction(action: "deleteModel", modelSlug: entry.slug)
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
    
    private var cardAccessibilityLabel: String {
        var label = "\(entry.displayName) by \(entry.provider). \(entry.shortDescription). Size: \(entry.estDownloadMB) MB. Context: \(entry.contextWindow) tokens."
        
        if isSelected {
            label += " Currently selected."
        }
        
        switch downloadState {
        case .notStarted:
            label += " Not downloaded."
        case .inProgress(let progress):
            label += " Downloading: \(Int(progress * 100)) percent complete."
        case .downloaded:
            label += " Downloaded and ready to use."
        case .failed(let error):
            label += " Download failed: \(error)"
        }
        
        return label
    }
    
    private var cardAccessibilityHint: String {
        switch downloadState {
        case .notStarted:
            return "Tap download button to download this model"
        case .inProgress:
            return "Download in progress. You can cancel if needed"
        case .downloaded:
            if isSelected {
                return "This model is currently selected for conversations"
            } else {
                return "Tap select button to use this model, or delete button to remove it"
            }
        case .failed:
            return "Download failed. Tap retry button to try again"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with name
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.displayName)
                        .font(.headline)
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    Text(entry.provider)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Provider: \(entry.provider)")
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .accessibilityLabel("Currently selected model")
                }
            }
            
            // Details
            Text(entry.shortDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            HStack {
                Label("\(entry.estDownloadMB) MB", systemImage: "externaldrive")
                    .accessibilityLabel("Download size: \(entry.estDownloadMB) megabytes")
                Spacer()
                Label("\(entry.contextWindow) tokens", systemImage: "text.alignleft")
                    .accessibilityLabel("Context window: \(entry.contextWindow) tokens")
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
                    .accessibilityLabel("Download \(entry.displayName)")
                    .accessibilityHint("Downloads the model to your device")
                    
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
                            .accessibilityLabel("Cancel download of \(entry.displayName)")
                        }
                        ProgressView(value: progress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .accessibilityLabel("Download progress: \(Int(progress * 100)) percent")
                        Text("\(Int(progress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
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
                        .accessibilityLabel("Currently selected model")
                        .accessibilityHint("This model is already selected")
                    } else {
                        Button(action: onSelect) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle")
                                Text("Select")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityLabel("Select \(entry.displayName)")
                        .accessibilityHint("Choose this model for conversations")
                    }
                    
                    if !isSelected {
                        Button(action: onDelete) {
                            Image(systemName: "trash.circle.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundColor(.red)
                        .accessibilityLabel("Delete \(entry.displayName)")
                        .accessibilityHint("Remove this model from your device to free up space")
                    }
                    
                case .failed(let error):
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("Download failed")
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                        .accessibilityLabel("Download failed for \(entry.displayName)")
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Error: \(error)")
                        Button(action: onDownload) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise.circle")
                                Text("Retry")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Retry downloading \(entry.displayName)")
                        .accessibilityHint("Try downloading this model again")
                    }
                }
                
                Spacer()
            }
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.1) : {
            #if os(iOS)
            Color(UIColor.systemGray6)
            #else
            Color.gray.opacity(0.2)
            #endif
        }())
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 2)
        )
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cardAccessibilityLabel)
        .accessibilityHint(cardAccessibilityHint)
    }
}

enum DownloadState: Equatable {
    case notStarted
    case inProgress(progress: Double)
    case downloaded(localURL: URL)
    case failed(error: String)
    
    var isDownloaded: Bool {
        if case .downloaded = self {
            return true
        }
        return false
    }
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

// MARK: - Simplified UI Components

@available(iOS 17.0, macOS 13.0, *)
struct CurrentModelRow: View {
    let model: SelectedModel
    
    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.headline)
                
                Text(model.provider)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text("Active")
                .font(.caption)
                .foregroundStyle(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.green.opacity(0.1), in: Capsule())
        }
        .padding(.vertical, 4)
    }
}

@available(iOS 17.0, macOS 13.0, *)
struct CleanModelRow: View {
    let entry: ModelCatalogEntry
    let isSelected: Bool
    let downloadState: DownloadState
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Model info (primary content)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayName)
                    .font(.headline)
                
                HStack(spacing: 8) {
                    // Status indicator
                    statusIndicator
                    
                    Text("\(entry.estDownloadMB) MB • \(entry.contextWindow) context")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Description (only show if not selected to reduce clutter)
                if !isSelected, case .notStarted = downloadState {
                    Text(entry.shortDescription)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
                
                // Progress bar for active downloads
                if case .inProgress(let progress) = downloadState {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .padding(.top, 4)
                }
            }
            
            Spacer()
            
            // Single action area (no competing buttons)
            actionView
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle()) // Full row tappable
        .onTapGesture {
            if !isSelected, case .downloaded = downloadState {
                onSelect()
            }
        }
    }
    
    @ViewBuilder
    private var statusIndicator: some View {
        Group {
            switch downloadState {
            case .downloaded where isSelected:
                Label("Active", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
            case .downloaded:
                Label("Downloaded", systemImage: "checkmark.circle")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.blue)
            case .inProgress(_):
                Label("Downloading", systemImage: "arrow.down.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.blue)
            case .failed:
                Label("Failed", systemImage: "exclamationmark.triangle")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.red)
            case .notStarted:
                Label("Not Downloaded", systemImage: "cloud")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
    }
    
    @ViewBuilder 
    private var actionView: some View {
        switch downloadState {
        case .downloaded where isSelected:
            Text("Active")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.green.opacity(0.1))
                .foregroundStyle(.green)
                .clipShape(Capsule())
                
        case .downloaded:
            // Secondary actions in menu (not inline)
            Menu {
                Button("Select Model") {
                    onSelect()
                }
                
                Divider()
                Button("Delete", role: .destructive) {
                    onDelete()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            
        case .inProgress(let progress):
            VStack(spacing: 4) {
                Text("\(Int(progress * 100))%")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.blue)
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            
        case .failed:
            Button("Retry") {
                onDownload()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
            
        case .notStarted:
            Button("Download") {
                onDownload()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

@available(iOS 17.0, macOS 13.0, *)
struct StatusIndicator: View {
    let state: DownloadState
    let isSelected: Bool
    
    var body: some View {
        Group {
            switch state {
            case .downloaded where isSelected:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            case .downloaded:
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
            case .inProgress(let progress):
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.blue)
            case .failed:
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            case .notStarted:
                Image(systemName: "cloud")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.title3)
    }
}

@available(iOS 17.0, macOS 13.0, *)
struct ActionButton: View {
    let state: DownloadState
    let isSelected: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            switch state {
            case .notStarted:
                Button("Download", action: onDownload)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    
            case .inProgress:
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    
            case .downloaded where !isSelected:
                Button("Select", action: onSelect)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)
                
            case .downloaded where isSelected:
                Button("Selected", action: {})
                    .buttonStyle(.bordered)
                    .disabled(true)
                    .frame(maxWidth: .infinity)
                    
            case .failed:
                Button("Retry", action: onDownload)
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
            default:
                EmptyView()
            }
        }
    }
}
