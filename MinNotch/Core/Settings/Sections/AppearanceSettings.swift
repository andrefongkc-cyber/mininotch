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

    /// What sits either side of the cutout in the open panel's top bar, in order.
    ///
    /// Tabs are items like any other, so a tab can live on the right. Whatever does not fit on
    /// its own side moves across at display time, see `TopStripLayout`.
    var topStripLeading: [TopStripItem] = TopStripItem.defaultLeading
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
        // A file from before the tabs could be arranged has no leading list, and every tab
        // then sits on the left, which is exactly where they were.
        topStripLeading = c.value(.topStripLeading, TopStripItem.defaultLeading)
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

/// Something the open panel's top bar can show either side of the cutout.
///
/// Every tab is an item, so the user can put any of them on either side. The band between the
/// two sides is not a destination: it is a click-through dead zone over the camera housing that
/// only works because nothing is drawn or dropped in it.
///
/// A tab's raw value is its `NotchTab` raw value, and `init(_:)` is an exhaustive switch, so a
/// new tab that is not given an item here fails to compile rather than silently never showing.
enum TopStripItem: String, Codable, CaseIterable, Identifiable, LayoutArrangeable {
    case media
    case calendar
    case system
    case shelf
    case clipboard
    case links
    case timer
    case weather
    case settings
    case battery
    /// Debug buttons, shown only while Settings > Advanced > Debug Buttons in Top Bar is on.
    case whatsNew
    case tutorial

    var id: String { rawValue }

    /// True for the two debug buttons, which exist only while their setting is on.
    var isDebug: Bool { self == .whatsNew || self == .tutorial }

    init(_ tab: NotchTab) {
        switch tab {
        case .media: self = .media
        case .calendar: self = .calendar
        case .system: self = .system
        case .shelf: self = .shelf
        case .clipboard: self = .clipboard
        case .links: self = .links
        case .timer: self = .timer
        case .weather: self = .weather
        }
    }

    /// The tab this item opens, or nil for settings and battery.
    var tab: NotchTab? { NotchTab(rawValue: rawValue) }

    var layoutTitle: String {
        switch self {
        case .settings: return "Settings"
        case .battery: return "Battery"
        case .whatsNew: return "What's New"
        case .tutorial: return "Tutorial"
        default: return tab?.title ?? rawValue
        }
    }

    var layoutSymbol: String {
        switch self {
        case .settings: return "gearshape"
        case .battery: return "battery.100percent"
        case .whatsNew: return "sparkles"
        case .tutorial: return "graduationcap"
        default: return tab?.symbolName ?? "questionmark"
        }
    }

    /// Every tab on the left, in the order they were always shown.
    static let defaultLeading: [TopStripItem] = NotchTab.allCases.map(TopStripItem.init)
    /// What the right side held before it was arrangeable.
    static let defaultTrailing: [TopStripItem] = [.settings, .battery]
}
