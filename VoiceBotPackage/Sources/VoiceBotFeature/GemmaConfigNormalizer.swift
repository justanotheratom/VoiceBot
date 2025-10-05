import Foundation

struct GemmaConfigNormalizer {
    static func normalizeIfNeeded(in directory: URL) {
        normalizeConfig(in: directory)
        normalizeIndex(in: directory)
        normalizeModelShard(in: directory)
    }

    private static func normalizeConfig(in directory: URL) {
        let configURL = directory.appendingPathComponent("config.json", isDirectory: false)
        let fm = FileManager.default
        guard fm.fileExists(atPath: configURL.path) else { return }

        do {
            let data = try Data(contentsOf: configURL)
            guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            var updated = false
            if var textConfig = root["text_config"] as? [String: Any] {
                if let intermediateArray = textConfig["intermediate_size"] as? [Any],
                   let firstValue = intermediateArray.first as? NSNumber {
                    textConfig["intermediate_size"] = firstValue.intValue
                    root["text_config"] = textConfig
                    updated = true
                }

                if textConfig["query_pre_attn_scalar"] == nil,
                   let headDim = textConfig["head_dim"] as? NSNumber {
                    textConfig["query_pre_attn_scalar"] = headDim.floatValue
                    root["text_config"] = textConfig
                    updated = true
                }
            }

            guard updated else { return }

            let normalizedData = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys]
            )
            try normalizedData.write(to: configURL, options: .atomic)
            AppLogger.download().log(event: "gemma:configNormalized", data: ["path": configURL.lastPathComponent])
        } catch {
            AppLogger.download().log(event: "gemma:configNormalizationFailed", data: [
                "error": error.localizedDescription,
                "path": configURL.lastPathComponent
            ], level: .error)
        }
    }

    private static func normalizeIndex(in directory: URL) {
        let indexURL = directory.appendingPathComponent("model.safetensors.index.json", isDirectory: false)
        let aggregateURL = directory.appendingPathComponent("model.safetensors", isDirectory: false)
        let fm = FileManager.default

        guard fm.fileExists(atPath: indexURL.path),
              fm.fileExists(atPath: aggregateURL.path) else { return }

        do {
            let data = try Data(contentsOf: indexURL)
            guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var weightMap = root["weight_map"] as? [String: String] else { return }

            let referencedFiles = Set(weightMap.values)
            let allReferencedFilesMissing = referencedFiles.allSatisfy { referenced in
                let candidatePath = directory.appendingPathComponent(referenced, isDirectory: false).path
                return !fm.fileExists(atPath: candidatePath)
            }

            let aggregateFilename = aggregateURL.lastPathComponent
            var updated = false

            if allReferencedFilesMissing {
                for (key, value) in weightMap where value.hasPrefix("model-") {
                    weightMap[key] = aggregateFilename
                    updated = true
                }
            }

            if let tensorNames = safetensorTensorNames(at: aggregateURL) {
                for name in tensorNames where name != "__metadata__" {
                    if weightMap[name] != aggregateFilename {
                        weightMap[name] = aggregateFilename
                        updated = true
                    }

                    let sanitized = sanitizeTensorName(name)
                    if weightMap[sanitized] != aggregateFilename {
                        weightMap[sanitized] = aggregateFilename
                        updated = true
                    }
                }
            }

            guard updated else { return }

            root["weight_map"] = weightMap
            let normalizedData = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys]
            )
            try normalizedData.write(to: indexURL, options: .atomic)
            AppLogger.download().log(event: "gemma:indexNormalized", data: ["path": indexURL.lastPathComponent])
        } catch {
            AppLogger.download().log(event: "gemma:indexNormalizationFailed", data: [
                "error": error.localizedDescription,
                "path": indexURL.lastPathComponent
            ], level: .error)
        }
    }

    private static func safetensorTensorNames(at url: URL) -> [String]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer {
            if #available(iOS 15.0, macOS 12.0, *) {
                try? handle.close()
            } else {
                handle.closeFile()
            }
        }

        guard let headerSizeData = try? handle.read(upToCount: 8),
              headerSizeData.count == 8 else {
            return nil
        }

        let headerSize = headerSizeData.withUnsafeBytes { ptr -> Int in
            let value = ptr.load(as: UInt64.self)
            return Int(UInt64(littleEndian: value))
        }

        guard headerSize > 0,
              let headerData = try? handle.read(upToCount: headerSize),
              headerData.count == headerSize,
              let json = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any] else {
            return nil
        }

        return json.keys.filter { $0 != "__metadata__" }
    }

    private static func sanitizeTensorName(_ name: String) -> String {
        if name.hasPrefix("language_model.model.") {
            return "language_model." + name.dropFirst("language_model.model.".count)
        }
        return name
    }

    private static func normalizeModelShard(in directory: URL) {
        let modelURL = directory.appendingPathComponent("model.safetensors", isDirectory: false)
        let fm = FileManager.default
        guard fm.fileExists(atPath: modelURL.path) else { return }

        do {
            let sourceHandle = try FileHandle(forReadingFrom: modelURL)
            defer {
                if #available(iOS 15.0, macOS 12.0, *) {
                    try? sourceHandle.close()
                } else {
                    sourceHandle.closeFile()
                }
            }

            guard let headerSizeData = try sourceHandle.read(upToCount: 8), headerSizeData.count == 8 else { return }
            let headerSize = headerSizeData.withUnsafeBytes { ptr -> UInt64 in
                let value = ptr.load(as: UInt64.self)
                return UInt64(littleEndian: value)
            }

            guard let headerData = try sourceHandle.read(upToCount: Int(headerSize)), headerData.count == headerSize else { return }
            guard var headerJSON = try JSONSerialization.jsonObject(with: headerData) as? [String: Any] else { return }

            var updated = false
            for key in Array(headerJSON.keys) {
                let sanitized = sanitizeTensorName(key)
                if sanitized != key, headerJSON[sanitized] == nil {
                    headerJSON[sanitized] = headerJSON[key]
                    updated = true
                }
            }

            guard updated else { return }

            let newHeaderData = try JSONSerialization.data(withJSONObject: headerJSON, options: [])
            var newHeaderSizeLE = UInt64(newHeaderData.count).littleEndian

            let tempURL = directory.appendingPathComponent("model.safetensors.tmp", isDirectory: false)
            if fm.fileExists(atPath: tempURL.path) {
                try fm.removeItem(at: tempURL)
            }
            fm.createFile(atPath: tempURL.path, contents: nil)

            guard let destinationHandle = try? FileHandle(forWritingTo: tempURL) else { return }
            defer {
                if #available(iOS 15.0, macOS 12.0, *) {
                    try? destinationHandle.close()
                } else {
                    destinationHandle.closeFile()
                }
            }

            withUnsafeBytes(of: &newHeaderSizeLE) { destinationHandle.write(Data($0)) }
            destinationHandle.write(newHeaderData)

            let bodyOffset = 8 + headerSize
            try sourceHandle.seek(toOffset: bodyOffset)

            while true {
                let chunk = try sourceHandle.read(upToCount: 8 * 1024 * 1024)
                if let chunk, !chunk.isEmpty {
                    destinationHandle.write(chunk)
                } else {
                    break
                }
            }

            if #available(iOS 13.0, *) {
                try destinationHandle.synchronize()
            }

            try fm.removeItem(at: modelURL)
            try fm.moveItem(at: tempURL, to: modelURL)
            AppLogger.download().log(event: "gemma:modelNormalized", data: ["path": modelURL.lastPathComponent])
        } catch {
            AppLogger.download().log(event: "gemma:modelNormalizationFailed", data: [
                "error": error.localizedDescription,
                "path": modelURL.lastPathComponent
            ], level: .error)
        }
    }
}
