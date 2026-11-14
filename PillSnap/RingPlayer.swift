import AVFoundation
import AudioToolbox

/// Loud looping ring + vibration while the "scan to stop" screen is open.
/// (The system alarm itself is handled by AlarmKit; this keeps the pressure on inside the app.)
@MainActor
final class RingPlayer {
    static let shared = RingPlayer()

    private var player: AVAudioPlayer?
    private var vibrationTimer: Timer?

    private init() {}

    func start() {
        if player?.isPlaying == true { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            if player == nil, let url = Bundle.main.url(forResource: "ring", withExtension: "wav") {
                let newPlayer = try AVAudioPlayer(contentsOf: url)
                newPlayer.numberOfLoops = -1
                player = newPlayer
            }
            player?.volume = 1.0
            player?.play()
        } catch {
            print("PillSnap: could not start ring sound: \(error)")
        }

        vibrationTimer?.invalidate()
        vibrationTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        vibrationTimer?.invalidate()
        vibrationTimer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
