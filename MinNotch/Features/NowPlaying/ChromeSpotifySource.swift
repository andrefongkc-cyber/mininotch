import AppKit

/// Spotify's web player, open.spotify.com, playing in a Google Chrome tab.
///
/// Chrome's dictionary lists every tab's URL and title, which is enough to find the tab and,
/// from a title like "Song • Artist", what is playing. Everything else (artwork, position,
/// playing or paused, and the buttons) comes from running a line of JavaScript in that tab,
/// which Chrome allows only once View > Developer > Allow JavaScript from Apple Events is on.
/// Without it the card shows the title and artist and nothing can be pressed; with it, it
/// reads the page's `navigator.mediaSession` and clicks Spotify's own buttons. Seeking is
/// left out: the page's slider ignores a value set from outside.
///
/// Asking Chrome is its own Automation permission, refused separately (`scope`), so turning
/// Chrome down never stops Music or Spotify.
/// `@unchecked Sendable`: everything here runs on `AppleScriptRunner.shared.queue`, which is where
/// the controller calls every source.
final class ChromeSpotifySource: MediaSource, @unchecked Sendable {
    static let bundleIdentifier = "com.google.Chrome"
    private static let scope = "chrome"

    var kind: MediaSourceKind { .chromeSpotify }

    var isAvailable: Bool {
        AppleScriptRunner.isRunning(bundleIdentifier: Self.bundleIdentifier)
            && !AppleScriptRunner.shared.isDenied(scope: Self.scope)
    }

    /// Single quotes only, so it can sit inside an AppleScript string as it is.
    private static let readScript = """
    (function(){var m=navigator.mediaSession,d=m&&m.metadata;\
    function t(i){var e=document.querySelector('[data-testid='+i+']');return e?e.textContent:''}\
    var a='';if(d&&d.artwork&&d.artwork.length){a=d.artwork[d.artwork.length-1].src}\
    var p=document.querySelector('[data-testid=control-button-playpause]');\
    return JSON.stringify({title:d?d.title:'',artist:d?d.artist:'',album:d?d.album:'',art:a,\
    state:m?m.playbackState:'',label:p?(p.getAttribute('aria-label')||''):'',\
    pos:t('playback-position'),dur:t('playback-duration')})})()
    """

    /// Runs `javascript` in the first Spotify tab, returning the tab's title and the result.
    private static func inSpotifyTab(_ javascript: String?) -> String {
        let run = javascript.map { "set pageInfo to execute t javascript \"\($0)\"" } ?? ""
        return """
        if application id "\(bundleIdentifier)" is running then
            tell application id "\(bundleIdentifier)"
                repeat with w in windows
                    repeat with t in tabs of w
                        if (URL of t) contains "open.spotify.com" then
                            set pageInfo to ""
                            try
                                \(run)
                            end try
                            return {(title of t) as text, pageInfo as text}
                        end if
                    end repeat
                end repeat
            end tell
        end if
        return {}
        """
    }

    private struct PageState: Decodable {
        var title: String
        var artist: String
        var album: String
        var art: String
        var state: String
        var label: String
        var pos: String
        var dur: String
    }

    private var lastArtworkURL: String?

    func snapshot() -> NowPlayingTrack? {
        guard isAvailable,
              let result = AppleScriptRunner.shared.run(Self.inSpotifyTab(Self.readScript), scope: Self.scope),
              result.numberOfItems >= 2
        else { return nil }
        let tabTitle = result.atIndex(1)?.stringValue ?? ""
        let json = result.atIndex(2)?.stringValue ?? ""

        if let data = json.data(using: .utf8),
           let page = try? JSONDecoder().decode(PageState.self, from: data),
           !page.title.isEmpty {
            lastArtworkURL = page.art
            let position = Self.seconds(page.pos) ?? 0
            var duration = Self.seconds(page.dur) ?? 0
            // Spotify can show the time left instead, as "-2:31".
            if page.dur.hasPrefix("-") { duration = position + abs(duration) }
            let label = page.label.lowercased()
            let playing = page.state == "playing" || (page.state != "paused" && label.hasPrefix("pause"))
            return NowPlayingTrack(
                title: page.title, artist: page.artist, album: page.album,
                duration: duration, elapsed: position, isPlaying: playing,
                sourceKind: .chromeSpotify, sourceAppName: "Spotify in Chrome",
                sourceBundleIdentifier: Self.bundleIdentifier,
                trackIdentity: "\(page.artist)|\(page.title)"
            )
        }

        // No JavaScript allowed: the tab's title says "Song • Artist" while a song is loaded.
        lastArtworkURL = nil
        let parts = tabTitle.components(separatedBy: " • ")
        guard parts.count >= 2, !parts[0].isEmpty else { return nil }
        return NowPlayingTrack(
            title: parts[0], artist: parts[1...].joined(separator: " • "), album: "",
            duration: 0, elapsed: 0, isPlaying: true,
            sourceKind: .chromeSpotify, sourceAppName: "Spotify in Chrome",
            sourceBundleIdentifier: Self.bundleIdentifier,
            trackIdentity: tabTitle
        )
    }

    /// "1:23" or "1:02:03" as seconds, ignoring a leading minus.
    static func seconds(_ text: String) -> TimeInterval? {
        let parts = text.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    private static let artworkHTTP = BoundedHTTPClient(maxBytes: 8_000_000, timeout: 8)

    func artwork() -> NSImage? {
        guard let string = lastArtworkURL, let url = URL(string: string),
              let data = Self.artworkHTTP.fetchSynchronously(url) else { return nil }
        return NSImage(data: data)
    }

    func send(_ command: MediaCommand) {
        guard isAvailable else { return }
        let button: String
        switch command {
        case .playPause, .play, .pause: button = "control-button-playpause"
        case .nextTrack: button = "control-button-skip-forward"
        case .previousTrack: button = "control-button-skip-back"
        case .toggleShuffle: button = "control-button-shuffle"
        case .cycleRepeat: button = "control-button-repeat"
        case .seek, .toggleFavorite: return
        }
        let click = "(function(){var b=document.querySelector('[data-testid=\(button)]');if(b){b.click()}return ''})()"
        AppleScriptRunner.shared.run(Self.inSpotifyTab(click), scope: Self.scope)
    }
}
