import Foundation
import OSLog
@preconcurrency import Hub

enum GemmaHubClient {
    enum Error: Swift.Error, Sendable {
        case missingToken
    }

    static func shared() throws -> HubApi {
        guard let token = GemmaHubTokenProvider.huggingFaceToken() else {
            throw Error.missingToken
        }

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let base = caches?.appendingPathComponent("huggingface", isDirectory: true)
        if let base {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            return HubApi(downloadBase: base, hfToken: token, useOfflineMode: false)
        }
        return HubApi(hfToken: token, useOfflineMode: false)
    }
}

enum GemmaHubTokenProvider {
    private static let logger = Logger(subsystem: "com.oneoffrepo.voicebot", category: "hub")

    static func huggingFaceToken() -> String? {
        let processInfo = ProcessInfo.processInfo
        if let env = processInfo.environment["LFM2ONIOS_HF_TOKEN"], !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            logger.debug("Using LFM2ONIOS_HF_TOKEN from environment")
            return env
        }

        if let environmentToken = environmentPlistValue(forKey: "LFM2ONIOS_HF_TOKEN"),
           !environmentToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            logger.debug("Using LFM2ONIOS_HF_TOKEN from Environment.plist")
            return environmentToken
        }

        if let infoValue = Bundle.main.object(forInfoDictionaryKey: "LFM2ONIOS_HF_TOKEN") as? String,
           !infoValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            logger.debug("Using LFM2ONIOS_HF_TOKEN from Info.plist")
            return infoValue
        }

        logger.error("No Hugging Face token configured. Add LFM2ONIOS_HF_TOKEN to the environment, Environment.plist, or Info.plist")
        return nil
    }

    private static func environmentPlistValue(forKey key: String) -> String? {
        let bundle = Bundle.main
        let possibleURLs: [URL?] = [
            bundle.url(forResource: "Environment", withExtension: "plist"),
            bundle.url(forResource: "Environment", withExtension: "plist", subdirectory: "Config")
        ]

        guard let url = possibleURLs.compactMap({ $0 }).first else {
            return nil
        }

        guard let data = try? Data(contentsOf: url) else {
            logger.error("Failed to load Environment.plist data")
            return nil
        }

        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            logger.error("Environment.plist could not be parsed")
            return nil
        }

        return plist[key] as? String
    }
}
