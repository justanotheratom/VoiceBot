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
        print("leap: { event: \"sdkAvailabilityCheck\", available: true }")
        return available
        #else
        print("leap: { event: \"sdkAvailabilityCheck\", available: false }")
        return false
        #endif
    }

    public static func sdkVersionString() -> String? {
        #if canImport(LeapSDK)
        // If the SDK exposes a version, surface it; otherwise return a placeholder
        print("leap: { event: \"versionCheck\", checking: \"ai.liquid.leap.sdk\" }")
        
        if let bundle = Bundle(identifier: "ai.liquid.leap.sdk") {
            let infoDict = bundle.infoDictionary
            print("leap: { event: \"bundleFound\", bundleId: \"ai.liquid.leap.sdk\", infoDictKeys: \"\(infoDict?.keys.joined(separator: ", ") ?? "none")\" }")
            
            if let version = infoDict?["CFBundleShortVersionString"] as? String {
                print("leap: { event: \"versionFound\", version: \"\(version)\" }")
                return version
            }
        } else {
            print("leap: { event: \"bundleNotFound\", bundleId: \"ai.liquid.leap.sdk\" }")
            
            // Try to find any Leap-related bundles
            for bundle in Bundle.allBundles {
                if let bundleId = bundle.bundleIdentifier,
                   bundleId.contains("leap") || bundleId.contains("Leap") {
                    print("leap: { event: \"foundRelatedBundle\", bundleId: \"\(bundleId)\" }")
                }
            }
        }
        return nil
        #else
        print("leap: { event: \"versionCheck\", available: false }")
        return nil
        #endif
    }
}


