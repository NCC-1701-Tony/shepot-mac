import AppKit

/// Short UI cues for recording start/stop and paste. Files come from scripts/make-sounds.py.
enum Sound: String {
    case start, stop, paste, error

    private static var cache: [Sound: NSSound] = [:]

    func play() {
        let sound = Self.cache[self] ?? NSSound(named: rawValue)
        guard let sound else { return }
        Self.cache[self] = sound
        sound.stop() // restart if it's still ringing
        sound.volume = 0.6
        sound.play()
    }
}
