import Foundation

extension KeyedDecodingContainer {
    /// Decodes a value, falling back to `fallback` when the key is missing or malformed.
    ///
    /// Every settings struct decodes through this so that adding a new stored property in a
    /// later version does not invalidate a settings file written by an earlier one, and a
    /// hand-edited or truncated file degrades to defaults instead of throwing.
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }

    /// Decodes a bounded number, clamping anything outside the range the control enforces.
    ///
    /// A settings file is not trusted input. It can be exported, mailed to somebody, edited
    /// by hand, corrupted, or written by an older build with different limits. The sliders
    /// bound these values on the way in, but import decodes straight into the store, so
    /// without a clamp a file claiming the panel is a hundred thousand points wide produces
    /// a panel a hundred thousand points wide, and the only way back is Reset.
    ///
    /// The range belongs next to the decode rather than in the pane, so it applies to every
    /// path into the value and not just the one with a slider attached to it.
    func value<T: Decodable & Comparable>(_ key: Key, _ fallback: T, in range: ClosedRange<T>) -> T {
        min(max(value(key, fallback), range.lowerBound), range.upperBound)
    }
}

/// Shared JSON coders. Sorted keys and pretty printing make an exported settings file
/// reviewable in a diff, which matters once users start sharing configurations.
enum SettingsCoding {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder { JSONDecoder() }
}
