import Foundation

public enum ModelRuntimeKind: String, Codable, Sendable {
    case leap
    case mlx

    public var displayName: String {
        switch self {
        case .leap:
            return "Leap"
        case .mlx:
            return "MLX"
        }
    }
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
    public let systemPrompt: String?

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
        gemmaMetadata: GemmaMetadata? = nil,
        systemPrompt: String? = nil
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
        self.systemPrompt = systemPrompt
    }
}

public enum ModelCatalog {
    /// Curated list of models for MVP. Keep small and focused.
    public static let all: [ModelCatalogEntry] = [
        ModelCatalogEntry(
            id: "lfm25-350m",
            displayName: "LFM2.5 350M Instruct",
            provider: "LiquidAI",
            slug: "lfm25-350m",
            quantizationSlug: nil,
            estDownloadMB: 222,
            contextWindow: 128_000,
            shortDescription: "Smallest instruct-tuned LFM2.5 variant available in the current catalog",
            downloadURLString: nil,
            runtime: .mlx,
            gemmaMetadata: .init(
                assetIdentifier: "lfm25-350m-4bit",
                repoID: "LiquidAI/LFM2.5-350M-MLX-4bit",
                revision: "main",
                primaryFilePath: "model.safetensors",
                matchingGlobs: [
                    "chat_template.jinja",
                    "config.json",
                    "generation_config.json",
                    "model.safetensors",
                    "model.safetensors.index.json",
                    "tokenizer.json",
                    "tokenizer_config.json"
                ]
            )
        ),
        ModelCatalogEntry(
            id: "lfm25-1.2b-instruct",
            displayName: "LFM2.5 1.2B Instruct",
            provider: "LiquidAI",
            slug: "lfm25-1.2b-instruct",
            quantizationSlug: "lfm2.5-1.2b-instruct-8da4w",
            estDownloadMB: 924,
            contextWindow: 4096,
            shortDescription: "Instruction-tuned LFM2.5 model published for the Leap runtime",
            downloadURLString: "https://huggingface.co/LiquidAI/LeapBundles/resolve/main/LFM2.5-1.2B-Instruct-8da4w_output_8da8w-seq_4096.bundle?download=true",
            runtime: .leap
        ),
        ModelCatalogEntry(
            id: "gemma4-e2b",
            displayName: "Gemma 4 E2B IT",
            provider: "Google",
            slug: "gemma4-e2b",
            quantizationSlug: nil,
            estDownloadMB: 3_613,
            contextWindow: 128_000,
            shortDescription: "Smallest Gemma 4 MLX model currently available",
            downloadURLString: nil,
            runtime: .mlx,
            gemmaMetadata: .init(
                assetIdentifier: "gemma4-e2b-4bit",
                repoID: "mlx-community/gemma-4-e2b-it-4bit",
                revision: "main",
                primaryFilePath: "model.safetensors",
                matchingGlobs: [
                    "chat_template.jinja",
                    "config.json",
                    "generation_config.json",
                    "model.safetensors",
                    "model.safetensors.index.json",
                    "processor_config.json",
                    "tokenizer.json",
                    "tokenizer_config.json"
                ]
            ),
            systemPrompt: "You are an advanced on-device assistant using Gemma 4. Use step-by-step reasoning for complex queries. Answer directly and concisely otherwise."
        )
    ]

    public static func entry(forSlug slug: String) -> ModelCatalogEntry? {
        return all.first { $0.slug == slug || $0.id == slug }
    }
}
