import SwiftUI

@available(iOS 17.0, macOS 13.0, *)
@MainActor
public struct ModelSelectionView: View {
    private let onSelect: (ModelCatalogEntry) -> Void
    private let onDelete: (ModelCatalogEntry) -> Void
    @State private var downloadedSet: Set<String> = []
    private let storage = ModelStorageService()

    public init(onSelect: @escaping (ModelCatalogEntry) -> Void, onDelete: @escaping (ModelCatalogEntry) -> Void) {
        self.onSelect = onSelect
        self.onDelete = onDelete
    }

    public var body: some View {
        List(ModelCatalog.all) { entry in
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 6) {
                        Text(entry.displayName)
                            .font(.headline)
                        if downloadedSet.contains(entry.id) {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(.green)
                                .opacity(0.7)
                                .imageScale(.small)
                                .accessibilityLabel("Downloaded")
                                .accessibilityIdentifier("downloadedLabel_\(entry.id)")
                        }
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "internaldrive")
                            .foregroundStyle(.secondary)
                        Text("\(entry.estDownloadMB) MB")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(entry.shortDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Text("Context: \(entry.contextWindow)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let q = entry.quantizationSlug {
                        Text(q)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if downloadedSet.contains(entry.id) {
                        Button {
                            onDelete(entry)
                            refreshDownloaded()
                        } label: {
                            Image(systemName: "trash")
                                .imageScale(.medium)
                                .foregroundStyle(.red)
                                .opacity(0.7)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete")
                        .accessibilityIdentifier("deleteButton_\(entry.id)")
                    } else {
                        Button {
                            onSelect(entry)
                        } label: {
                            Image(systemName: "arrow.down.circle")
                                .imageScale(.medium)
                                .foregroundStyle(.blue)
                                .opacity(0.7)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Download")
                        .accessibilityIdentifier("downloadButton_\(entry.id)")
                    }
                }
            }
            // Reduce extra padding to keep rows compact
        }
        .navigationTitle("Select Model")
        .task {
            refreshDownloaded()
        }
    }

    private func refreshDownloaded() {
        let ids = ModelCatalog.all.filter { storage.isDownloaded(entry: $0) }.map { $0.id }
        downloadedSet = Set(ids)
    }
}


