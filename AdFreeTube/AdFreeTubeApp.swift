import SwiftUI

@main
struct AdFreeTubeApp: App {
    init() {
        // Configure the audio session once at launch so playback continues
        // when the device is locked or the app is backgrounded (with PiP).
        AudioSessionManager.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .ignoresSafeArea(.keyboard)
        }
    }
}
