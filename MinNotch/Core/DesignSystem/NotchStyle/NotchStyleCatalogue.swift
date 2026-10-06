import AppKit
import SwiftUI

/// The styles themselves. Each language is one function returning its dark or light variant.
///
/// Minimal Dark holds the values the notch was drawn with before styles existed, literally: white
/// ink, a black surface, plain fills, the artwork's old border and shadow. Change nothing about it
/// without running `Scripts/style-diff.sh` against a build from before the change.
extension NotchStyle {
    static func make(_ language: NotchDesignLanguage, isDark: Bool) -> NotchStyle {
        switch language {
        case .minimal: return minimal(isDark: isDark)
        default: return minimal(isDark: isDark)
        }
    }

    /// Whether a language is finished enough to be offered in Settings.
    static func isOffered(_ language: NotchDesignLanguage) -> Bool {
        language == .minimal
    }

    /// Resolves the user's choice. `systemIsDark` answers Match System.
    static func resolve(_ settings: AppearanceSettings, systemIsDark: Bool) -> NotchStyle {
        let isDark: Bool
        switch settings.notchVariant {
        case .dark: isDark = true
        case .light: isDark = false
        case .system: isDark = systemIsDark
        }
        let language = isOffered(settings.notchLanguage) ? settings.notchLanguage : .minimal
        return make(language, isDark: isDark)
    }

    // MARK: Minimal

    /// The notch as it always was, and its light counterpart: the same geometry and the same
    /// simplicity, near-black ink on white, a hairline edge and a faint shadow so it holds its
    /// shape against a light desktop.
    private static func minimal(isDark: Bool) -> NotchStyle {
        if isDark {
            return NotchStyle(
                language: .minimal,
                isDark: true,
                ink: .white,
                surface: .housing,
                tile: .plain,
                button: .plain,
                module: nil,
                transport: NotchTransportStyle(),
                track: NotchTrackStyle(),
                artwork: NotchArtworkStyle(),
                glow: NotchGlowStyle()
            )
        }
        let ink = Color(red: 0.11, green: 0.11, blue: 0.12)
        return NotchStyle(
            language: .minimal,
            isDark: false,
            ink: ink,
            surface: NotchSurfaceStyle(
                base: Color(red: 0.985, green: 0.985, blue: 0.99),
                border: NotchBorder(top: .black.opacity(0.1), bottom: .black.opacity(0.14), width: 1),
                shadow: NotchShadow(color: .black.opacity(0.12), radius: 10, y: 3),
                vibrancyMaterial: .popover
            ),
            tile: .plain,
            button: .plain,
            module: nil,
            transport: NotchTransportStyle(),
            track: NotchTrackStyle(),
            artwork: NotchArtworkStyle(
                border: NotchBorder(top: .black.opacity(0.08), bottom: .black.opacity(0.08), width: 0.5),
                shadow: NotchShadow(color: .black.opacity(0.16), radius: 6, y: 3)
            ),
            glow: NotchGlowStyle()
        )
    }
}
