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
        return root.appendingPathComponent(name, isDirectory: false)
    }

    public func expectedGemmaDirectoryURL(for entry: ModelCatalogEntry) throws -> URL {
        guard entry.runtime == .mlx else {
            throw ModelStorageError.unsupportedRuntime(entry.slug)
        }
        guard let metadata = entry.gemmaMetadata else {
            throw ModelStorageError.missingGemmaMetadata(entry.slug)
        }

        let root = try modelsRootDirectory()
        return root.appendingPathComponent(metadata.assetIdentifier, isDirectory: true)
    }

    public func isDownloaded(entry: ModelCatalogEntry) -> Bool {
        do {
            let url = try expectedResourceURL(for: entry)
            switch entry.runtime {
            case .leap:
                return isLeapBundleDownloaded(at: url)
            case .mlx:
                return isGemmaDirectoryReady(at: url, metadata: entry.gemmaMetadata)
            }
        } catch {
            AppLogger.storage().logError(event: "checkFailed", error: error, data: ["modelSlug": entry.slug])
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

        guard exists else {
            return false
        }

        if isDir.boolValue {
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path) {
                let hasFiles = !contents.isEmpty
                return hasFiles
            } else {
                AppLogger.storage().log(event: "contentsReadFailed", data: [
                    "path": url,
                    "reason": "cannotReadDirContents"
                ], level: .error)
                return false
            }
        } else {
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = attrs[.size] as? Int64 ?? 0
                let isValid = fileSize > 1024
                return isValid
            } catch {
                AppLogger.storage().logError(event: "attributeReadFailed", error: error, data: ["path": url])
                return false
            }
        }
    }

    private func isGemmaDirectoryReady(at url: URL, metadata: ModelCatalogEntry.GemmaMetadata?) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

        guard exists, isDir.boolValue else {
            return false
        }

        guard let metadata else {
            AppLogger.storage().log(event: "missingMetadata", data: [
                "path": url
            ], level: .error)
            return false
        }

        let primaryPath = url.appendingPathComponent(metadata.primaryFilePath)
        if !FileManager.default.fileExists(atPath: primaryPath.path) {
            AppLogger.storage().log(event: "primaryFileMissing", data: [
                "path": primaryPath
            ], level: .error)
            return false
        }

        return true
    }
}
