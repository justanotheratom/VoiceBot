import Foundation

public struct SelectedModel: Codable, Equatable, Sendable {
    public let slug: String
    public let displayName: String
    public let provider: String
    public let quantizationSlug: String?

    public init(slug: String, displayName: String, provider: String, quantizationSlug: String?) {
        self.slug = slug
        self.displayName = displayName
        self.provider = provider
        self.quantizationSlug = quantizationSlug
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


