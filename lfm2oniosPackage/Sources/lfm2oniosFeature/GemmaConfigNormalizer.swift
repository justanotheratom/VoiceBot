import Foundation

struct GemmaConfigNormalizer {
    static func normalizeIfNeeded(in directory: URL) {
        normalizeConfig(in: directory)
        normalizeIndex(in: directory)
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
}
