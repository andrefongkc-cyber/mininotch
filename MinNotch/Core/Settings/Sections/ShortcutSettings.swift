import Foundation

/// Settings > Shortcuts.
///
/// Bindings are keyed by `HotkeyAction.rawValue` so an action can be added or removed
/// without invalidating the rest of the user's bindings.
struct ShortcutSettings: Codable, Equatable {
    var bindings: [String: KeyCombo] = HotkeyAction.defaultBindings

    /// Master switch, so a user can silence every shortcut without losing their bindings.
    var globalHotkeysEnabled: Bool = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bindings = c.value(.bindings, HotkeyAction.defaultBindings)
        globalHotkeysEnabled = c.value(.globalHotkeysEnabled, true)
    }

    func combo(for action: HotkeyAction) -> KeyCombo? {
        bindings[action.rawValue]
    }

    mutating func setCombo(_ combo: KeyCombo?, for action: HotkeyAction) {
        if let combo {
            bindings[action.rawValue] = combo
        } else {
            bindings.removeValue(forKey: action.rawValue)
        }
    }
}
