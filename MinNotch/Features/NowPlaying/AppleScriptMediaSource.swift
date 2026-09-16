import AppKit

/// Everything that differs between two scriptable players.
///
/// Keeping the differences as data rather than as subclasses means adding a third player
/// later is a new `PlayerDescriptor` value, not a new class.
struct PlayerDescriptor {
    var kind: MediaSourceKind
    var bundleIdentifier: String
    var displayName: String
    /// Application name as AppleScript knows it.
    var scriptName: String
    /// Divisor turning the player's duration unit into seconds. Spotify reports milliseconds.
    var durationScale: Double
    /// Distributed notification the player posts when playback changes.
    var changeNotification: String?
    /// Script returning the artwork, or nil when artwork comes from a URL instead.
    var artworkScript: String?
    /// Script returning an artwork URL to download.
    var artworkURLScript: String?
    var shuffleScript: String
    var repeatScript: String
    var favoriteScript: String
    /// The property holding shuffle state, as the player's dictionary names it.
    var shuffleStateProperty: String?
    /// Script listing upcoming tracks, with `LIMIT` replaced by a count, or nil when the
    /// player exposes no queue.
    var upNextScript: String?

    static let appleMusic = PlayerDescriptor(
        kind: .appleMusic,
        bundleIdentifier: "com.apple.Music",
        displayName: "Music",
        scriptName: "Music",
        durationScale: 1,
        changeNotification: "com.apple.Music.playerInfo",
        artworkScript: "tell application \"Music\" to get raw data of artwork 1 of current track",
        artworkURLScript: nil,
        shuffleScript: "tell application \"Music\" to set shuffle enabled to not (shuffle enabled)",
        repeatScript: """
        tell application "Music"
            if song repeat is off then
                set song repeat to all
            else if song repeat is all then
                set song repeat to one
            else
                set song repeat to off
            end if
        end tell
        """,
        favoriteScript: """
        tell application "Music"
            try
                set favorited of current track to not (favorited of current track)
            on error
                set loved of current track to not (loved of current track)
            end try
        end tell
        """,
        shuffleStateProperty: "shuffle enabled",
        // Music does not expose its real Up Next queue to AppleScript. What it does expose is
        // the playlist or album the current track is playing from, and the current track's
        // position in it, which gives the next tracks in order. With shuffle on that order is
        // not the play order, so it says so instead of listing tracks that will not come next.
        //
        // Checked for another way in, and there is none: the dictionary has no queue, shuffle
        // mode, or "playing next" class at all, and the session Music saves to
        // ~/Library/Application Support/Music/PlaybackSessions holds the current item and the
        // shuffle setting, not the shuffled order. Reading the Playing Next sidebar through
        // Accessibility would need that sidebar open in a Music window.
        upNextScript: """
        if application "Music" is running then
            tell application "Music"
                try
                    if shuffle enabled then
                        set sourceName to ""
                        try
                            set sourceName to (name of current playlist) as text
                        end try
                        return {"shuffle", sourceName}
                    end if
                    set sourceList to current playlist
                    set position to index of current track
                    set total to count of tracks of sourceList
                    set lastPosition to position + LIMIT
                    if lastPosition > total then set lastPosition to total
                    set upcoming to {"ok"}
                    repeat with i from (position + 1) to lastPosition
                        set nextTrack to track i of sourceList
                        set end of upcoming to {(name of nextTrack) as text, (artist of nextTrack) as text}
                    end repeat
                    return upcoming
                on error
                    return {"unavailable"}
                end try
            end tell
        else
            return {"unavailable"}
        end if
        """
    )

    static let spotify = PlayerDescriptor(
        kind: .spotify,
        bundleIdentifier: "com.spotify.client",
        displayName: "Spotify",
        scriptName: "Spotify",
        durationScale: 1000,
        changeNotification: "com.spotify.client.PlaybackStateChanged",
        artworkScript: nil,
        artworkURLScript: "tell application \"Spotify\" to get artwork url of current track",
        shuffleScript: "tell application \"Spotify\" to set shuffling to not shuffling",
        repeatScript: "tell application \"Spotify\" to set repeating to not repeating",
        favoriteScript: "",
        shuffleStateProperty: "shuffling",
        // Spotify's dictionary has no queue at all: current track, position, state, nothing
        // after. Up Next is Apple Music only for that reason, not by choice.
        upNextScript: nil
    )
}

/// Reads and controls a scriptable player through Apple Events.
///
/// This is the primary path rather than a fallback. The private MediaRemote framework used
/// to be the obvious choice, but Apple gated its now playing functions behind an
/// entitlement, so a shipping app cannot rely on it. Apple Events work everywhere, are
/// allowed in the App Store with the automation entitlement, and give real transport
/// control including seeking.
final class AppleScriptMediaSource: MediaSource {
    let descriptor: PlayerDescriptor

    init(descriptor: PlayerDescriptor) {
        self.descriptor = descriptor
    }

    var kind: MediaSourceKind { descriptor.kind }

    var isAvailable: Bool {
        AppleScriptRunner.isRunning(bundleIdentifier: descriptor.bundleIdentifier)
            && !AppleScriptRunner.shared.isAuthorizationDenied
    }

    var changeNotificationNames: [String] {
        descriptor.changeNotification.map { [$0] } ?? []
    }

    // MARK: Reading

    /// Returns a typed AppleScript list rather than a delimited string on purpose: parsing
    /// numbers out of `as text` breaks under locales that use a comma decimal separator.
    private var snapshotScript: String {
        """
        if application "\(descriptor.scriptName)" is running then
            tell application "\(descriptor.scriptName)"
                try
                    set playerStateText to (player state as text)
                    if playerStateText is "stopped" then return {"stopped"}
                    set currentItem to current track
                    set shuffleState to missing value
                    \(shuffleRead)
                    return {playerStateText, (name of currentItem) as text, (artist of currentItem) as text, (album of currentItem) as text, (duration of currentItem), (player position), (id of currentItem) as text, shuffleState}
                on error
                    return {"stopped"}
                end try
            end tell
        else
            return {"stopped"}
        end if
        """
    }

    /// Reads shuffle state inside its own `try`, so a player build that lacks the property
    /// still reports the track rather than failing the whole snapshot.
    private var shuffleRead: String {
        guard let property = descriptor.shuffleStateProperty else { return "" }
        return "try\n                        set shuffleState to (\(property))\n                    end try"
    }

    #if DEBUG
    /// The snapshot script as sent, for `--check-media --scripts` to compile.
    var debugSnapshotScript: String { snapshotScript }
    #endif

    func snapshot() -> NowPlayingTrack? {
        guard isAvailable else { return nil }
        guard let result = AppleScriptRunner.shared.run(snapshotScript) else { return nil }
        guard result.numberOfItems >= 7 else { return nil }

        let state = result.atIndex(1)?.stringValue ?? "stopped"
        guard state != "stopped" else { return nil }

        let duration = (result.atIndex(5)?.doubleValue ?? 0) / descriptor.durationScale
        let elapsed = result.atIndex(6)?.doubleValue ?? 0

        return NowPlayingTrack(
            title: result.atIndex(2)?.stringValue ?? "",
            artist: result.atIndex(3)?.stringValue ?? "",
            album: result.atIndex(4)?.stringValue ?? "",
            duration: duration,
            elapsed: elapsed,
            isPlaying: state == "playing",
            sourceKind: descriptor.kind,
            sourceAppName: descriptor.displayName,
            trackIdentity: result.atIndex(7)?.stringValue ?? "",
            isShuffling: Self.bool(from: result.atIndex(8))
        )
    }

    /// A boolean from an Apple Event descriptor, or nil for `missing value` or anything else.
    private static func bool(from descriptor: NSAppleEventDescriptor?) -> Bool? {
        guard let descriptor else { return nil }
        switch descriptor.descriptorType {
        case typeTrue: return true
        case typeFalse: return false
        case typeBoolean: return descriptor.booleanValue
        default: return nil
        }
    }

    // MARK: Up Next

    func upNext(limit: Int) -> UpNextState {
        guard let template = descriptor.upNextScript else { return .idle }
        guard isAvailable else { return .unavailable("Music is not running.") }

        let script = template.replacingOccurrences(of: "LIMIT", with: String(max(limit, 1)))
        guard let result = AppleScriptRunner.shared.run(script), result.numberOfItems >= 1 else {
            return .unavailable("Up Next could not be read from Music.")
        }

        switch result.atIndex(1)?.stringValue {
        case "shuffle":
            let source = result.numberOfItems >= 2 ? (result.atIndex(2)?.stringValue ?? "") : ""
            return .unavailable(
                source.isEmpty
                    ? "Shuffling. Music doesn't share the shuffled order."
                    : "Shuffling \u{201C}\(source)\u{201D}. Music doesn't share the order."
            )
        case "ok":
            guard result.numberOfItems >= 2 else {
                return .unavailable("Nothing after this in the current playlist.")
            }
            let items: [UpNextItem] = (2...result.numberOfItems).compactMap { index in
                guard let pair = result.atIndex(index), pair.numberOfItems >= 2,
                      let title = pair.atIndex(1)?.stringValue, !title.isEmpty else { return nil }
                return UpNextItem(title: title, artist: pair.atIndex(2)?.stringValue ?? "")
            }
            return items.isEmpty ? .unavailable("Nothing after this in the current playlist.") : .loaded(items)
        default:
            return .unavailable("Up Next is only known when playing from a playlist or album.")
        }
    }

    // MARK: Artwork

    /// Fetches cover art from the URL the player hands back.
    ///
    /// That string comes out of another process over Apple Events, so it is not the user's
    /// input and it is not this app's. It was previously read with `Data(contentsOf:)`, which
    /// accepts any scheme the string parses as: a reply of `file:///…` would have had an
    /// unsandboxed app read that file off disk and try to decode it as an image. It also had
    /// no timeout and no size limit, on the serial queue every media read shares, so one slow
    /// or endless response stalled all of them. HTTPS only, capped, and timed out.
    private static let artworkHTTP = BoundedHTTPClient(maxBytes: 8_000_000, timeout: 8)

    func artwork() -> NSImage? {
        guard isAvailable else { return nil }

        if let script = descriptor.artworkScript,
           let descriptorResult = AppleScriptRunner.shared.run(script) {
            if let image = Self.image(from: descriptorResult) { return image }
        }

        if let script = descriptor.artworkURLScript,
           let urlString = AppleScriptRunner.shared.runReturningString(script),
           let url = URL(string: urlString),
           let data = Self.artworkHTTP.fetchSynchronously(url) {
            return NSImage(data: data)
        }

        return nil
    }

    /// Music returns artwork as a raw data descriptor. Some builds prefix the payload with
    /// a four byte type code, so the leading bytes are trimmed if the direct decode fails.
    private static func image(from descriptor: NSAppleEventDescriptor) -> NSImage? {
        let data = descriptor.data
        guard !data.isEmpty else { return nil }
        if let image = NSImage(data: data), image.isValid { return image }
        guard data.count > 4 else { return nil }
        return NSImage(data: data.dropFirst(4))
    }

    // MARK: Commands

    func send(_ command: MediaCommand) {
        guard isAvailable else { return }
        let name = descriptor.scriptName

        let script: String
        switch command {
        case .playPause:
            script = "tell application \"\(name)\" to playpause"
        case .play:
            script = "tell application \"\(name)\" to play"
        case .pause:
            script = "tell application \"\(name)\" to pause"
        case .nextTrack:
            script = "tell application \"\(name)\" to next track"
        case .previousTrack:
            script = "tell application \"\(name)\" to previous track"
        case .seek(let position):
            // Formatted with an explicit POSIX locale so a comma decimal separator from the
            // user's locale never reaches AppleScript.
            let value = String(format: "%.3f", position)
            script = "tell application \"\(name)\" to set player position to \(value)"
        case .toggleShuffle:
            script = descriptor.shuffleScript
        case .cycleRepeat:
            script = descriptor.repeatScript
        case .toggleFavorite:
            script = descriptor.favoriteScript
        }

        guard !script.isEmpty else { return }
        AppleScriptRunner.shared.run(script)
    }
}
