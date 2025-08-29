import Foundation

public struct ModelCatalogEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: String            // Use slug as stable identifier
    public let displayName: String
    public let provider: String
    public let slug: String
    public let quantizationSlug: String?
    public let estDownloadMB: Int
    public let contextWindow: Int
    public let shortDescription: String

    public init(
        id: String,
        displayName: String,
        provider: String,
        slug: String,
        quantizationSlug: String?,
        estDownloadMB: Int,
        contextWindow: Int,
        shortDescription: String
    ) {
        self.id = id
        self.displayName = displayName
        self.provider = provider
        self.slug = slug
        self.quantizationSlug = quantizationSlug
        self.estDownloadMB = estDownloadMB
        self.contextWindow = contextWindow
        self.shortDescription = shortDescription
    }
}

public enum ModelCatalog {
    /// Curated list of models for MVP. Keep small and focused.
    public static let all: [ModelCatalogEntry] = [
        ModelCatalogEntry(
            id: "qwen-0.6b",
            displayName: "Qwen 0.6B (8DA4W)",
            provider: "Leap",
            slug: "qwen-0.6b",
            quantizationSlug: "qwen-0.6b-20250610-8da4w",
            estDownloadMB: 350,
            contextWindow: 4096,
            shortDescription: "Fast, tiny model for on-device prototyping"
        ),
        ModelCatalogEntry(
            id: "tiny-1b",
            displayName: "TinyLM ~1B",
            provider: "Leap",
            slug: "tiny-1b",
            quantizationSlug: nil,
            estDownloadMB: 800,
            contextWindow: 4096,
            shortDescription: "Small class model with better quality vs 0.6B"
        ),
        ModelCatalogEntry(
            id: "mid-3b",
            displayName: "Mid-size ~3B",
            provider: "Leap",
            slug: "mid-3b",
            quantizationSlug: nil,
            estDownloadMB: 2200,
            contextWindow: 8192,
            shortDescription: "Better quality, slower on mobile"
        )
    ]

    public static func entry(forSlug slug: String) -> ModelCatalogEntry? {
        return all.first { $0.slug == slug || $0.id == slug }
    }
}


