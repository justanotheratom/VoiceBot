import Foundation
import os.log

/// Centralized logging utility for structured, consistent logging across the app
public struct AppLogger {
    private static let subsystem = "com.oneoffrepo.lfm2onios"
    
    public struct Category {
        public static let app = "app"
        public static let download = "download" 
        public static let runtime = "runtime"
        public static let ui = "ui"
        public static let storage = "storage"
    }
    
    private let category: String
    private let logger: os.Logger
    
    private init(category: String) {
        self.category = category
        self.logger = os.Logger(subsystem: Self.subsystem, category: category)
    }
    
    static func app() -> AppLogger { AppLogger(category: Category.app) }
    static func download() -> AppLogger { AppLogger(category: Category.download) }
    static func runtime() -> AppLogger { AppLogger(category: Category.runtime) }
    static func ui() -> AppLogger { AppLogger(category: Category.ui) }
    static func storage() -> AppLogger { AppLogger(category: Category.storage) }
    
    /// Log a structured event with consistent formatting
    /// - Parameters:
    ///   - event: The event name (e.g., "launch", "download:complete")
    ///   - data: Additional structured data as key-value pairs
    ///   - level: The log level (default: .default)
    public func log(event: String, data: [String: Any] = [:], level: OSLogType = .default) {
        var logData: [String: Any] = ["event": event]
        logData.merge(data) { _, new in new }
        
        let message = formatLogMessage(logData)
        logger.log(level: level, "\(message, privacy: .public)")
        
        // Also print to console for development/debugging
        print("\(category): \(message)")
    }
    
    /// Log an error with structured formatting
    public func logError(event: String, error: Error, data: [String: Any] = [:]) {
        var errorData = data
        errorData["error"] = String(describing: error)
        errorData["errorType"] = String(describing: type(of: error))
        
        log(event: event, data: errorData, level: .error)
    }
    
    private func formatLogMessage(_ data: [String: Any]) -> String {
        // Create a JSON-like structured format for consistency
        let items = data.compactMap { key, value -> String? in
            let valueStr: String
            
            switch value {
            case let string as String:
                valueStr = "\"\(string)\""
            case let number as NSNumber:
                valueStr = number.stringValue
            case let bool as Bool:
                valueStr = bool ? "true" : "false"
            case let url as URL:
                valueStr = "\"\(url.path)\""
            default:
                valueStr = "\"\(String(describing: value))\""
            }
            
            return "\(key): \(valueStr)"
        }
        
        return "{ \(items.joined(separator: ", ")) }"
    }
}

/// Convenience extensions for common logging patterns
public extension AppLogger {
    
    // MARK: - App Events
    static func logAppLaunch(build: String, sdkVersion: String? = nil) {
        let logger = AppLogger.app()
        var data: [String: Any] = ["build": build]
        if let version = sdkVersion {
            data["sdkVersion"] = version
        }
        logger.log(event: "launch", data: data)
    }
    
    static func logAppStateChange(from: String, to: String) {
        AppLogger.app().log(event: "stateChange", data: ["from": from, "to": to])
    }
    
    // MARK: - Download Events
    static func logDownloadStart(modelSlug: String, quantization: String?) {
        var data: [String: Any] = ["modelSlug": modelSlug]
        if let quant = quantization {
            data["quantization"] = quant
        }
        AppLogger.download().log(event: "start", data: data)
    }
    
    static func logDownloadProgress(modelSlug: String, progress: Double) {
        AppLogger.download().log(event: "progress", data: [
            "modelSlug": modelSlug,
            "progress": Int(progress * 100)
        ])
    }
    
    static func logDownloadComplete(modelSlug: String, localPath: String, sizeBytes: Int64? = nil) {
        var data: [String: Any] = [
            "modelSlug": modelSlug,
            "localPath": localPath
        ]
        if let size = sizeBytes {
            data["sizeBytes"] = size
        }
        AppLogger.download().log(event: "complete", data: data)
    }
    
    static func logDownloadFailed(modelSlug: String, error: Error) {
        AppLogger.download().logError(event: "failed", error: error, data: ["modelSlug": modelSlug])
    }
    
    // MARK: - Runtime Events
    static func logRuntimeLoadStart(slug: String, url: String) {
        AppLogger.runtime().log(event: "load:start", data: [
            "slug": slug,
            "url": url,
            "urlExists": FileManager.default.fileExists(atPath: URL(string: url)?.path ?? "")
        ])
    }
    
    static func logRuntimeLoadSuccess(slug: String, loadTimeMs: Int? = nil) {
        var data: [String: Any] = ["slug": slug]
        if let time = loadTimeMs {
            data["loadTimeMs"] = time
        }
        AppLogger.runtime().log(event: "load:success", data: data)
    }
    
    static func logRuntimeLoadFailed(slug: String, error: Error) {
        AppLogger.runtime().logError(event: "load:failed", error: error, data: ["slug": slug])
    }
    
    static func logStreamStart(prompt: String) {
        AppLogger.runtime().log(event: "stream:start", data: [
            "promptLength": prompt.count,
            "promptPreview": String(prompt.prefix(50))
        ])
    }
    
    static func logStreamComplete(tokens: Int, finishReason: String?, tokensPerSecond: Double? = nil) {
        var data: [String: Any] = ["tokens": tokens]
        if let reason = finishReason {
            data["finishReason"] = reason
        }
        if let tps = tokensPerSecond {
            data["tokensPerSecond"] = String(format: "%.2f", tps)
        }
        AppLogger.runtime().log(event: "stream:complete", data: data)
    }
    
    static func logStreamFailed(error: Error, prompt: String? = nil) {
        var data: [String: Any] = [:]
        if let p = prompt {
            data["promptLength"] = p.count
        }
        AppLogger.runtime().logError(event: "stream:failed", error: error, data: data)
    }
    
    // MARK: - UI Events
    static func logUIAction(action: String, data: [String: Any] = [:]) {
        AppLogger.ui().log(event: action, data: data)
    }
    
    static func logModelSelected(slug: String, displayName: String, source: String = "unknown") {
        AppLogger.ui().log(event: "modelSelected", data: [
            "modelSlug": slug,
            "displayName": displayName,
            "source": source
        ])
    }
    
    static func logSettingsAction(action: String, modelSlug: String? = nil) {
        var data: [String: Any] = ["action": action]
        if let slug = modelSlug {
            data["modelSlug"] = slug
        }
        AppLogger.ui().log(event: "settings", data: data)
    }
    
    // MARK: - Storage Events
    static func logStorageCheck(modelSlug: String, isDownloaded: Bool, fileSize: Int64? = nil) {
        var data: [String: Any] = [
            "modelSlug": modelSlug,
            "isDownloaded": isDownloaded
        ]
        if let size = fileSize {
            data["fileSizeBytes"] = size
        }
        AppLogger.storage().log(event: "check", data: data)
    }
    
    static func logStorageDelete(modelSlug: String, success: Bool, error: Error? = nil) {
        var data: [String: Any] = [
            "modelSlug": modelSlug,
            "success": success
        ]
        if let err = error {
            data["error"] = String(describing: err)
        }
        AppLogger.storage().log(event: "delete", data: data)
    }
}