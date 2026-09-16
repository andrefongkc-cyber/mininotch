import AppKit
import Observation

/// Owns media state for the whole app: picks a source, keeps it fresh, and forwards
/// transport commands.
///
/// Freshness comes from two places. The scriptable players and MediaRemote both post
/// distributed notifications when playback changes, which covers track changes instantly.
/// A slow timer covers the position, which nothing broadcasts. Between polls the view
/// extrapolates from `elapsed(at:)`, so the scrubber is smooth without a fast timer.
@Observable
final class NowPlayingController {
    private(set) var track: NowPlayingTrack?
    private(set) var artwork: NSImage?
    private(set) var palette: ArtworkPalette = .fallback
    private(set) var lyrics: Lyrics?
    /// Why the lyric strip looks the way it does. Without this the strip silently renders
    /// nothing when a lookup fails, which is indistinguishable from the feature being broken.
    private(set) var lyricsStatus: LyricsStatus = .idle
    /// The next few tracks, or why they cannot be listed. Apple Music only.
    private(set) var upNext: UpNextState = .idle

    /// True while the user is dragging the scrubber, so incoming positions are ignored
    /// until they let go and the seek lands.
    var isScrubbing = false {
        didSet { if !isScrubbing { scrubTarget = nil } }
    }
    /// Position the user is dragging towards, in seconds.
    var scrubTarget: TimeInterval?

    /// Supplies the current output device's buffering, when the audio tap is running.
    ///
    /// A closure rather than a reference to the analyser, so the media layer does not depend
    /// on the ambient lighting feature existing.
    @ObservationIgnored var audioLatencyProvider: (() -> TimeInterval?)?

    /// Fired when a genuinely different track starts. Wired to the sneak-peek animation.
    @ObservationIgnored var onTrackChange: ((NowPlayingTrack) -> Void)?

    @ObservationIgnored private let appleMusic = AppleScriptMediaSource(descriptor: .appleMusic)
    @ObservationIgnored private let spotify = AppleScriptMediaSource(descriptor: .spotify)
    @ObservationIgnored private let system = SystemNowPlayingSource()
    @ObservationIgnored private let lyricsProviders: [LyricsProviding] = [AppleMusicLyricsProvider()]

    @ObservationIgnored private var settings: SettingsStore?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observerTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var lastTrackIdentity: String?
    @ObservationIgnored private var snapshotDate = Date()
    @ObservationIgnored private var loadedLyricsKey: String?

    /// Source that most recently reported a track, used to stay on one player when both
    /// are open and one is merely paused.
    @ObservationIgnored private var stickySource: MediaSourceKind?

    init() {}

    // MARK: Lifecycle

    func start(settings: SettingsStore) {
        self.settings = settings
        observeSourceNotifications()
        restartTimer()
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for token in observerTokens {
            DistributedNotificationCenter.default().removeObserver(token)
        }
        observerTokens.removeAll()
    }

    /// Called when Settings > Media changes, since the poll interval and preferred source
    /// both live there.
    func settingsChanged() {
        // Switching the online lookup off also forgets what it found. The cache is a record
        // of songs looked up online, and turning that off is the user saying they would
        // rather it had not happened, not merely that it should stop.
        if let settings, !settings.media.lyricsSource.usesNetwork {
            LyricsCache.shared.removeAll()
        }
        restartTimer()
        refresh()
    }

    private func restartTimer() {
        timer?.invalidate()
        guard let settings, settings.media.enabled else { return }

        let interval = max(0.5, settings.media.pollInterval)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // Common mode so the position keeps updating while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func observeSourceNotifications() {
        let center = DistributedNotificationCenter.default()
        let names = appleMusic.changeNotificationNames
            + spotify.changeNotificationNames
            + system.changeNotificationNames

        for name in names {
            let token = center.addObserver(
                forName: Notification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refresh()
            }
            observerTokens.append(token)
        }
    }

    // MARK: Refresh

    func refresh() {
        guard let settings, settings.media.enabled else {
            if track != nil { clear() }
            return
        }

        // MediaRemote answers asynchronously, so kick it off before the synchronous work.
        system.refresh()

        AppleScriptRunner.shared.queue.async { [weak self] in
            guard let self else { return }
            let preferred = settings.media.preferredSource
            let candidates = self.orderedSources(for: preferred)

            var chosen: (MediaSource, NowPlayingTrack)?
            for source in candidates {
                guard source.isAvailable, let snapshot = source.snapshot() else { continue }
                if snapshot.isPlaying { chosen = (source, snapshot); break }
                if chosen == nil { chosen = (source, snapshot) }
            }

            // Stamped here, on the queue that did the reading, rather than on main after the
            // hop. An Apple Event round trip costs a hundred milliseconds or more, and
            // timestamping the value on arrival rather than at capture makes every later
            // extrapolation that much late. It is why the lyric highlight trailed the vocal.
            let capturedAt = Date()
            let result = chosen
            DispatchQueue.main.async { self.publish(result, capturedAt: capturedAt) }
        }
    }

    /// Candidate sources in priority order.
    ///
    /// Under `.auto` the source that last reported a track is tried first, so a paused
    /// Spotify does not lose the card to a stopped Music the moment playback stops.
    private func orderedSources(for preferred: MediaSourceKind) -> [MediaSource] {
        switch preferred {
        case .appleMusic: return [appleMusic]
        case .spotify: return [spotify]
        case .system: return [system]
        case .auto:
            var sources: [MediaSource] = [appleMusic, spotify, system]
            if let stickySource, let index = sources.firstIndex(where: { $0.kind == stickySource }) {
                let sticky = sources.remove(at: index)
                sources.insert(sticky, at: 0)
            }
            return sources
        }
    }

    private func publish(_ result: (MediaSource, NowPlayingTrack)?, capturedAt: Date) {
        guard let (source, snapshot) = result else {
            clear()
            return
        }

        stickySource = source.kind
        snapshotDate = capturedAt

        let isNewTrack = snapshot.trackIdentity != lastTrackIdentity
            || snapshot.artworkKey != track?.artworkKey

        var published = snapshot
        // Hold the user's drag position until the seek round-trips.
        if isScrubbing, let scrubTarget { published.elapsed = scrubTarget }
        track = published

        guard isNewTrack else { return }
        lastTrackIdentity = snapshot.trackIdentity
        onTrackChange?(snapshot)
        loadArtwork(from: source, for: snapshot)
        loadLyrics(for: snapshot)
        loadUpNext(from: source, for: snapshot)
    }

    // MARK: Up Next

    /// How many upcoming tracks the row reads. Three is what fits on one line after the first.
    static let upNextLimit = 3

    /// Whether the card should reserve and draw its Up Next row right now.
    ///
    /// Read by the card and by both surfaces that size it, so the row's height is only ever
    /// counted when the row is actually there.
    var showsUpNext: Bool {
        guard let settings, settings.media.showUpNext, settings.media.enabled else { return false }
        return track?.sourceKind == .appleMusic
    }

    /// Reads the queue once per track, not once per poll.
    ///
    /// The read is a separate Apple Event round trip that walks the playlist, so doing it on
    /// every position poll would cost a tenth of a second on the queue every media read
    /// shares. The queue only changes when the track does, or when shuffle is flipped.
    private func loadUpNext(from source: MediaSource, for snapshot: NowPlayingTrack) {
        guard showsUpNext else {
            upNext = .idle
            return
        }
        let key = snapshot.artworkKey
        AppleScriptRunner.shared.queue.async { [weak self] in
            let state = source.upNext(limit: Self.upNextLimit)
            DispatchQueue.main.async {
                guard let self, self.track?.artworkKey == key else { return }
                self.upNext = state
            }
        }
    }

    private func clear() {
        upNext = .idle
        track = nil
        artwork = nil
        palette = .fallback
        lyrics = nil
        lastTrackIdentity = nil
        loadedLyricsKey = nil
    }

    // MARK: Artwork and lyrics

    /// Fetches artwork, retrying while the track stays the same.
    ///
    /// Players publish a track's metadata before its artwork has finished decoding, so the
    /// first read often comes back empty. That is most visible when a track starts on its
    /// own, because autoplay gives the player no head start the way pressing play does.
    /// Without the retry, one empty read left that track with no artwork for its whole
    /// duration.
    private func loadArtwork(from source: MediaSource, for snapshot: NowPlayingTrack, attempt: Int = 0) {
        let key = snapshot.artworkKey

        AppleScriptRunner.shared.queue.async { [weak self] in
            let image = source.artwork()
            let palette = image.map(ArtworkPalette.extract(from:)) ?? .fallback

            DispatchQueue.main.async {
                guard let self, self.track?.artworkKey == key else { return }

                if let image {
                    self.artwork = image
                    self.palette = palette
                    return
                }

                // Clear straight away rather than leaving the previous album's cover up,
                // which would be wrong rather than merely missing.
                if attempt == 0 {
                    self.artwork = nil
                    self.palette = .fallback
                }

                guard attempt < Self.artworkRetryLimit else { return }
                let delay = 0.5 * Double(attempt + 1)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    guard self.track?.artworkKey == key else { return }
                    self.loadArtwork(from: source, for: snapshot, attempt: attempt + 1)
                }
            }
        }
    }

    /// Four retries over roughly five seconds, which covers a slow decode without hammering
    /// the player for a track that genuinely has no cover.
    private static let artworkRetryLimit = 4

    private func loadLyrics(for snapshot: NowPlayingTrack) {
        guard let settings, settings.media.showLyrics, FeatureFlag.lyrics.isEnabled else {
            lyrics = nil
            lyricsStatus = .idle
            return
        }

        let key = snapshot.artworkKey
        guard loadedLyricsKey != key else { return }
        loadedLyricsKey = key
        lyrics = nil
        lyricsStatus = .searching

        let allowsOnline = settings.media.lyricsSource.usesNetwork

        // The player is asked first either way: a locally tagged sheet is instant, exact,
        // and costs no network request.
        AppleScriptRunner.shared.queue.async { [weak self] in
            guard let self else { return }
            let local = self.lyricsProviders.lazy.compactMap { $0.lyrics(for: snapshot) }.first

            DispatchQueue.main.async {
                guard self.track?.artworkKey == key else { return }

                if let local, !local.isEmpty {
                    self.lyrics = local
                    self.lyricsStatus = .loaded
                    return
                }

                guard allowsOnline else {
                    self.lyricsStatus = .noneStoredLocally
                    return
                }

                LRCLIBClient.shared.lyrics(for: snapshot) { found in
                    guard self.track?.artworkKey == key else { return }
                    if let found, !found.isEmpty {
                        self.lyrics = found
                        self.lyricsStatus = .loaded
                    } else {
                        self.lyricsStatus = .notFound
                    }
                }
            }
        }
    }

    /// Re-runs lyric loading after the setting is switched on mid-track.
    func reloadLyricsIfNeeded() {
        guard let track else { return }
        loadedLyricsKey = nil
        loadLyrics(for: track)
    }

    // MARK: Position

    /// Playback position at `date`, extrapolated from the last snapshot.
    func elapsed(at date: Date = Date()) -> TimeInterval {
        guard let track else { return 0 }
        if isScrubbing, let scrubTarget { return scrubTarget }
        guard track.isPlaying else { return track.elapsed }

        let advanced = track.elapsed + date.timeIntervalSince(snapshotDate)
        guard track.hasDuration else { return max(advanced, 0) }
        return min(max(advanced, 0), track.duration)
    }

    /// Position to line lyrics up against.
    ///
    /// Separate from `elapsed(at:)` because the offset must not move the scrubber. Lyric
    /// files are transcribed by hand and their timings vary by seconds between sources, so
    /// the correction is per-user rather than something that can be derived.
    func lyricsTime(at date: Date = Date()) -> TimeInterval {
        var time = elapsed(at: date) + (settings?.media.lyricsOffset ?? 0)

        // What the player reports is what it has handed to the output device, not what is
        // audible. Bluetooth and AirPlay buffer for tens to hundreds of milliseconds, so the
        // line that matches what is being heard is that much earlier.
        if settings?.media.useAudioClockForLyrics == true, let latency = audioLatencyProvider?() {
            time -= latency
        }
        return time
    }

    /// Buffering currently being compensated for, in seconds. Zero when the tap is not
    /// running or the compensation is switched off.
    var lyricsLatencyCompensation: TimeInterval {
        guard settings?.media.useAudioClockForLyrics == true else { return 0 }
        return audioLatencyProvider?() ?? 0
    }

    func progress(at date: Date = Date()) -> Double {
        guard let track, track.hasDuration else { return 0 }
        return min(max(elapsed(at: date) / track.duration, 0), 1)
    }

    // MARK: Commands

    func send(_ command: MediaCommand) {
        guard let kind = track?.sourceKind ?? stickySource else { return }
        let source = sourceFor(kind)

        // Shuffle is shown flipped at once and confirmed by the read-back below. Waiting for
        // the round trip left the button looking unresponsive for a noticeable beat.
        if command == .toggleShuffle, let current = track?.isShuffling {
            track?.isShuffling = !current
        }

        AppleScriptRunner.shared.queue.async { [weak self] in
            source.send(command)
            // Read back promptly so the button state reflects reality rather than a guess.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard let self else { return }
                self.refresh()
                // Shuffle changes what plays next, so the queue has to be read again.
                if command == .toggleShuffle, let track = self.track {
                    self.loadUpNext(from: source, for: track)
                }
            }
        }
    }

    func seek(to position: TimeInterval) {
        guard let track, track.hasDuration else { return }
        let clamped = min(max(position, 0), track.duration)
        scrubTarget = clamped
        send(.seek(clamped))
    }

    /// Whether the active source can seek. MediaRemote clients cannot, so the scrubber
    /// renders as a read-only progress bar for them rather than pretending to work.
    var canSeek: Bool {
        switch track?.sourceKind {
        case .appleMusic, .spotify: return true
        default: return false
        }
    }

    /// Whether a control is backed by a real command for the active source.
    func supports(_ control: MediaControl) -> Bool {
        guard control.isImplemented else { return false }
        switch control {
        case .shuffle:
            // Only the scriptable players have a shuffle to flip; MediaRemote clients do not.
            return track?.sourceKind == .appleMusic || track?.sourceKind == .spotify
        default:
            return true
        }
    }

    private func sourceFor(_ kind: MediaSourceKind) -> MediaSource {
        switch kind {
        case .appleMusic: return appleMusic
        case .spotify: return spotify
        case .system, .auto: return system
        }
    }

    /// Reported in Settings > Media so a user can see why the system source is empty.
    var systemSourceStatus: String {
        if !system.isAvailable { return "Unavailable on this version of macOS" }
        if !system.isPermitted { return "Loaded, but macOS has not returned any track yet" }
        return "Available"
    }
}

#if DEBUG
extension NowPlayingController {
    /// Injects a fixed track and artwork for offscreen design review.
    /// `settings` is attached without starting anything, so a capture can see the settings-
    /// dependent parts of the card, such as whether Up Next shows, without the controller
    /// polling the real player and replacing the sample with whatever is actually playing.
    func applySample(settings: SettingsStore? = nil) {
        if let settings { self.settings = settings }
        track = NowPlayingTrack(
            title: "Weightless in the Blue Hour",
            artist: "Aoife Lennox",
            album: "Slow Cartography",
            duration: 254,
            elapsed: 97,
            isPlaying: true,
            sourceKind: .appleMusic,
            sourceAppName: "Music",
            trackIdentity: "sample",
            isShuffling: false
        )
        upNext = .loaded([
            UpNextItem(title: "Paper Lanterns", artist: "Aoife Lennox"),
            UpNextItem(title: "Low Tide Radio", artist: "Aoife Lennox"),
            UpNextItem(title: "Everything Is Quiet Here", artist: "Aoife Lennox")
        ])

        // A flat two-tone square stands in for artwork; it exercises the same layout and
        // the same palette extraction path as a real cover would.
        let size = NSSize(width: 300, height: 300)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGradient(
            starting: NSColor(srgbRed: 0.24, green: 0.30, blue: 0.62, alpha: 1),
            ending: NSColor(srgbRed: 0.83, green: 0.36, blue: 0.35, alpha: 1)
        )?.draw(in: NSRect(origin: .zero, size: size), angle: 45)
        image.unlockFocus()

        snapshotDate = Date()
        artwork = image
        palette = ArtworkPalette.extract(from: image)
        // Parsed from LRC rather than built by hand, so a preview exercises the same word
        // timing path a real track goes through.
        lyrics = LRCParser.parse(
            """
            [01:30.00] The harbour lights go out one at a time
            [01:36.00] And nothing here is asking me to stay
            [01:43.00] I have been counting hours like they were mine
            [01:50.00] So take the morning, I was never going to use it
            """
        )
    }
}
#endif
