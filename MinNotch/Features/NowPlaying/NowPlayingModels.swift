import AppKit

/// A single playback snapshot from whichever source is active.
///
/// Artwork is deliberately not part of this value: images are expensive to compare and
/// arrive later than the metadata, so `NowPlayingController` carries them alongside and
/// keys them off `artworkKey`.
struct NowPlayingTrack: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    /// Playback position at the moment the snapshot was taken.
    var elapsed: TimeInterval
    var isPlaying: Bool
    var sourceKind: MediaSourceKind
    var sourceAppName: String
    /// Player-specific identity, used to tell a genuine track change from a metadata refresh.
    var trackIdentity: String
    /// Whether the player is shuffling, or nil when the source cannot say.
    var isShuffling: Bool? = nil

    /// Identity of the artwork, so it is only re-fetched when the album actually changes.
    var artworkKey: String { "\(sourceKind.rawValue)|\(album)|\(artist)|\(title)" }

    var hasDuration: Bool { duration > 0.5 }

    var progress: Double {
        guard hasDuration else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }

    var remaining: TimeInterval { max(duration - elapsed, 0) }

    static func placeholder(kind: MediaSourceKind = .system) -> NowPlayingTrack {
        NowPlayingTrack(
            title: "Nothing Playing",
            artist: "",
            album: "",
            duration: 0,
            elapsed: 0,
            isPlaying: false,
            sourceKind: kind,
            sourceAppName: "",
            trackIdentity: ""
        )
    }
}

/// A track that plays after the current one.
struct UpNextItem: Equatable, Identifiable {
    let id = UUID()
    var title: String
    var artist: String

    static func == (lhs: UpNextItem, rhs: UpNextItem) -> Bool {
        lhs.title == rhs.title && lhs.artist == rhs.artist
    }
}

/// What the Up Next row has to show.
enum UpNextState: Equatable {
    /// Not asked, or the source has no concept of a queue.
    case idle
    case loaded([UpNextItem])
    /// Asked, and there is a reason nothing can be listed. The message is shown in the row,
    /// so an empty row always explains itself.
    case unavailable(String)
}

/// A transport command sent back to the active player.
enum MediaCommand: Equatable {
    case playPause
    case play
    case pause
    case nextTrack
    case previousTrack
    /// Absolute position in seconds.
    case seek(TimeInterval)
    case toggleShuffle
    case cycleRepeat
    case toggleFavorite
}

/// One source of playback information.
///
/// Sources are polled and are expected to be cheap when their app is not running, because
/// `NowPlayingController` asks every source whether it is live before choosing one.
protocol MediaSource: AnyObject {
    var kind: MediaSourceKind { get }
    /// False when the backing app is not running, or the API is unavailable on this system.
    var isAvailable: Bool { get }
    /// Latest metadata, or nil when the source has nothing to report.
    func snapshot() -> NowPlayingTrack?
    /// Artwork for the current track. Called off the main thread and only on track change.
    func artwork() -> NSImage?
    func send(_ command: MediaCommand)
    /// Distributed notification names this source posts, used to avoid polling where possible.
    var changeNotificationNames: [String] { get }
    /// The next few tracks, when the source can read them. Called off the main thread.
    func upNext(limit: Int) -> UpNextState
}

extension MediaSource {
    var changeNotificationNames: [String] { [] }
    func upNext(limit: Int) -> UpNextState { .idle }
}

/// One word of a lyric line, with the window during which it is being sung.
struct LyricWord: Equatable {
    var text: String
    var start: TimeInterval
    var end: TimeInterval

    func isCurrent(at time: TimeInterval) -> Bool { time >= start && time < end }
    func isSung(at time: TimeInterval) -> Bool { time >= end }
}

/// One line of lyrics. `timestamp` is nil when the provider only has an unsynced sheet, in
/// which case the view renders the lines without a highlighted current line.
struct LyricLine: Equatable, Identifiable {
    let id = UUID()
    var timestamp: TimeInterval?
    var text: String
    /// Per-word timing. Empty for unsynced lyrics.
    var words: [LyricWord] = []

    static func == (lhs: LyricLine, rhs: LyricLine) -> Bool {
        lhs.timestamp == rhs.timestamp && lhs.text == rhs.text && lhs.words == rhs.words
    }
}

struct Lyrics: Equatable {
    var lines: [LyricLine]
    var isSynced: Bool { lines.contains { $0.timestamp != nil } }
    var isEmpty: Bool { lines.isEmpty }
    /// True when the lines carry per-word timing, whether it came from enhanced LRC tags
    /// or was estimated from the line's length. Either way the strip can highlight a word.
    var hasWordTiming: Bool { lines.contains { !$0.words.isEmpty } }

    /// Index of the line that should be highlighted at `time`, for synced lyrics only.
    func index(at time: TimeInterval) -> Int? {
        guard isSynced else { return nil }
        var result: Int?
        for (index, line) in lines.enumerated() {
            guard let timestamp = line.timestamp else { continue }
            if timestamp <= time { result = index } else { break }
        }
        return result
    }
}

/// State of the lyric lookup for the current track.
///
/// The lyric strip renders one of these rather than collapsing to nothing, so "lyrics are
/// switched on but you see none" always comes with a reason.
enum LyricsStatus: Equatable {
    /// Lyrics are switched off, or nothing is playing.
    case idle
    case searching
    case loaded
    /// The player holds no lyrics for this track and online lookup is switched off.
    case noneStoredLocally
    /// Looked online and found nothing.
    case notFound

    var message: String? {
        switch self {
        case .idle, .loaded: return nil
        case .searching: return "Looking for lyrics…"
        case .noneStoredLocally: return "No lyrics stored for this track. Turn on Look Up Online in Settings > Media."
        case .notFound: return "No lyrics found for this track."
        }
    }
}
