import Foundation

public struct SelectedModel: Codable, Equatable, Sendable {
    public let slug: String
    public let displayName: String
    public let provider: String
    public let quantizationSlug: String?
    public let localURL: URL?
    public let runtime: ModelRuntimeKind
    public let runtimeIdentifier: String?

    public init(
        slug: String,
        displayName: String,
        provider: String,
        quantizationSlug: String?,
        localURL: URL?,
        runtime: ModelRuntimeKind,
        runtimeIdentifier: String? = nil
    ) {
        self.slug = slug
        self.displayName = displayName
        self.provider = provider
        self.quantizationSlug = quantizationSlug
        self.localURL = localURL
        self.runtime = runtime
        self.runtimeIdentifier = runtimeIdentifier
    }

    private enum CodingKeys: String, CodingKey {
        case slug
        case displayName
        case provider
        case quantizationSlug
        case localURL
        case runtime
        case runtimeIdentifier
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.slug = try container.decode(String.self, forKey: .slug)
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.provider = try container.decode(String.self, forKey: .provider)
        self.quantizationSlug = try container.decodeIfPresent(String.self, forKey: .quantizationSlug)
        self.localURL = try container.decodeIfPresent(URL.self, forKey: .localURL)
        self.runtime = try container.decodeIfPresent(ModelRuntimeKind.self, forKey: .runtime) ?? .leap
        self.runtimeIdentifier = try container.decodeIfPresent(String.self, forKey: .runtimeIdentifier)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(slug, forKey: .slug)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(provider, forKey: .provider)
        try container.encodeIfPresent(quantizationSlug, forKey: .quantizationSlug)
        try container.encodeIfPresent(localURL, forKey: .localURL)
        try container.encode(runtime, forKey: .runtime)
        try container.encodeIfPresent(runtimeIdentifier, forKey: .runtimeIdentifier)
    }
}

public protocol PersistenceServicing {
    func loadSelectedModel() -> SelectedModel?
    func saveSelectedModel(_ model: SelectedModel)
    func clearSelectedModel()
}

public struct PersistenceService: PersistenceServicing {
    private let defaults: UserDefaults
    private let selectedKey = "lfm2.selectedModel"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadSelectedModel() -> SelectedModel? {
        guard let data = defaults.data(forKey: selectedKey) else { return nil }
        return try? JSONDecoder().decode(SelectedModel.self, from: data)
    }

    public func saveSelectedModel(_ model: SelectedModel) {
        if let data = try? JSONEncoder().encode(model) {
            defaults.set(data, forKey: selectedKey)
        }
    }

    public func clearSelectedModel() {
        defaults.removeObject(forKey: selectedKey)
    }
}

