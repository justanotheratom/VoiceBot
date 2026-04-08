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

public enum ModelDownloadError: Error, LocalizedError, Sendable {
    case cancelled
    case insufficientStorage
    case underlying(String)
    case downloaderUnavailable
    case invalidURL
    case unsupportedRuntime
    case missingMetadata
    case missingToken

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "The download was cancelled."
        case .insufficientStorage:
            return "There is not enough storage space for this model."
        case .underlying(let message):
            return message
        case .downloaderUnavailable:
            return "The model downloader is not available."
        case .invalidURL:
            return "The model download URL is invalid."
        case .unsupportedRuntime:
            return "This model runtime is not supported."
        case .missingMetadata:
            return "The model catalog entry is missing required metadata."
        case .missingToken:
            return "A Hugging Face token is required for this model."
        }
    }
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
