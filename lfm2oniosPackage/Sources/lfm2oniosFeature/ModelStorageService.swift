import Foundation

public enum ModelStorageError: Error, Sendable {
    case unsupportedRuntime(String)
    case missingGemmaMetadata(String)
}

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

    public func expectedResourceURL(for entry: ModelCatalogEntry) throws -> URL {
        switch entry.runtime {
        case .leap:
            return try expectedBundleURL(for: entry)
        case .mlx:
            return try expectedGemmaDirectoryURL(for: entry)
        }
    }

    public func expectedBundleURL(for entry: ModelCatalogEntry) throws -> URL {
        guard entry.runtime == .leap else {
            throw ModelStorageError.unsupportedRuntime(entry.slug)
        }

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

    public func expectedGemmaDirectoryURL(for entry: ModelCatalogEntry) throws -> URL {
        guard entry.runtime == .mlx else {
            throw ModelStorageError.unsupportedRuntime(entry.slug)
        }
        guard let metadata = entry.gemmaMetadata else {
            throw ModelStorageError.missingGemmaMetadata(entry.slug)
        }

        let root = try modelsRootDirectory()
        let directory = root.appendingPathComponent(metadata.assetIdentifier, isDirectory: true)
        print("storage: { event: \"expectedGemmaDirectory\", slug: \"\(entry.slug)\", assetIdentifier: \"\(metadata.assetIdentifier)\", root: \"\(root.path)\", fullPath: \"\(directory.path)\" }")
        return directory
    }

    public func isDownloaded(entry: ModelCatalogEntry) -> Bool {
        do {
            let url = try expectedResourceURL(for: entry)
            print("storage: { event: \"isDownloaded:check\", slug: \"\(entry.slug)\", expectedPath: \"\(url.path)\", runtime: \"\(entry.runtime.rawValue)\" }")

            switch entry.runtime {
            case .leap:
                return isLeapBundleDownloaded(at: url)
            case .mlx:
                return isGemmaDirectoryReady(at: url, metadata: entry.gemmaMetadata)
            }
        } catch {
            print("storage: { event: \"isDownloaded:error\", slug: \"\(entry.slug)\", error: \"\(String(describing: error))\" }")
            return false
        }
    }

    public func deleteDownloadedModel(entry: ModelCatalogEntry) throws {
        let url = try expectedResourceURL(for: entry)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func isLeapBundleDownloaded(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        print("storage: { event: \"isDownloaded:pathCheck\", exists: \(exists), isDirectory: \(isDir.boolValue) }")

        guard exists else {
            print("storage: { event: \"isDownloaded:result\", result: false, reason: \"notExists\" }")
            return false
        }

        if isDir.boolValue {
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path) {
                let hasFiles = !contents.isEmpty
                print("storage: { event: \"isDownloaded:contentsCheck\", fileCount: \(contents.count), hasFiles: \(hasFiles) }")
                return hasFiles
            } else {
                print("storage: { event: \"isDownloaded:result\", result: false, reason: \"cannotReadDirContents\" }")
                return false
            }
        } else {
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = attrs[.size] as? Int64 ?? 0
                let isValid = fileSize > 1024
                print("storage: { event: \"isDownloaded:fileCheck\", fileSize: \(fileSize), isValid: \(isValid) }")
                return isValid
            } catch {
                print("storage: { event: \"isDownloaded:result\", result: false, reason: \"cannotReadFileAttrs\", error: \"\(error.localizedDescription)\" }")
                return false
            }
        }
    }

    private func isGemmaDirectoryReady(at url: URL, metadata: ModelCatalogEntry.GemmaMetadata?) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        print("storage: { event: \"isDownloaded:gemmaPathCheck\", exists: \(exists), isDirectory: \(isDir.boolValue) }")

        guard exists, isDir.boolValue else {
            print("storage: { event: \"isDownloaded:result\", result: false, reason: \"missingDirectory\" }")
            return false
        }

        guard let metadata else {
            print("storage: { event: \"isDownloaded:result\", result: false, reason: \"missingMetadata\" }")
            return false
        }

        let primaryPath = url.appendingPathComponent(metadata.primaryFilePath)
        if !FileManager.default.fileExists(atPath: primaryPath.path) {
            print("storage: { event: \"isDownloaded:result\", result: false, reason: \"primaryFileMissing\", primaryFile: \"\(primaryPath.path)\" }")
            return false
        }

        return true
    }
}

