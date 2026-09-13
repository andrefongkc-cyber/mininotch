import Foundation

/// Settings > General.
struct GeneralSettings: Codable, Equatable {
    /// Register the app as a login item via `SMAppService`. The stored value is the user's
    /// intent; `LaunchAtLogin` reconciles it with the real registration state at launch.
    var launchAtLogin: Bool = false

    /// Show the `NSStatusItem`. When off, the notch itself and the global hotkey are the
    /// only ways to reach Settings, so the hotkey must always stay registered.
    var showMenuBarIcon: Bool = true

    /// Expand the notch when the pointer rests over it.
    var hoverToOpen: Bool = true

    /// Seconds the pointer must dwell before the panel expands. 0 means immediate.
    var hoverOpenDelay: Double = 0.25

    /// Collapse again when the pointer leaves the panel.
    var closeOnMouseExit: Bool = true

    /// Expand on click even when `hoverToOpen` is off.
    var clickToOpen: Bool = true

    /// Widen the closed pill either side of the cutout to show battery and playback.
    ///
    /// Off by default: at rest the pill is then exactly the size of the hardware notch, so
    /// the top of the screen looks untouched. On a notched Mac this also means the closed
    /// pill is invisible, because the whole cutout is behind the camera housing.
    var extendPillForIndicators: Bool = false

    /// What sits either side of the cutout in the closed pill, in order, outermost last on
    /// the leading side and outermost first on the trailing one. Arranged in Settings.
    var pillLeading: [PillIndicator] = PillIndicator.defaultLeading
    var pillTrailing: [PillIndicator] = PillIndicator.defaultTrailing

    /// Reopen on whichever tab was showing last, instead of the default tab.
    var rememberLastTab: Bool = true

    /// Persisted last tab, only consulted when `rememberLastTab` is on.
    var lastTab: NotchTab = .media

    /// Tab shown when `rememberLastTab` is off.
    var defaultTab: NotchTab = .media

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = c.value(.launchAtLogin, false)
        showMenuBarIcon = c.value(.showMenuBarIcon, true)
        hoverToOpen = c.value(.hoverToOpen, true)
        hoverOpenDelay = c.value(.hoverOpenDelay, 0.25, in: 0...1)
        closeOnMouseExit = c.value(.closeOnMouseExit, true)
        clickToOpen = c.value(.clickToOpen, true)
        extendPillForIndicators = c.value(.extendPillForIndicators, false)
        pillLeading = c.value(.pillLeading, PillIndicator.defaultLeading)
        pillTrailing = c.value(.pillTrailing, PillIndicator.defaultTrailing)
        rememberLastTab = c.value(.rememberLastTab, true)
        lastTab = c.value(.lastTab, NotchTab.media)
        defaultTab = c.value(.defaultTab, NotchTab.media)
    }
}

/// Something the closed pill can show in one of its flanks.
///
/// Which of these appear, and which side each sits on, is the user's arrangement rather than
/// a fixed assignment in the view. The middle of the pill is deliberately not a destination:
/// that band sits over the camera housing and only works because nothing is drawn in it.
enum PillIndicator: String, Codable, CaseIterable, Identifiable, LayoutArrangeable {
    case artwork
    case activity
    case playing
    case battery

    var id: String { rawValue }

    var layoutTitle: String {
        switch self {
        case .artwork: return "Album Art"
        case .activity: return "Live Activity"
        case .playing: return "Playing Indicator"
        case .battery: return "Battery"
        }
    }

    var layoutSymbol: String {
        switch self {
        case .artwork: return "photo"
        case .activity: return "bolt.badge.clock"
        case .playing: return "waveform"
        case .battery: return "battery.100percent"
        }
    }

    /// What today's fixed layout did, so an existing install sees no change.
    static let defaultLeading: [PillIndicator] = [.artwork, .activity, .playing]
    static let defaultTrailing: [PillIndicator] = [.battery]
}
