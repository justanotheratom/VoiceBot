import Foundation

struct GemmaConfigNormalizer {
    static func normalizeIfNeeded(in directory: URL) {
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
}
