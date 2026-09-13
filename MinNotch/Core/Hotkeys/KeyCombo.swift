import AppKit
import Carbon.HIToolbox

/// A recorded key combination, stored in a form that survives serialisation.
///
/// The virtual key code is what Carbon's hotkey API wants, and it is layout-independent,
/// so a combo recorded on QWERTY still fires on Dvorak at the same physical key. The
/// display string is derived at render time from the current keyboard layout.
struct KeyCombo: Codable, Equatable, Hashable {
    /// Virtual key code, e.g. `kVK_ANSI_N`.
    var keyCode: UInt32
    /// `NSEvent.ModifierFlags` raw value, masked to the device-independent flags.
    var modifierFlags: UInt

    init(keyCode: UInt32, modifierFlags: UInt) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .control, .option, .shift])
        // A bare key with no modifiers would swallow normal typing system-wide.
        guard !flags.isEmpty else { return nil }
        self.keyCode = UInt32(event.keyCode)
        self.modifierFlags = flags.rawValue
    }

    var cocoaFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierFlags) }

    /// Modifier mask in the Carbon encoding `RegisterEventHotKey` expects.
    var carbonModifiers: UInt32 {
        var carbon: UInt32 = 0
        if cocoaFlags.contains(.command) { carbon |= UInt32(cmdKey) }
        if cocoaFlags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if cocoaFlags.contains(.option) { carbon |= UInt32(optionKey) }
        if cocoaFlags.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }

    /// Human-readable form, e.g. "⌃⌥N".
    var displayString: String {
        var parts = ""
        if cocoaFlags.contains(.control) { parts += "⌃" }
        if cocoaFlags.contains(.option) { parts += "⌥" }
        if cocoaFlags.contains(.shift) { parts += "⇧" }
        if cocoaFlags.contains(.command) { parts += "⌘" }
        return parts + KeyCodeNames.name(for: keyCode)
    }
}

/// Maps virtual key codes to the glyph macOS shows in a menu.
///
/// Printable keys resolve through the active keyboard layout via
/// `UCKeyTranslate`, so the label matches what is physically printed on the user's
/// keyboard. Non-printable keys come from a fixed table because they have no character.
enum KeyCodeNames {
    private static let special: [UInt32: String] = [
        UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥", UInt32(kVK_Space): "Space",
        UInt32(kVK_Delete): "⌫", UInt32(kVK_ForwardDelete): "⌦", UInt32(kVK_Escape): "⎋",
        UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_Home): "↖", UInt32(kVK_End): "↘",
        UInt32(kVK_PageUp): "⇞", UInt32(kVK_PageDown): "⇟",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12"
    ]

    static func name(for keyCode: UInt32) -> String {
        if let special = special[keyCode] { return special }
        if let translated = translate(keyCode: keyCode) { return translated.uppercased() }
        return "Key \(keyCode)"
    }

    private static func translate(keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)

        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }

        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}
