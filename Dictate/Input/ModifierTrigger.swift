import AppKit
import Carbon.HIToolbox

/// A lone modifier key (right ⌘ or right ⌥) as the trigger.
/// Uses global event monitors, which work once Accessibility is granted.
final class ModifierTrigger {
    enum Key {
        case rightCommand, rightOption

        var keyCode: UInt16 {
            switch self {
            case .rightCommand: UInt16(kVK_RightCommand)
            case .rightOption: UInt16(kVK_RightOption)
            }
        }

        /// Device-dependent bits that tell right from left (NX_DEVICERCMDKEYMASK / NX_DEVICERALTKEYMASK).
        var deviceMask: UInt {
            switch self {
            case .rightCommand: 0x10
            case .rightOption: 0x40
            }
        }
    }

    /// Called on the main thread.
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)? // released without any other key in between
    var onChord: (() -> Void)?   // another key was pressed while held: it's a shortcut, not dictation

    private var key: Key?
    private var monitors: [Any] = []
    private var isDown = false
    private var chorded = false

    func start(_ key: Key) {
        stop()
        self.key = key
        let flags: (NSEvent) -> Void = { [weak self] in self?.flagsChanged($0) }
        let keyDown: (NSEvent) -> Void = { [weak self] _ in self?.otherKeyPressed() }
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags),
            NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { flags($0); return $0 },
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: keyDown),
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { keyDown($0); return $0 },
        ].compactMap { $0 }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        key = nil
        isDown = false
    }

    private func flagsChanged(_ event: NSEvent) {
        guard let key else { return }
        guard event.keyCode == key.keyCode else {
            if isDown { otherKeyPressed() } // e.g. right ⌘ + ⇧
            return
        }
        let down = event.modifierFlags.rawValue & key.deviceMask != 0
        if down, !isDown {
            isDown = true
            chorded = false
            onPress?()
        } else if !down, isDown {
            isDown = false
            if !chorded { onRelease?() }
        }
    }

    private func otherKeyPressed() {
        guard isDown, !chorded else { return }
        chorded = true
        onChord?()
    }
}
