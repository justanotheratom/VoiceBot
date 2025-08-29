import SwiftUI

@available(iOS 17.0, macOS 13.0, *)
@MainActor
public struct ModelSelectionView: View {
    private let onSelect: (ModelCatalogEntry) -> Void

    public init(onSelect: @escaping (ModelCatalogEntry) -> Void) {
        self.onSelect = onSelect
    }

    public var body: some View {
        List(ModelCatalog.all) { entry in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(entry.displayName)
                        .font(.headline)
                    Spacer()
                    Text("\(entry.estDownloadMB) MB")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
                    Button("Download") {
                        onSelect(entry)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("downloadButton_\(entry.id)")
                }
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Select Model")
    }
}


