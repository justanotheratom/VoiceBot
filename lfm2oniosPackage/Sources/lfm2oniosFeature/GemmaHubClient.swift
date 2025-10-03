import Foundation
import OSLog
@preconcurrency import Hub

enum GemmaHubClient {
    static let shared: HubApi = {
        guard let token = GemmaHubTokenProvider.huggingFaceToken() else {
            preconditionFailure("LFM2ONIOS_HF_TOKEN must be set in the environment or Info.plist for Gemma downloads")
        }

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let base = caches?.appendingPathComponent("huggingface", isDirectory: true)
        if let base {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            return HubApi(downloadBase: base, hfToken: token)
        }
        return HubApi(hfToken: token)
    }()
}

enum GemmaHubTokenProvider {
    private static let logger = Logger(subsystem: "com.oneoffrepo.lfm2onios", category: "hub")

    static func huggingFaceToken() -> String? {
        let processInfo = ProcessInfo.processInfo
        if let env = processInfo.environment["LFM2ONIOS_HF_TOKEN"], !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            logger.debug("Using LFM2ONIOS_HF_TOKEN from environment")
            return env
        }

        if let infoValue = Bundle.main.object(forInfoDictionaryKey: "LFM2ONIOS_HF_TOKEN") as? String,
           !infoValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            logger.debug("Using LFM2ONIOS_HF_TOKEN from Info.plist")
            return infoValue
        }

        logger.error("No Hugging Face token configured. Set LFM2ONIOS_HF_TOKEN in the environment or Info.plist")
        return nil
    }
}
