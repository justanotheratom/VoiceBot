import Foundation
import LeapSDK
@preconcurrency import LeapModelDownloader

public struct ModelDownloadResult: Sendable {
    public let localURL: URL
}

public protocol ModelDownloadServicing: Sendable {
    func downloadModel(
        entry: ModelCatalogEntry,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> ModelDownloadResult
}

public enum ModelDownloadError: Error, Sendable {
    case cancelled
    case insufficientStorage
    case underlying(String)
    case downloaderUnavailable
    case invalidURL
    case unsupportedRuntime
    case missingMetadata
    case missingToken
}

public struct ModelDownloadService: ModelDownloadServicing {
    public init() {}

    public func downloadModel(
        entry: ModelCatalogEntry,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> ModelDownloadResult {
        let adapter = adapter(for: entry)
        let localURL = try await adapter.download(entry: entry, progress: progress)
        return ModelDownloadResult(localURL: localURL)
    }

    private func adapter(for entry: ModelCatalogEntry) -> any RuntimeModelDownloadAdapting {
        switch entry.runtime {
        case .leap:
            return LeapModelDownloadAdapter()
        case .mlx:
            return GemmaModelDownloadAdapter()
        }
    }
}
