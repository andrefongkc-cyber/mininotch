import SwiftUI

/// How the single accent colour is chosen.
enum AccentMode: String, Codable, CaseIterable, Identifiable {
    /// Follow the user's macOS accent colour. This is the default and the native choice.
    case system
    /// Use `AppearanceSettings.customAccent`.
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Match System"
        case .custom: return "Custom"
        }
    }
}

/// What tints the Now Playing scrubber and any progress bars.
enum SliderColorStyle: String, Codable, CaseIterable, Identifiable {
    case accent
    case albumArt
    case monochrome

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accent: return "Accent Color"
        case .albumArt: return "Album Artwork"
        case .monochrome: return "Monochrome"
        }
    }
}

/// Settings > Appearance.
struct AppearanceSettings: Codable, Equatable {
    var accentMode: AccentMode = .system
    var customAccent: RGBAColor = .systemBlue

    /// Draw the notch surface on `NSVisualEffectView` vibrancy instead of solid black.
    ///
    /// Off by default. The surface is meant to read as an extension of the display's black
    /// cutout, and any translucency makes it lighter than the hardware it is pretending to
    /// be part of. It is applied in both the open and closed states when enabled, so it can
    /// never appear part-way through the open animation as a flash of light.
    var useVibrancy: Bool = false

    var sliderColor: SliderColorStyle = .accent

    /// Corner radius of the expanded panel, tunable because the right value depends on the
    /// display's physical notch.
    var panelCornerRadius: Double = Double(Metrics.notchPanelCornerRadius)

    /// Width of the expanded panel in points.
    ///
    /// Wide and short rather than narrow and tall: the panel's top strip has to fit controls
    /// either side of the notch cutout, and a wide panel keeps the track title on one line.
    var expandedWidth: Double = 560

    /// What sits to the right of the cutout in the open panel's top strip, in order.
    var topStripTrailing: [TopStripItem] = TopStripItem.defaultTrailing

    /// Settings > Appearance > Ambient Lighting.
    var ambientGlow = AmbientGlowSettings()

    /// Shadow under the expanded panel.
    ///
    /// Off by default. The shadow exists only while the panel is open, so it appears and
    /// disappears with the transition rather than with the box, and on a transparent window
    /// a large-radius shadow reads as a pale halo trailing the shape as it grows and shrinks.
    /// It is worth having on a display with no physical notch, where the panel genuinely is
    /// floating over the desktop rather than pretending to be part of the bezel.
    var showPanelShadow: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accentMode = c.value(.accentMode, AccentMode.system)
        customAccent = c.value(.customAccent, RGBAColor.systemBlue)
        useVibrancy = c.value(.useVibrancy, false)
        sliderColor = c.value(.sliderColor, SliderColorStyle.accent)
        panelCornerRadius = c.value(.panelCornerRadius, Double(Metrics.notchPanelCornerRadius), in: 8...32)
        expandedWidth = c.value(.expandedWidth, 560, in: 460...820)
        topStripTrailing = c.value(.topStripTrailing, TopStripItem.defaultTrailing)
        showPanelShadow = c.value(.showPanelShadow, false)
        ambientGlow = c.value(.ambientGlow, AmbientGlowSettings())
    }

    /// The one accent colour the whole app uses for active and selected states.
    var resolvedAccent: Color {
        switch accentMode {
        case .system: return Palette.controlAccent
        case .custom: return customAccent.color
        }
    }
}

/// Something the open panel's top strip can show in its trailing flank.
///
/// Only the trailing flank is arrangeable. The leading side holds the tab strip, whose
/// position is what keeps it aligned to the left of the cutout, and the band between them is
/// a click-through dead zone that only works because nothing is drawn or dropped in it.
/// Neither is offered as a destination.
enum TopStripItem: String, Codable, CaseIterable, Identifiable, LayoutArrangeable {
    case settings
    case battery

    var id: String { rawValue }

    var layoutTitle: String {
        switch self {
        case .settings: return "Settings"
        case .battery: return "Battery"
        }
    }

    var layoutSymbol: String {
        switch self {
        case .settings: return "gearshape"
        case .battery: return "battery.100percent"
        }
    }

    /// What the strip held before it was arrangeable.
    static let defaultTrailing: [TopStripItem] = [.settings, .battery]
}
