import AppKit

/// Generic now playing source backed by MediaRemote, covering every app rather than just
/// the two scriptable players.
///
/// The MediaRemote payload arrives asynchronously, so the source keeps the most recent
/// one and answers `snapshot()` from that cache. Elapsed time is extrapolated from the
/// payload's timestamp and playback rate, which is what makes a scrubber move smoothly
/// between payloads instead of stepping once a second.
final class SystemNowPlayingSource: MediaSource {
    let kind: MediaSourceKind = .system

    private var cached: NowPlayingTrack?
    private var cachedArtwork: NSImage?
    private var cachedArtworkKey: String?
    private var elapsedAtTimestamp: TimeInterval = 0
    private var payloadTimestamp: Date?
    private var playbackRate: Double = 0

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
        bridge.requestNowPlayingInfo { [weak self] information in
            self?.apply(information)
            completion?()
        }
    }

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
            sourceAppName: Self.nowPlayingApplicationName(),
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
        guard var track = cached else { return nil }
        // Advance the position between payloads so the scrubber is continuous.
        if playbackRate > 0, let payloadTimestamp {
            let advanced = elapsedAtTimestamp + Date().timeIntervalSince(payloadTimestamp) * playbackRate
            track.elapsed = track.duration > 0 ? min(advanced, track.duration) : advanced
        }
        return track
    }

    func artwork() -> NSImage? { cachedArtwork }

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
