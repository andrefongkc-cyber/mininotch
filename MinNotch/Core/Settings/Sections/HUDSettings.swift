import Foundation

/// Visual treatment for the replacement volume/brightness overlays.
enum HUDStyle: String, Codable, CaseIterable, Identifiable {
    case notchInline
    case floatingPill
    case progressRing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notchInline: return "Inline Bar"
        case .floatingPill: return "Bar Below Notch"
        case .progressRing: return "Ring"
        }
    }
}

/// Settings > HUDs.
///
/// Nothing here is wired up in V1. The settings exist so the pane is real and so the
/// HUD feature can be built later without a settings migration. `HUDCoordinator` is the
/// intended owner of these values; see WORKPLAN.md.
struct HUDSettings: Codable, Equatable {
    var replaceVolumeHUD: Bool = false
    var replaceBrightnessHUD: Bool = false
    var replaceKeyboardBacklightHUD: Bool = false
    var style: HUDStyle = .notchInline

    /// Seconds the HUD stays on screen after the last change.
    var dismissDelay: Double = 1.5

    /// Show the numeric level alongside the bar.
    var showNumericValue: Bool = false

    /// Hide macOS's own overlay so only MinNotch's indicator appears.
    ///
    /// Works by taking the volume and brightness keys before macOS sees them, which needs
    /// Accessibility access; see `SystemKeyInterceptor`. Off by default, because an app reading
    /// key presses should be something the user chose.
    var suppressSystemOverlay: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        replaceVolumeHUD = c.value(.replaceVolumeHUD, false)
        replaceBrightnessHUD = c.value(.replaceBrightnessHUD, false)
        replaceKeyboardBacklightHUD = c.value(.replaceKeyboardBacklightHUD, false)
        style = c.value(.style, HUDStyle.notchInline)
        dismissDelay = c.value(.dismissDelay, 1.5, in: 0.5...4)
        showNumericValue = c.value(.showNumericValue, false)
        suppressSystemOverlay = c.value(.suppressSystemOverlay, false)
    }
}
