import AppKit

/// Generic now playing source backed by MediaRemote, covering every app rather than just
/// the two scriptable players.
///
/// The MediaRemote payload arrives asynchronously, so the source keeps the most recent
/// one and answers `snapshot()` from that cache. Elapsed time is extrapolated from the
/// payload's timestamp and playback rate, which is what makes a scrubber move smoothly
/// between payloads instead of stepping once a second.
///
/// Unchecked `Sendable`, with the cache behind `lock`: payloads arrive on the main queue while
/// `snapshot()` and `artwork()` are read on the AppleScript queue with every other source.
final class SystemNowPlayingSource: MediaSource, @unchecked Sendable {
    let kind: MediaSourceKind = .system

    private let lock = NSLock()

    private var cached: NowPlayingTrack?
    private var cachedArtwork: NSImage?
    private var cachedArtworkKey: String?
    private var elapsedAtTimestamp: TimeInterval = 0
    private var payloadTimestamp: Date?
    private var playbackRate: Double = 0
    /// The app MediaRemote says owns playback, asked for alongside each payload.
    private var owner: NSRunningApplication?

    private let bridge = MediaRemoteBridge.shared

    var isAvailable: Bool { bridge.isFrameworkLoaded }

    /// Whether this build is actually permitted to read the payload. False here with
    /// `isAvailable` true means the framework loaded but the entitlement check refused us,
    /// which Settings > Media surfaces rather than silently showing an empty card.
    var isPermitted: Bool { bridge.hasEverReceivedPayload }

    var changeNotificationNames: [String] {
        [MediaRemoteBridge.NotificationName.infoDidChange,
         MediaRemoteBridge.NotificationName.playbackDidChange]
    }

    /// Kicks off an asynchronous refresh. Called from the controller's poll.
    func refresh(completion: (() -> Void)? = nil) {
        bridge.requestNowPlayingApplicationPID { [weak self] pid in
            let owner = pid.flatMap(NSRunningApplication.init(processIdentifier:))
            self?.lock.withLock { self?.owner = owner }
            self?.bridge.requestNowPlayingInfo { [weak self] information in
                self?.lock.withLock { self?.apply(information) }
                completion?()
            }
        }
    }

    /// Called with `lock` held.
    private func apply(_ information: [String: Any]?) {
        guard let information, !information.isEmpty else {
            cached = nil
            return
        }

        let title = information[MediaRemoteBridge.InfoKey.title] as? String ?? ""
        guard !title.isEmpty else { cached = nil; return }

        let duration = information[MediaRemoteBridge.InfoKey.duration] as? Double ?? 0
        let elapsed = information[MediaRemoteBridge.InfoKey.elapsedTime] as? Double ?? 0
        let rate = information[MediaRemoteBridge.InfoKey.playbackRate] as? Double ?? 0

        elapsedAtTimestamp = elapsed
        payloadTimestamp = information[MediaRemoteBridge.InfoKey.timestamp] as? Date ?? Date()
        playbackRate = rate

        let identity = information[MediaRemoteBridge.InfoKey.uniqueIdentifier]
            .map { String(describing: $0) } ?? title

        cached = NowPlayingTrack(
            title: title,
            artist: information[MediaRemoteBridge.InfoKey.artist] as? String ?? "",
            album: information[MediaRemoteBridge.InfoKey.album] as? String ?? "",
            duration: duration,
            elapsed: elapsed,
            isPlaying: rate > 0,
            sourceKind: .system,
            sourceAppName: owner?.localizedName ?? Self.nowPlayingApplicationName(),
            sourceBundleIdentifier: owner?.bundleIdentifier,
            trackIdentity: identity
        )

        if let data = information[MediaRemoteBridge.InfoKey.artworkData] as? Data,
           let image = NSImage(data: data) {
            cachedArtwork = image
            cachedArtworkKey = cached?.artworkKey
        } else if cachedArtworkKey != cached?.artworkKey {
            cachedArtwork = nil
        }
    }

    func snapshot() -> NowPlayingTrack? {
        lock.lock()
        defer { lock.unlock() }
        guard var track = cached else { return nil }
        // Advance the position between payloads so the scrubber is continuous.
        if playbackRate > 0, let payloadTimestamp {
            let advanced = elapsedAtTimestamp + Date().timeIntervalSince(payloadTimestamp) * playbackRate
            track.elapsed = track.duration > 0 ? min(advanced, track.duration) : advanced
        }
        return track
    }

    func artwork() -> NSImage? { lock.withLock { cachedArtwork } }

    func send(_ command: MediaCommand) {
        switch command {
        case .playPause: bridge.send(.togglePlayPause)
        case .play: bridge.send(.play)
        case .pause: bridge.send(.pause)
        case .nextTrack: bridge.send(.nextTrack)
        case .previousTrack: bridge.send(.previousTrack)
        // MediaRemote seeking and the shuffle, repeat, and favourite commands need
        // per-command payloads that vary by client, so they stay unimplemented rather
        // than silently doing nothing surprising. Scriptable players handle them.
        case .seek, .toggleShuffle, .cycleRepeat, .toggleFavorite:
            break
        }
    }

    /// Best-effort name of the app that owns playback, used as the card's subtitle.
    private static func nowPlayingApplicationName() -> String {
        NSWorkspace.shared.runningApplications
            .first { $0.isActive && $0.activationPolicy == .regular }?
            .localizedName ?? "System"
    }
}
