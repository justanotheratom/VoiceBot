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
        let bundleURL = root.appendingPathComponent(name, isDirectory: false)
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
            
            guard exists else {
                print("storage: { event: \"isDownloaded:result\", result: false, reason: \"notExists\" }")
                return false
            }
            
            if isDir.boolValue {
                // Bundle as directory - check it has files
                if let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path) {
                    let hasFiles = !contents.isEmpty
                    print("storage: { event: \"isDownloaded:contentsCheck\", fileCount: \(contents.count), hasFiles: \(hasFiles) }")
                    return hasFiles
                } else {
                    print("storage: { event: \"isDownloaded:result\", result: false, reason: \"cannotReadDirContents\" }")
                    return false
                }
            } else {
                // Bundle as file (ZIP archive) - check file size and that it's readable
                do {
                    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                    let fileSize = attrs[.size] as? Int64 ?? 0
                    let isValid = fileSize > 1024 // At least 1KB
                    print("storage: { event: \"isDownloaded:fileCheck\", fileSize: \(fileSize), isValid: \(isValid) }")
                    return isValid
                } catch {
                    print("storage: { event: \"isDownloaded:result\", result: false, reason: \"cannotReadFileAttrs\", error: \"\(error.localizedDescription)\" }")
                    return false
                }
            }
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

}


