import Foundation
import os
import os.log

enum AppLogCategory: String {
    case app
    case download
    case runtime
    case ui
}

struct AppLogger {
    static let subsystem = "com.oneoffrepo.lfm2onios"

    static let app = Logger(subsystem: subsystem, category: AppLogCategory.app.rawValue)
    static let download = Logger(subsystem: subsystem, category: AppLogCategory.download.rawValue)
    static let runtime = Logger(subsystem: subsystem, category: AppLogCategory.runtime.rawValue)
    static let ui = Logger(subsystem: subsystem, category: AppLogCategory.ui.rawValue)

    static func logLaunch() {
        let build = Self.buildString()
        app.info("app: { event: \"launch\", build: \"\(build)\" }")
        let legacy = OSLog(subsystem: subsystem, category: AppLogCategory.app.rawValue)
        os_log("app: { event: \"launch\", build: \"%{public}@\" }", log: legacy, type: .info, build)
        print("app: { event: \"launch\", build: \"\(build)\" }")
    }

    private static func buildString() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }
}


