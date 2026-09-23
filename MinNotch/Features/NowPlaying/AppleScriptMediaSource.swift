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
    /// Expression giving repeat state as "off", "all" or "one", or nil when it cannot be read.
    var repeatStateExpression: String?
    /// Whether repeat has a "one track" setting, which decides what the button cycles through.
    var repeatSupportsOne: Bool
    /// Expression giving whether the current track is a favourite, with `currentItem` in scope,
    /// or nil for a player with no favourites to read.
    var favoriteStateExpression: String?
    /// Expression giving the current track's BPM tag, or nil for a player without one.
    var bpmExpression: String? = nil
    /// A snapshot script of the player's own, returning the same list the generic one does,
    /// for a player whose dictionary has no `player state` or `current track`.
    var snapshotScriptOverride: String? = nil
    /// Commands for a player that does not use the Music and Spotify verbs. `POSITION` in the
    /// seek script is replaced by whole seconds.
    var playPauseScript: String? = nil
    var playScript: String? = nil
    var pauseScript: String? = nil
    var seekScript: String? = nil
    /// Splits a file name such as "Artist - Title.mp3" into artist and title, for a player that
    /// knows only the file it is playing.
    var titlesFromFileName = false
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
        repeatStateExpression: "(song repeat as text)",
        repeatSupportsOne: true,
        // Favourite replaced love in Music on macOS 14; `loved` is kept as a fallback read for
        // a build that still has only that, the same way the toggle script falls back.
        favoriteStateExpression: "(favorited of currentItem)",
        bpmExpression: "(bpm of currentItem)",
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
        // Spotify's dictionary has no like or save command, so favourite is Music only.
        favoriteScript: "",
        shuffleStateProperty: "shuffling",
        repeatStateExpression: "(repeating)",
        repeatSupportsOne: false,
        favoriteStateExpression: nil,
        // Spotify's dictionary has no queue at all: current track, position, state, nothing
        // after. Up Next is Apple Music only for that reason, not by choice.
        upNextScript: nil
    )
}

extension PlayerDescriptor {
    /// VLC knows the file it is playing and nothing else: no artist, no album, no artwork, no
    /// shuffle or repeat in its dictionary. What it does have is a position that can be set,
    /// which the system Now Playing source cannot do, so it gets a descriptor of its own.
    static let vlc = PlayerDescriptor(
        kind: .vlc,
        bundleIdentifier: "org.videolan.vlc",
        displayName: "VLC",
        scriptName: "VLC",
        durationScale: 1,
        changeNotification: nil,
        artworkScript: nil,
        artworkURLScript: nil,
        shuffleScript: "",
        repeatScript: "",
        favoriteScript: "",
        shuffleStateProperty: nil,
        repeatStateExpression: nil,
        repeatSupportsOne: false,
        favoriteStateExpression: nil,
        snapshotScriptOverride: """
        if application "VLC" is running then
            tell application "VLC"
                try
                    set itemName to (name of current item) as text
                    if itemName is "" then return {"stopped"}
                    if playing then
                        set stateText to "playing"
                    else
                        set stateText to "paused"
                    end if
                    return {stateText, itemName, "", "", (duration of current item), (current time), itemName, missing value, missing value, missing value, missing value}
                on error
                    return {"stopped"}
                end try
            end tell
        else
            return {"stopped"}
        end if
        """,
        // VLC's `play` pauses when already playing, so play and pause check first.
        playPauseScript: "tell application \"VLC\" to play",
        playScript: "tell application \"VLC\" to if not playing then play",
        pauseScript: "tell application \"VLC\" to if playing then play",
        seekScript: "tell application \"VLC\" to set current time to POSITION",
        titlesFromFileName: true
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
        if let override = descriptor.snapshotScriptOverride { return override }
        return """
        if application "\(descriptor.scriptName)" is running then
            tell application "\(descriptor.scriptName)"
                try
                    set playerStateText to (player state as text)
                    if playerStateText is "stopped" then return {"stopped"}
                    set currentItem to current track
                    set shuffleState to missing value
                    set repeatState to missing value
                    set favoriteState to missing value
                    set bpmValue to missing value
                    \(optionalRead("shuffleState", descriptor.shuffleStateProperty.map { "(\($0))" }))
                    \(optionalRead("repeatState", descriptor.repeatStateExpression))
                    \(optionalRead("favoriteState", descriptor.favoriteStateExpression))
                    \(optionalRead("bpmValue", descriptor.bpmExpression))
                    return {playerStateText, (name of currentItem) as text, (artist of currentItem) as text, (album of currentItem) as text, (duration of currentItem), (player position), (id of currentItem) as text, shuffleState, repeatState, favoriteState, bpmValue}
                on error
                    return {"stopped"}
                end try
            end tell
        else
            return {"stopped"}
        end if
        """
    }

    /// Reads one optional value inside its own `try`, so a player build that lacks the
    /// property still reports the track rather than failing the whole snapshot.
    private func optionalRead(_ variable: String, _ expression: String?) -> String {
        guard let expression else { return "" }
        var read = "try\n                        set \(variable) to \(expression)\n                    end try"
        // Music builds from before favourites called it love.
        if variable == "favoriteState", descriptor.kind == .appleMusic {
            read += "\n                    if favoriteState is missing value then\n                        try\n                            set favoriteState to (loved of currentItem)\n                        end try\n                    end if"
        }
        return read
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

        var title = result.atIndex(2)?.stringValue ?? ""
        var artist = result.atIndex(3)?.stringValue ?? ""
        if descriptor.titlesFromFileName {
            (title, artist) = Self.titles(fromFileName: title)
        }

        return NowPlayingTrack(
            title: title,
            artist: artist,
            album: result.atIndex(4)?.stringValue ?? "",
            duration: duration,
            elapsed: elapsed,
            isPlaying: state == "playing",
            sourceKind: descriptor.kind,
            sourceAppName: descriptor.displayName,
            sourceBundleIdentifier: descriptor.bundleIdentifier,
            trackIdentity: result.atIndex(7)?.stringValue ?? "",
            isShuffling: Self.bool(from: result.atIndex(8)),
            repeatMode: Self.repeatMode(from: result.numberOfItems >= 9 ? result.atIndex(9) : nil),
            isFavorite: result.numberOfItems >= 10 ? Self.bool(from: result.atIndex(10)) : nil,
            // Zero is Music's "no tag", not a tempo.
            beatsPerMinute: result.numberOfItems >= 11
                ? result.atIndex(11).map { Double($0.int32Value) }.flatMap { $0 > 0 ? $0 : nil }
                : nil
        )
    }

    /// "Artist - Title.mp3" as a title and an artist, or the name without its extension as the
    /// title when it has no separator. Only ever a guess, which is why only VLC gets it.
    static func titles(fromFileName name: String) -> (title: String, artist: String) {
        let known: Set<String> = ["mp3", "m4a", "aac", "flac", "wav", "ogg", "opus", "aiff", "mp4", "mkv", "mov", "avi", "webm"]
        let ext = (name as NSString).pathExtension.lowercased()
        let stem = known.contains(ext) ? (name as NSString).deletingPathExtension : name
        let parts = stem.components(separatedBy: " - ")
        guard parts.count >= 2 else { return (stem, "") }
        let artist = parts[0].trimmingCharacters(in: .whitespaces)
        let title = parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
        return title.isEmpty || artist.isEmpty ? (stem, "") : (title, artist)
    }

    /// Music answers with its constant's name, Spotify with a boolean.
    private static func repeatMode(from descriptor: NSAppleEventDescriptor?) -> RepeatMode? {
        guard let descriptor else { return nil }
        if let flag = bool(from: descriptor) { return flag ? .all : .off }
        return descriptor.stringValue.flatMap { RepeatMode(rawValue: $0.lowercased()) }
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
            script = descriptor.playPauseScript ?? "tell application \"\(name)\" to playpause"
        case .play:
            script = descriptor.playScript ?? "tell application \"\(name)\" to play"
        case .pause:
            script = descriptor.pauseScript ?? "tell application \"\(name)\" to pause"
        case .nextTrack:
            script = descriptor.kind == .vlc ? "tell application \"VLC\" to next" : "tell application \"\(name)\" to next track"
        case .previousTrack:
            script = descriptor.kind == .vlc ? "tell application \"VLC\" to previous" : "tell application \"\(name)\" to previous track"
        case .seek(let position):
            if let template = descriptor.seekScript {
                // VLC takes whole seconds.
                script = template.replacingOccurrences(of: "POSITION", with: String(Int(position.rounded())))
                break
            }
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
