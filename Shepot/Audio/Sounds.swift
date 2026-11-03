import AppKit

/// Sound sets for the UI cues. Files come from scripts/make-sounds.py as "<set>-<cue>.wav".
enum SoundSet: String, CaseIterable {
    case standard, pixel, air, keys

    var title: String {
        switch self {
        case .standard: "Стандартный"
        case .pixel: "Пиксельный"
        case .air: "Воздушный"
        case .keys: "Клавиши"
        }
    }

    var note: String {
        switch self {
        case .standard: "Мягкие электронные тоны"
        case .pixel: "Маленькие цифровые блипы"
        case .air: "Тихое дыхание, мягкие тона"
        case .keys: "Тихие щелчки клавиш"
        }
    }
}

/// Short cues for recording start/stop, paste and errors.
enum Sound: String {
    case start, stop, paste, error

    private static var cache: [String: NSSound] = [:]

    func play(set: SoundSet) {
        let name = "\(set.rawValue)-\(rawValue)"
        let sound = Self.cache[name] ?? NSSound(named: name)
        guard let sound else { return }
        Self.cache[name] = sound
        sound.stop() // restart if it's still ringing
        sound.volume = 0.6
        sound.play()
    }
}
