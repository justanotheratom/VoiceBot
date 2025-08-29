import SwiftUI

@available(iOS 17.0, macOS 13.0, *)
@MainActor
public struct ModelSelectionView: View {
    private let onComplete: (ModelCatalogEntry, URL) -> Void
    private let onDelete: (ModelCatalogEntry) -> Void
    private let onCancel: (() -> Void)?
    @State private var downloadedSet: Set<String> = []
    private let storage = ModelStorageService()
    private let downloadService = ModelDownloadService()
    @State private var downloading: [String: Double] = [:] // id -> 0...1
    @State private var tasks: [String: Task<Void, Never>] = [:]

    public init(onComplete: @escaping (ModelCatalogEntry, URL) -> Void, onDelete: @escaping (ModelCatalogEntry) -> Void, onCancel: (() -> Void)? = nil) {
        self.onComplete = onComplete
        self.onDelete = onDelete
        self.onCancel = onCancel
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
                    if let pct = downloading[entry.id] {
                        HStack(spacing: 6) {
                            ProgressView(value: pct, total: 1.0)
                                .progressViewStyle(.linear)
                                .frame(width: 80)
                            Text("\(Int(pct * 100))%")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "internaldrive")
                                .foregroundStyle(.secondary)
                            Text("\(entry.estDownloadMB) MB")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
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
                    if let _ = downloading[entry.id] {
                        Button {
                            tasks[entry.id]?.cancel()
                            tasks[entry.id] = nil
                            downloading[entry.id] = nil
                            print("download: { event: \"cancelled\", modelSlug: \"\(entry.slug)\" }")
                        } label: {
                            Image(systemName: "xmark.circle")
                                .imageScale(.medium)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cancel")
                        .accessibilityIdentifier("cancelButton_\(entry.id)")
                    } else if downloadedSet.contains(entry.id) {
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
                            startDownload(entry: entry)
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
            .contentShape(Rectangle())
            .onTapGesture {
                // If already downloaded and not currently downloading, treat row tap as selection
                if downloading[entry.id] == nil && downloadedSet.contains(entry.id) {
                    do {
                        let url = try storage.expectedBundleURL(for: entry)
                        onComplete(entry, url)
                        print("ui: { event: \"select\", modelSlug: \"\(entry.slug)\" }")
                    } catch {
                        print("ui: { event: \"selectFailed\", error: \"\(String(describing: error))\" }")
                    }
                }
            }
            // Reduce extra padding to keep rows compact
        }
        .navigationTitle("Select Model")
        .toolbar {
            if let onCancel {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel() }
                        .accessibilityIdentifier("cancelSelectionButton")
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Button("Cancel") { onCancel() }
                        .accessibilityIdentifier("cancelSelectionButton")
                }
                #endif
            }
        }
        .task {
            refreshDownloaded()
        }
    }

    private func refreshDownloaded() {
        let ids = ModelCatalog.all.filter { storage.isDownloaded(entry: $0) }.map { $0.id }
        downloadedSet = Set(ids)
    }

    private func startDownload(entry: ModelCatalogEntry) {
        downloading[entry.id] = 0
        let task = Task { @MainActor in
            do {
                let result = try await downloadService.downloadModel(entry: entry) { pct in
                    Task { @MainActor in
                        downloading[entry.id] = pct
                    }
                }
                downloading[entry.id] = nil
                downloadedSet.insert(entry.id)
                onComplete(entry, result.localURL)
                print("download: { event: \"complete:inline\", modelSlug: \"\(entry.slug)\" }")
            } catch {
                downloading[entry.id] = nil
                if Task.isCancelled == false {
                    print("download: { event: \"failed\", error: \"\(String(describing: error))\" }")
                }
            }
        }
        tasks[entry.id] = task
    }
}


