import Foundation

public enum ModelRuntimeKind: String, Codable, Sendable {
    case leap
    case mlx
}

public struct ModelCatalogEntry: Identifiable, Codable, Equatable, Sendable {
    public struct GemmaMetadata: Codable, Equatable, Sendable {
        public let assetIdentifier: String
        public let repoID: String
        public let revision: String
        public let primaryFilePath: String
        public let matchingGlobs: [String]

        public init(
            assetIdentifier: String,
            repoID: String,
            revision: String,
            primaryFilePath: String,
            matchingGlobs: [String]
        ) {
            self.assetIdentifier = assetIdentifier
            self.repoID = repoID
            self.revision = revision
            self.primaryFilePath = primaryFilePath
            self.matchingGlobs = matchingGlobs
        }
    }

    public let id: String            // Use slug as stable identifier
    public let displayName: String
    public let provider: String
    public let slug: String
    public let quantizationSlug: String?
    public let estDownloadMB: Int
    public let contextWindow: Int
    public let shortDescription: String
    public let downloadURLString: String?
    public let runtime: ModelRuntimeKind
    public let gemmaMetadata: GemmaMetadata?

    public init(
        id: String,
        displayName: String,
        provider: String,
        slug: String,
        quantizationSlug: String?,
        estDownloadMB: Int,
        contextWindow: Int,
        shortDescription: String,
        downloadURLString: String?,
        runtime: ModelRuntimeKind,
        gemmaMetadata: GemmaMetadata? = nil
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
        self.runtime = runtime
        self.gemmaMetadata = gemmaMetadata
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
            downloadURLString: "https://huggingface.co/LiquidAI/LeapBundles/resolve/main/LFM2-350M-8da4w_output_8da8w-seq_4096.bundle?download=true",
            runtime: .leap
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
            downloadURLString: "https://huggingface.co/LiquidAI/LeapBundles/resolve/main/LFM2-700M-8da4w_output_8da8w-seq_4096.bundle?download=true",
            runtime: .leap
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
            downloadURLString: "https://huggingface.co/LiquidAI/LeapBundles/resolve/main/LFM2-1.2B-8da4w_output_8da8w-seq_4096.bundle?download=true",
            runtime: .leap
        ),
        ModelCatalogEntry(
            id: "gemma3-270m",
            displayName: "Gemma 3 270M IT",
            provider: "Google",
            slug: "gemma3-270m",
            quantizationSlug: nil,
            estDownloadMB: 145,
            contextWindow: 8192,
            shortDescription: "Instruction-tuned Gemma 3 running via MLX runtime",
            downloadURLString: nil,
            runtime: .mlx,
            gemmaMetadata: .init(
                assetIdentifier: "gemma3-270m-4bit",
                repoID: "mlx-community/gemma-3-270m-it-4bit",
                revision: "main",
                primaryFilePath: "model.safetensors",
                matchingGlobs: [
                    "model.safetensors",
                    "tokenizer.json"
                ]
            )
        )
    ]

    public static func entry(forSlug slug: String) -> ModelCatalogEntry? {
        return all.first { $0.slug == slug || $0.id == slug }
    }
}

