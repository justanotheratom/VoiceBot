import Foundation
import OSLog
@preconcurrency import Hub

enum GemmaHubClient {
    static let shared: HubApi = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let base = caches?.appendingPathComponent("huggingface", isDirectory: true)
        let token = GemmaHubTokenProvider.huggingFaceToken()
        if let base {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            return HubApi(downloadBase: base, hfToken: token)
        }
        if let token {
            return HubApi(hfToken: token)
        }
        return HubApi()
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

        logger.debug("No Hugging Face token configured; relying on anonymous access")
        return nil
    }
}
