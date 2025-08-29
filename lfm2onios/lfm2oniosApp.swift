import SwiftUI
import lfm2oniosFeature

@main
struct lfm2oniosApp: App {
    init() {
        AppLogger.logLaunch()
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    AppLogger.ui.info("ui: { event: \"rootAppear\" }")
                    print("ui: { event: \"rootAppear\" }")
                }
        }
    }
}
