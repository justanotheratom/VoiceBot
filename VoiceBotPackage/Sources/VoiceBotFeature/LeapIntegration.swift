import Foundation

#if canImport(LeapSDK)
import LeapSDK
#endif
#if canImport(LeapSDKTypes)
import LeapSDKTypes
#endif

public enum LeapIntegration {
    public static var isSDKAvailable: Bool {
        #if canImport(LeapSDK)
        let available = true
        AppLogger.runtime().log(event: "leap:sdkAvailabilityCheck", data: ["available": true])
        return available
        #else
        AppLogger.runtime().log(event: "leap:sdkAvailabilityCheck", data: ["available": false])
        return false
        #endif
    }

    public static func sdkVersionString() -> String? {
        #if canImport(LeapSDK)
        // If the SDK exposes a version, surface it; otherwise return a placeholder
        AppLogger.runtime().log(event: "leap:versionCheck", data: ["bundleId": "ai.liquid.leap.sdk"])
        
        if let bundle = Bundle(identifier: "ai.liquid.leap.sdk") {
            let infoDict = bundle.infoDictionary
            AppLogger.runtime().log(event: "leap:bundleFound", data: [
                "bundleId": "ai.liquid.leap.sdk",
                "infoDictKeys": infoDict?.keys.joined(separator: ", ") ?? "none"
            ])
            
            if let version = infoDict?["CFBundleShortVersionString"] as? String {
                AppLogger.runtime().log(event: "leap:versionFound", data: [
                    "version": version
                ])
                return version
            }
        } else {
            AppLogger.runtime().log(event: "leap:bundleNotFound", data: [
                "bundleId": "ai.liquid.leap.sdk"
            ])
            
            // Try to find any Leap-related bundles
            for bundle in Bundle.allBundles {
                if let bundleId = bundle.bundleIdentifier,
                   bundleId.contains("leap") || bundleId.contains("Leap") {
                    AppLogger.runtime().log(event: "leap:foundRelatedBundle", data: [
                        "bundleId": bundleId
                    ])
                }
            }
        }
        return nil
        #else
        AppLogger.runtime().log(event: "leap:versionCheck", data: ["available": false])
        return nil
        #endif
    }
}

