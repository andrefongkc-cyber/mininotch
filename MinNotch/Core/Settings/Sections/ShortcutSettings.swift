import Foundation

/// Settings > Shortcuts.
///
/// Bindings are keyed by `HotkeyAction.rawValue` so an action can be added or removed
/// without invalidating the rest of the user's bindings.
struct ShortcutSettings: Codable, Equatable {
    var bindings: [String: KeyCombo] = HotkeyAction.defaultBindings

    /// Master switch, so a user can silence every shortcut without losing their bindings.
    var globalHotkeysEnabled: Bool = true

    /// The actions that existed when these bindings were saved.
    ///
    /// A cleared shortcut is a missing key, exactly like an action this file has never heard
    /// of, so without this a new action's default could never reach anyone who had saved their
    /// settings before it existed. An action missing from here is new: it gets its default once,
    /// unless that combination is already taken, and from then on is the user's to clear.
    var knownActions: [String] = HotkeyAction.allCases.map(\.rawValue)

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bindings = c.value(.bindings, HotkeyAction.defaultBindings)
        globalHotkeysEnabled = c.value(.globalHotkeysEnabled, true)

        let known = Set(c.value(.knownActions, HotkeyAction.actionsBeforeKnownActions))
        for (action, combo) in HotkeyAction.defaultBindings
        where !known.contains(action) && bindings[action] == nil && !bindings.values.contains(combo) {
            bindings[action] = combo
        }
        knownActions = HotkeyAction.allCases.map(\.rawValue)
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
