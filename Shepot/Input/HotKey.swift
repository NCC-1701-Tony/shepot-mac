import AppKit
import Carbon.HIToolbox

/// Global hotkey via Carbon. Works without Input Monitoring permission.
final class HotKey {
    struct Combo: Codable, Equatable {
        var keyCode: UInt32   // kVK_* virtual key code
        var modifiers: UInt32 // Carbon mask: optionKey, cmdKey, controlKey, shiftKey
        var label: String     // e.g. "⌥ Space"
    }

    static let defaultCombo = Combo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), label: "⌥ Space")

    /// Called on the main thread.
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x5348_5054 // 'SHPT'

    init() {
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            switch Int(GetEventKind(event)) {
            case kEventHotKeyPressed: hotKey.onPress?()
            case kEventHotKeyReleased: hotKey.onRelease?()
            default: break
            }
            return noErr
        }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    deinit {
        unregister()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// Returns false if another app already holds this combo.
    @discardableResult
    func register(_ combo: Combo) -> Bool {
        unregister()
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            combo.keyCode, combo.modifiers, id,
            GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotKeyRef
        )
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }
}

extension HotKey.Combo {
    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19",
    ]
    private static let namedKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
    ]

    /// Builds a combo from a key press. Needs a modifier, except for F-keys.
    init?(event: NSEvent) {
        let code = Int(event.keyCode)
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        let functionKey = Self.functionKeys[code]
        guard !flags.isEmpty || functionKey != nil else { return nil }

        var carbon: UInt32 = 0
        var symbols = ""
        if flags.contains(.control) { carbon |= UInt32(controlKey); symbols += "⌃" }
        if flags.contains(.option) { carbon |= UInt32(optionKey); symbols += "⌥" }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey); symbols += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey); symbols += "⌘" }

        let key = functionKey ?? Self.namedKeys[code]
            ?? event.charactersIgnoringModifiers?.uppercased() ?? "?"
        self.init(keyCode: UInt32(code), modifiers: carbon, label: symbols.isEmpty ? key : "\(symbols) \(key)")
    }
}
