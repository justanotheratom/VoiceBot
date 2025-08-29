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
        true
        #else
        false
        #endif
    }

    public static func sdkVersionString() -> String? {
        #if canImport(LeapSDK)
        // If the SDK exposes a version, surface it; otherwise return a placeholder
        if let version = Bundle(identifier: "ai.liquid.leap.sdk")?.infoDictionary?[("CFBundleShortVersionString")] as? String {
            return version
        }
        return nil
        #else
        return nil
        #endif
    }
}


