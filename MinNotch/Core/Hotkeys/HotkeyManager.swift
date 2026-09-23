import AppKit
import Carbon.HIToolbox

/// Registers global shortcuts with Carbon's hotkey API.
///
/// Carbon rather than a `CGEventTap`: `RegisterEventHotKey` needs no Accessibility
/// permission, survives sandboxing, and is allowed in the Mac App Store. That matters
/// because the distribution decision is still open, and an Accessibility prompt on first
/// launch would be a poor trade for one shortcut.
///
/// The C event handler cannot capture Swift context, so registrations are held in a
/// static table keyed by the hotkey id we hand to Carbon.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private struct Registration {
        var ref: EventHotKeyRef?
        var action: HotkeyAction
    }

    /// Four-char code identifying our hotkeys, so ids never collide with another app's.
    private static let signature: OSType = {
        let chars = Array("MNCH".utf8)
        return chars.reduce(OSType(0)) { ($0 << 8) + OSType($1) }
    }()

    private static var registrations: [UInt32: Registration] = [:]
    private static var handler: EventHandlerRef?

    /// Invoked on the main thread when a registered shortcut fires.
    var onAction: ((HotkeyAction) -> Void)?

    private var nextID: UInt32 = 1
    private var isEnabled = true

    private init() {}

    /// Replaces every registration with the bindings in `settings`.
    ///
    /// Called on launch and whenever Settings > Shortcuts changes. Re-registering wholesale
    /// is cheap and avoids having to diff the binding dictionary.
    func apply(_ settings: ShortcutSettings) {
        unregisterAll()
        isEnabled = settings.globalHotkeysEnabled
        guard isEnabled else { return }

        installHandlerIfNeeded()

        for action in HotkeyAction.allCases {
            guard action.isAvailable, let combo = settings.combo(for: action) else { continue }
            register(combo, for: action)
        }
    }

    private func register(_ combo: KeyCombo, for action: HotkeyAction) {
        let id = nextID
        nextID += 1

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )

        guard status == noErr else {
            // The usual cause is another app already owning the combination. The Shortcuts
            // pane surfaces this by showing the binding without a checkmark.
            AppLog.hotkeys.error("Could not register \(action.rawValue, privacy: .public): OSStatus \(status)")
            return
        }

        Self.registrations[id] = Registration(ref: ref, action: action)
    }

    private func unregisterAll() {
        for (_, registration) in Self.registrations {
            if let ref = registration.ref { UnregisterEventHotKey(ref) }
        }
        Self.registrations.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard Self.handler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr,
                      let registration = HotkeyManager.registrations[hotKeyID.id]
                else { return OSStatus(eventNotHandledErr) }

                DispatchQueue.main.async {
                    HotkeyManager.shared.onAction?(registration.action)
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &Self.handler
        )
    }

    /// True when the combination is already claimed by one of our own actions.
    func conflictingAction(for combo: KeyCombo, in settings: ShortcutSettings, excluding action: HotkeyAction) -> HotkeyAction? {
        HotkeyAction.allCases.first { candidate in
            candidate != action && settings.combo(for: candidate) == combo
        }
    }
}
