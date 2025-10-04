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

            guard allReferencedFilesMissing else { return }

            var updated = false
            for (key, value) in weightMap {
                if value.hasPrefix("model-") {
                    weightMap[key] = "model.safetensors"
                    updated = true
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
}
