import Foundation

public struct ModelStorageService: Sendable {
    public init() {}

    public func modelsRootDirectory() throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport.appendingPathComponent("Models", isDirectory: true)
    }

    public func expectedBundleURL(for entry: ModelCatalogEntry) throws -> URL {
        let root = try modelsRootDirectory()
        let name: String
        if let q = entry.quantizationSlug, !q.isEmpty {
            name = "\(q).bundle"
        } else {
            name = "\(entry.slug).bundle"
        }
        return root.appendingPathComponent(name, isDirectory: true)
    }

    public func isDownloaded(entry: ModelCatalogEntry) -> Bool {
        do {
            let url = try expectedBundleURL(for: entry)
            return FileManager.default.fileExists(atPath: url.path)
        } catch {
            return false
        }
    }

    public func deleteDownloadedModel(entry: ModelCatalogEntry) throws {
        let url = try expectedBundleURL(for: entry)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}


