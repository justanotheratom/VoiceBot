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
        let bundleURL = root.appendingPathComponent(name, isDirectory: true)
        print("storage: { event: \"expectedBundleURL\", slug: \"\(entry.slug)\", quantization: \"\(entry.quantizationSlug ?? "none")\", name: \"\(name)\", root: \"\(root.path)\", fullPath: \"\(bundleURL.path)\" }")
        return bundleURL
    }

    public func isDownloaded(entry: ModelCatalogEntry) -> Bool {
        do {
            let url = try expectedBundleURL(for: entry)
            print("storage: { event: \"isDownloaded:check\", slug: \"\(entry.slug)\", expectedPath: \"\(url.path)\" }")
            
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            print("storage: { event: \"isDownloaded:pathCheck\", exists: \(exists), isDirectory: \(isDir.boolValue) }")
            
            guard exists, isDir.boolValue else {
                print("storage: { event: \"isDownloaded:result\", result: false, reason: \"notExistsOrNotDir\" }")
                return false
            }
            
            // Lightweight sanity: bundle should contain at least one file
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path) {
                let hasFiles = !contents.isEmpty
                print("storage: { event: \"isDownloaded:contentsCheck\", fileCount: \(contents.count), hasFiles: \(hasFiles) }")
                return hasFiles
            }
            
            print("storage: { event: \"isDownloaded:result\", result: false, reason: \"cannotReadContents\" }")
            return false
        } catch {
            print("storage: { event: \"isDownloaded:error\", error: \"\(String(describing: error))\" }")
            return false
        }
    }

    public func deleteDownloadedModel(entry: ModelCatalogEntry) throws {
        let url = try expectedBundleURL(for: entry)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // Extract a ZIP archive into the bundle directory, replacing any existing content
    public func extractArchive(_ archiveURL: URL, for entry: ModelCatalogEntry) throws -> URL {
        let dest = try expectedBundleURL(for: entry)
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        // Use ZIPFoundation to extract. If it fails, bubble up to allow caller to fall back.
        try fm.unzipItem(at: archiveURL, to: dest)
        return dest
    }
}


