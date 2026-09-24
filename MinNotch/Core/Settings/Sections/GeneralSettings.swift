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

    /// Whether the closed pill's Song indicator shows the title or the artist.
    var pillSongText: PillSongText = .title

    /// A live activity for each file arriving in Downloads. Off by default: it reads the
    /// Downloads folder, which is a permission of its own.
    var showDownloadActivity: Bool = false

    /// A live activity with an accessory's charge when it connects.
    var announceConnectedDevices: Bool = true

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
        pillSongText = c.value(.pillSongText, PillSongText.title)
        // Before the song had an indicator of its own, it rode in the Live Activity slot as the
        // lowest-priority activity. A file from then has no `pillSongText` key, and gets the Song
        // placed where that slot is, so the song stays where its owner was used to seeing it.
        if !c.contains(.pillSongText) {
            PillIndicator.placeSong(leading: &pillLeading, trailing: &pillTrailing)
        }
        showDownloadActivity = c.value(.showDownloadActivity, false)
        announceConnectedDevices = c.value(.announceConnectedDevices, true)
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
    case song
    case activity
    case playing
    case battery
    case weather

    var id: String { rawValue }

    var layoutTitle: String {
        switch self {
        case .artwork: return "Album Art"
        case .song: return "Song"
        case .activity: return "Live Activity"
        case .playing: return "Playing Indicator"
        case .battery: return "Battery"
        case .weather: return "Weather"
        }
    }

    var layoutSymbol: String {
        switch self {
        case .artwork: return "photo"
        case .song: return "textformat"
        case .activity: return "bolt.badge.clock"
        case .playing: return "waveform"
        case .battery: return "battery.100percent"
        case .weather: return "cloud.sun"
        }
    }

    /// The song beside its cover on the left, and what changes on its own on the right.
    /// Balanced on purpose: both flanks are drawn at the wider one's width, so a layout that
    /// piles everything on one side leaves the other side an empty black strip.
    static let defaultLeading: [PillIndicator] = [.artwork, .song]
    static let defaultTrailing: [PillIndicator] = [.playing, .activity, .battery]

    /// Puts the Song just before the Live Activity, on whichever side that is. Nothing happens
    /// when the Song is already placed, or when there is no Live Activity to stand beside,
    /// since then the song was never showing.
    static func placeSong(leading: inout [PillIndicator], trailing: inout [PillIndicator]) {
        guard !leading.contains(.song), !trailing.contains(.song) else { return }
        if let index = leading.firstIndex(of: .activity) {
            leading.insert(.song, at: index)
        } else if let index = trailing.firstIndex(of: .activity) {
            trailing.insert(.song, at: index)
        }
    }
}

/// What the closed pill's Song indicator shows.
enum PillSongText: String, Codable, CaseIterable, Identifiable {
    case title
    case artist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .title: return "Song Title"
        case .artist: return "Artist"
        }
    }
}
