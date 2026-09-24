import Foundation

/// Which player MinNotch reads from.
enum MediaSourceKind: String, Codable, CaseIterable, Identifiable {
    /// Pick whichever supported player is currently playing, preferring the most recent.
    case auto
    case appleMusic
    case spotify
    case vlc
    /// The system-wide Now Playing information, which covers browsers and any other app.
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Automatic"
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        case .vlc: return "VLC"
        case .system: return "System Now Playing"
        }
    }

    var symbolName: String {
        switch self {
        case .auto: return "wand.and.stars"
        case .appleMusic: return "music.note"
        case .spotify: return "music.note.list"
        case .vlc: return "play.rectangle"
        case .system: return "waveform"
        }
    }
}

/// Visual treatment of the Now Playing card. Only `.classic` is implemented in V1; the
/// other cases exist so the picker in Settings > Media is real from day one and V2 only
/// has to add a view, not a setting.
enum NowPlayingCardStyle: String, Codable, CaseIterable, Identifiable {
    case classic
    case compact
    case fullArtwork

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .compact: return "Compact"
        case .fullArtwork: return "Full Artwork"
        }
    }

    /// One line of what the style looks like, for the picker's row.
    var summary: String {
        switch self {
        case .classic: return "Artwork beside the title, scrubber and controls."
        case .compact: return "One short row, half the height of Classic."
        case .fullArtwork: return "The cover fills the card, blurred behind a large copy of it."
        }
    }
}

/// A control that can appear in the Now Playing transport row. The order of
/// `MediaSettings.controlOrder` is the render order, arranged in Settings > Layout. A control
/// the playing source cannot carry out is left off the card rather than drawn dead; see
/// `NowPlayingController.supports(_:)`.
enum MediaControl: String, Codable, CaseIterable, Identifiable {
    case shuffle
    case previous
    case playPause
    case next
    case repeatMode
    case favorite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shuffle: return "Shuffle"
        case .previous: return "Previous"
        case .playPause: return "Play / Pause"
        case .next: return "Next"
        case .repeatMode: return "Repeat"
        case .favorite: return "Favorite"
        }
    }

    var symbolName: String {
        switch self {
        case .shuffle: return "shuffle"
        case .previous: return "backward.fill"
        case .playPause: return "playpause.fill"
        case .next: return "forward.fill"
        case .repeatMode: return "repeat"
        case .favorite: return "heart"
        }
    }

    static let defaultOrder: [MediaControl] = [.shuffle, .previous, .playPause, .next]
}

extension MediaControl: LayoutArrangeable {
    var layoutTitle: String { title }
    var layoutSymbol: String { symbolName }
}

/// Where lyrics are looked for.
enum LyricsSource: String, Codable, CaseIterable, Identifiable {
    /// Only what the player already stores locally. Nothing leaves the Mac, but streamed
    /// tracks almost never carry lyrics, so this finds very little in practice.
    case playerOnly
    /// Fall back to an online lyrics database when the player has nothing.
    case playerThenOnline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playerOnly: return "This Mac Only"
        case .playerThenOnline: return "Look Up Online"
        }
    }

    var usesNetwork: Bool { self == .playerThenOnline }
}

/// What the effects button on the Now Playing card is currently showing.
///
/// Backed by two independent booleans rather than being stored itself, so the Media pane can
/// keep offering them as separate switches while the notch offers one button that cycles.
/// Storing a fourth value would mean two sources of truth for the same two facts.
enum MediaEffectsMode: Equatable {
    case off
    case visualizer
    case ambient
    case both

    var showsVisualizer: Bool { self == .visualizer || self == .both }
    var showsAmbient: Bool { self == .ambient || self == .both }

    var next: MediaEffectsMode {
        switch self {
        case .off: return .visualizer
        case .visualizer: return .ambient
        case .ambient: return .both
        case .both: return .off
        }
    }

    var symbolName: String {
        switch self {
        case .off: return "sparkles"
        case .visualizer: return "waveform"
        case .ambient: return "light.beacon.max"
        case .both: return "sparkles.rectangle.stack"
        }
    }

    var title: String {
        switch self {
        case .off: return "Effects Off"
        case .visualizer: return "Visualizer"
        case .ambient: return "Ambient Glow"
        case .both: return "Visualizer and Glow"
        }
    }
}

/// Settings > Media.
struct MediaSettings: Codable, Equatable {
    var enabled: Bool = true
    var preferredSource: MediaSourceKind = .auto

    /// Show time-synced lyrics under the track info when the source provides them.
    var showLyrics: Bool = false

    /// Where lyrics come from. Local only by default.
    var lyricsSource: LyricsSource = .playerOnly

    /// Measure how far the lyric file sits from the audio, and correct for it.
    ///
    /// Off by default: it needs the system audio tap running, which is a permission, and a file
    /// whose timings are already right gains nothing from it.
    var matchLyricsToAudio: Bool = false

    /// Subtract the output device's buffering from lyric timing.
    ///
    /// On by default, but it only does anything while the audio tap is running, because the
    /// latency figure comes from the same Core Audio work.
    var useAudioClockForLyrics: Bool = true

    /// Seconds to shift lyric timing by. Negative shows each line earlier.
    ///
    /// Lyric files are timed by hand and disagree between sources, so no amount of clock
    /// accuracy on our side makes every sheet line up. This is the manual correction.
    var lyricsOffset: Double = 0


    /// Show elapsed and remaining time either side of the scrubber.
    var showTimecodes: Bool = true

    /// A small icon of the playing app on the corner of the artwork.
    var showSourceBadge: Bool = true

    /// Tint the card with colours sampled from the artwork.
    var tintFromArtwork: Bool = true

    var cardStyle: NowPlayingCardStyle = .classic

    /// Also show Now Playing in a small window that floats above other apps.
    ///
    /// Off by default. The notch is the point of this app; a second always-visible window is
    /// a deliberate choice, useful on an external display where there is no notch to look at.
    var floatingWindow: Bool = false
    var controlOrder: [MediaControl] = MediaControl.defaultOrder

    // MARK: V2 scaffolding (persisted now, rendered as "Coming soon")

    /// Brief Dynamic-Island-style expand-and-collapse when the track changes.
    var sneakPeekOnTrackChange: Bool = true
    /// How long the sneak peek stays down, in seconds.
    var sneakPeekDuration: Double = 2.6
    static let sneakPeekDurationRange: ClosedRange<Double> = 1...8

    /// The current lyric line under the closed pill, in a strip the size of the sneak peek,
    /// for as long as something with lyrics is playing.
    var showLyricsWhenClosed: Bool = false

    /// Show the next few tracks under the current one. Apple Music only: Spotify's scripting
    /// dictionary has no queue to read.
    var showUpNext: Bool = true
    /// Audio visualiser keyed to the artwork's colours.
    var showVisualizer: Bool = false
    /// Replace the built-in visualiser with a user-supplied Lottie animation.
    var customVisualizerPath: String?

    /// Polling interval for sources that cannot push updates.
    var pollInterval: Double = 1.0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = c.value(.enabled, true)
        preferredSource = c.value(.preferredSource, MediaSourceKind.auto)
        showLyrics = c.value(.showLyrics, false)
        lyricsSource = c.value(.lyricsSource, LyricsSource.playerOnly)
        lyricsOffset = c.value(.lyricsOffset, 0, in: -2...2)
        useAudioClockForLyrics = c.value(.useAudioClockForLyrics, true)
        matchLyricsToAudio = c.value(.matchLyricsToAudio, false)
        showTimecodes = c.value(.showTimecodes, true)
        showSourceBadge = c.value(.showSourceBadge, true)
        tintFromArtwork = c.value(.tintFromArtwork, true)
        cardStyle = c.value(.cardStyle, NowPlayingCardStyle.classic)
        floatingWindow = c.value(.floatingWindow, false)
        controlOrder = c.value(.controlOrder, MediaControl.defaultOrder)
        sneakPeekOnTrackChange = c.value(.sneakPeekOnTrackChange, true)
        sneakPeekDuration = c.value(.sneakPeekDuration, 2.6, in: Self.sneakPeekDurationRange)
        showLyricsWhenClosed = c.value(.showLyricsWhenClosed, false)
        showUpNext = c.value(.showUpNext, true)
        showVisualizer = c.value(.showVisualizer, false)
        customVisualizerPath = c.value(.customVisualizerPath, nil as String?)
        pollInterval = c.value(.pollInterval, 1.0, in: 0.5...5)
    }
}
