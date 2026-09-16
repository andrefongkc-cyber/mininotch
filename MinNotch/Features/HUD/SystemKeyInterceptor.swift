import AppKit
import ApplicationServices
import CoreGraphics

/// Takes the volume and brightness keys before macOS sees them, so its own overlay never
/// appears and MinNotch's indicator is the only one.
///
/// **Why a key tap and not the overlay's helper.** Earlier versions suspended `OSDUIHelper`, the
/// process that drew the overlay. On macOS 26 that process no longer draws it: with the helper
/// suspended (state `T`) the overlay still appeared on every key press. There is no supported way
/// to hide the overlay itself, so this stops the key press reaching the system at all and does
/// what the key would have done: it sets the volume or brightness directly, and the HUD shows the
/// new level. Nothing about macOS is changed, and if MinNotch quits, crashes or hangs the keys go
/// back to macOS on their own, because the tap dies with the process and the system disables a
/// tap that stops answering.
///
/// **Only keys it can act on.** A key is taken only when the matching indicator is on and the
/// level could actually be set: an output with no software volume, such as some HDMI and USB
/// devices, leaves the key to macOS, whose overlay then says the volume cannot be changed. Keyboard
/// backlight keys are always left alone, since there is no public way to set the backlight.
///
/// **Needs Accessibility access.** An event tap that can swallow events is refused to an app the
/// user has not listed under Privacy & Security > Accessibility. Without it `start()` returns
/// false and nothing is taken.
final class SystemKeyInterceptor {
    enum Key: Equatable, CaseIterable {
        case volumeUp, volumeDown, mute, brightnessUp, brightnessDown

        /// `NX_KEYTYPE_*` from `IOKit/hidsystem/ev_keymap.h`.
        init?(code: Int) {
            switch code {
            case 0: self = .volumeUp
            case 1: self = .volumeDown
            case 7: self = .mute
            case 2: self = .brightnessUp
            case 3: self = .brightnessDown
            default: return nil
            }
        }

        var code: Int {
            switch self {
            case .volumeUp: return 0
            case .volumeDown: return 1
            case .mute: return 7
            case .brightnessUp: return 2
            case .brightnessDown: return 3
            }
        }

        var isVolume: Bool { self == .volumeUp || self == .volumeDown || self == .mute }
    }

    /// One press, or one auto-repeat of a held key.
    struct Press: Equatable {
        var key: Key
        var isDown: Bool
        var isRepeat: Bool
        /// Shift and Option held, which macOS treats as a quarter step.
        var isFineStep: Bool
    }

    /// Whether to take this key at all. Asked on every press, so a settings change applies at once.
    var wantsKey: ((Key) -> Bool)?
    /// Performs a taken key press. Returns false if it could not, in which case the press goes to
    /// macOS after all.
    var perform: ((Press) -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// Keys whose press was taken, so their release is taken too. A release on its own would reach
    /// macOS without the press that belongs to it.
    private var heldKeys: [Key] = []

    var isRunning: Bool { tap != nil }

    deinit { stop() }

    // MARK: Permission

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows macOS's own "would like to control this computer" dialog, which leads to the
    /// Accessibility list. Only call this in answer to the user asking for the feature.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Lifecycle

    /// Installs the tap. Returns false when Accessibility access has not been granted.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard Self.isTrusted else { return false }

        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let interceptor = Unmanaged<SystemKeyInterceptor>.fromOpaque(context).takeUnretainedValue()
            return interceptor.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1) << Self.systemDefinedType,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            AppLog.app.error("Could not install the volume key tap")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(tap)
        self.tap = nil
        self.source = nil
        heldKeys.removeAll()
    }

    // MARK: Events

    /// `NX_SYSDEFINED`, the event type media and brightness keys arrive as.
    private static let systemDefinedType: CGEventType.RawValue = 14
    /// `NX_SUBTYPE_AUX_CONTROL_BUTTONS`.
    private static let auxControlSubtype = 8

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system switches off a tap whose callback was slow, or while secure input is on.
        // Switch it back on, or the keys would quietly go back to showing Apple's overlay.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard type.rawValue == Self.systemDefinedType,
              let nsEvent = NSEvent(cgEvent: event),
              let press = Self.press(from: nsEvent)
        else { return Unmanaged.passUnretained(event) }

        if press.isDown {
            guard wantsKey?(press.key) == true, perform?(press) == true else {
                return Unmanaged.passUnretained(event)
            }
            if !heldKeys.contains(press.key) { heldKeys.append(press.key) }
            return nil
        }

        guard let index = heldKeys.firstIndex(of: press.key) else {
            return Unmanaged.passUnretained(event)
        }
        heldKeys.remove(at: index)
        return nil
    }

    /// Decodes an auxiliary key event, or nil for anything else that arrives as system-defined.
    ///
    /// `data1` packs the key code in the top 16 bits, the state in the next 8 (`0x0A` down,
    /// `0x0B` up), and a repeat flag in the lowest bit.
    static func press(from event: NSEvent) -> Press? {
        guard event.type == .systemDefined, Int(event.subtype.rawValue) == auxControlSubtype else { return nil }
        let data = event.data1
        guard let key = Key(code: (data & 0xFFFF_0000) >> 16) else { return nil }

        let flags = data & 0xFFFF
        let state = (flags & 0xFF00) >> 8
        guard state == 0x0A || state == 0x0B else { return nil }

        return Press(
            key: key,
            isDown: state == 0x0A,
            isRepeat: flags & 0x1 != 0,
            isFineStep: event.modifierFlags.contains([.shift, .option])
        )
    }

    /// Builds the event a key would send, for the debug check.
    static func makeEvent(for key: Key, isDown: Bool, modifiers: NSEvent.ModifierFlags = []) -> NSEvent? {
        let state = isDown ? 0x0A : 0x0B
        return NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: Int16(auxControlSubtype),
            data1: (key.code << 16) | (state << 8),
            data2: -1
        )
    }
}
