import SwiftUI

/// Reusable model row card component for displaying model information with download/select actions.
/// Consolidates ModelCardView and CleanModelRow patterns from SettingsView.
@available(iOS 17.0, macOS 13.0, *)
public struct ModelRowCard: View {
    let entry: ModelCatalogEntry
    let isSelected: Bool
    let downloadState: DownloadState
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    public init(
        entry: ModelCatalogEntry,
        isSelected: Bool,
        downloadState: DownloadState,
        onSelect: @escaping () -> Void,
        onDownload: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.entry = entry
        self.isSelected = isSelected
        self.downloadState = downloadState
        self.onSelect = onSelect
        self.onDownload = onDownload
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    public var body: some View {
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

// MARK: - Preview

@available(iOS 17.0, macOS 13.0, *)
#Preview {
    List {
        ModelRowCard(
            entry: ModelCatalog.all[0],
            isSelected: false,
            downloadState: .notStarted,
            onSelect: {},
            onDownload: {},
            onDelete: {},
            onCancel: {}
        )

        ModelRowCard(
            entry: ModelCatalog.all[1],
            isSelected: false,
            downloadState: .inProgress(progress: 0.65),
            onSelect: {},
            onDownload: {},
            onDelete: {},
            onCancel: {}
        )

        ModelRowCard(
            entry: ModelCatalog.all[2],
            isSelected: true,
            downloadState: .downloaded(localURL: URL(fileURLWithPath: "/tmp")),
            onSelect: {},
            onDownload: {},
            onDelete: {},
            onCancel: {}
        )
    }
}
