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
    public let downloadURLString: String?

    public init(
        id: String,
        displayName: String,
        provider: String,
        slug: String,
        quantizationSlug: String?,
        estDownloadMB: Int,
        contextWindow: Int,
        shortDescription: String,
        downloadURLString: String?
    ) {
        self.id = id
        self.displayName = displayName
        self.provider = provider
        self.slug = slug
        self.quantizationSlug = quantizationSlug
        self.estDownloadMB = estDownloadMB
        self.contextWindow = contextWindow
        self.shortDescription = shortDescription
        self.downloadURLString = downloadURLString
    }
}

public enum ModelCatalog {
    /// Curated list of models for MVP. Keep small and focused.
    public static let all: [ModelCatalogEntry] = [
        ModelCatalogEntry(
            id: "lfm2-350m",
            displayName: "LFM2 350M",
            provider: "LiquidAI",
            slug: "lfm2-350m",
            quantizationSlug: "lfm2-350m-20250710-8da4w",
            estDownloadMB: 322,
            contextWindow: 4096,
            shortDescription: "Smallest LFM2 text model; fastest on-device option",
            downloadURLString: "https://huggingface.co/LiquidAI/LeapBundles/resolve/main/LFM2-350M-8da4w_output_8da8w-seq_4096.bundle?download=true"
        ),
        ModelCatalogEntry(
            id: "lfm2-700m",
            displayName: "LFM2 700M",
            provider: "LiquidAI",
            slug: "lfm2-700m",
            quantizationSlug: "lfm2-700m-20250710-8da4w",
            estDownloadMB: 610,
            contextWindow: 4096,
            shortDescription: "Balanced quality vs size; still mobile-friendly",
            downloadURLString: "https://huggingface.co/LiquidAI/LeapBundles/resolve/main/LFM2-700M-8da4w_output_8da8w-seq_4096.bundle?download=true"
        ),
        ModelCatalogEntry(
            id: "lfm2-1.2b",
            displayName: "LFM2 1.2B",
            provider: "LiquidAI",
            slug: "lfm2-1.2b",
            quantizationSlug: "lfm2-1.2b-20250710-8da4w",
            estDownloadMB: 924,
            contextWindow: 4096,
            shortDescription: "Higher quality; larger footprint on mobile",
            downloadURLString: "https://huggingface.co/LiquidAI/LeapBundles/resolve/main/LFM2-1.2B-8da4w_output_8da8w-seq_4096.bundle?download=true"
        )
    ]

    public static func entry(forSlug slug: String) -> ModelCatalogEntry? {
        return all.first { $0.slug == slug || $0.id == slug }
    }
}


