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
        favoriteScript: ""
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
                    return {playerStateText, (name of currentItem) as text, (artist of currentItem) as text, (album of currentItem) as text, (duration of currentItem), (player position), (id of currentItem) as text}
                on error
                    return {"stopped"}
                end try
            end tell
        else
            return {"stopped"}
        end if
        """
    }

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
            trackIdentity: result.atIndex(7)?.stringValue ?? ""
        )
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
