import SwiftUI

@available(iOS 17.0, macOS 13.0, *)
@MainActor
public struct DownloadingView: View {
    public let entry: ModelCatalogEntry
    public let onComplete: (ModelDownloadResult) -> Void
    public let onCancel: () -> Void

    @State private var progressValue: Double = 0
    @State private var isDownloading: Bool = true
    private let service = ModelDownloadService()

    public init(
        entry: ModelCatalogEntry,
        onComplete: @escaping (ModelDownloadResult) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.entry = entry
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("Downloading \(entry.displayName)")
                .font(.headline)
            ProgressView(value: progressValue, total: 1.0)
                .progressViewStyle(.linear)
                .padding(.horizontal)
            Text("\(Int(progressValue * 100))%")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
        }
        .padding()
        .task(id: entry.id) {
            guard isDownloading else { return }
            do {
                let result = try await service.downloadModel(entry: entry) { pct in
                    Task { @MainActor in
                        progressValue = pct
                    }
                }
                onComplete(result)
            } catch {
                // Surface a basic error and allow retry by staying on view
                print("download: { event: \"failed\", error: \"\(String(describing: error))\" }")
                isDownloading = false
            }
        }
        .navigationTitle("Downloading")
    }
}


