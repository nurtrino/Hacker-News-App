import AVFoundation

/// Owns the shared `AVAudioSession`. Setting the category to `.playback`
/// allows YouTube audio/video to keep playing while the app is in the
/// background or the screen is locked (Picture-in-Picture must be active
/// for video; audio continues regardless once a media element is playing).
final class AudioSessionManager {
    static let shared = AudioSessionManager()

    private init() {}

    func configure() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true, options: [])
        } catch {
            // Non-fatal: playback still works, just without the background
            // privileges. Log so it is visible while debugging.
            print("[AdFreeTube] Failed to configure audio session: \(error)")
        }
    }
}
