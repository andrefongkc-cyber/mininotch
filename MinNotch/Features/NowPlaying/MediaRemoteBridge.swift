import AppKit

/// Thin wrapper around the private MediaRemote framework.
///
/// This is the only way to read now playing information from apps that are not
/// scriptable, which is most of them: browsers, VLC, podcast clients. It is loaded at
/// runtime with `dlopen` rather than linked, so a future macOS release that removes or
/// renames the symbols degrades to "system source unavailable" instead of failing to launch.
///
/// Two caveats drive the design. Recent macOS releases gate the now playing functions
/// behind a private entitlement, so an unentitled build may load the framework
/// successfully and still never receive a payload; `hasEverReceivedPayload` distinguishes
/// those cases so the UI can say so honestly. And private API cannot ship to the Mac App
/// Store, so this whole source is behind a capability check that the App Store build
/// simply reports as unavailable.
final class MediaRemoteBridge {
    static let shared = MediaRemoteBridge()

    private typealias GetNowPlayingInfoFunction = @convention(c) (
        DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void
    ) -> Void
    private typealias SendCommandFunction = @convention(c) (Int, CFDictionary?) -> Bool
    private typealias RegisterNotificationsFunction = @convention(c) (DispatchQueue) -> Void

    /// MediaRemote command codes.
    enum Command: Int {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    private var handle: UnsafeMutableRawPointer?
    private var getNowPlayingInfo: GetNowPlayingInfoFunction?
    private var sendCommandFunction: SendCommandFunction?
    private var registerForNotifications: RegisterNotificationsFunction?

    /// True when the framework loaded and both symbols resolved.
    private(set) var isFrameworkLoaded = false
    /// True once a non-empty payload has actually arrived, which is the real test of whether
    /// this build is allowed to read now playing information.
    private(set) var hasEverReceivedPayload = false

    private init() { load() }

    private func load() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_NOW) else {
            AppLog.media.info("MediaRemote is not present; the system source is unavailable")
            return
        }
        self.handle = handle

        guard let infoSymbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo"),
              let commandSymbol = dlsym(handle, "MRMediaRemoteSendCommand")
        else {
            AppLog.media.info("MediaRemote symbols are unavailable on this macOS version")
            return
        }

        getNowPlayingInfo = unsafeBitCast(infoSymbol, to: GetNowPlayingInfoFunction.self)
        sendCommandFunction = unsafeBitCast(commandSymbol, to: SendCommandFunction.self)

        if let registerSymbol = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            registerForNotifications = unsafeBitCast(registerSymbol, to: RegisterNotificationsFunction.self)
            registerForNotifications?(DispatchQueue.main)
        }

        isFrameworkLoaded = true
    }

    /// Asks for the current payload. The completion runs on the main queue.
    func requestNowPlayingInfo(_ completion: @escaping ([String: Any]?) -> Void) {
        guard let getNowPlayingInfo else { completion(nil); return }
        getNowPlayingInfo(DispatchQueue.main) { [weak self] information in
            let dictionary = information as? [String: Any]
            if let dictionary, !dictionary.isEmpty { self?.hasEverReceivedPayload = true }
            completion(dictionary)
        }
    }

    @discardableResult
    func send(_ command: Command) -> Bool {
        guard let sendCommandFunction else { return false }
        return sendCommandFunction(command.rawValue, nil)
    }

    /// Names of the notifications MediaRemote posts once registered.
    enum NotificationName {
        static let infoDidChange = "kMRMediaRemoteNowPlayingInfoDidChangeNotification"
        static let playbackDidChange = "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"
    }

    /// Keys inside the now playing payload.
    enum InfoKey {
        static let title = "kMRMediaRemoteNowPlayingInfoTitle"
        static let artist = "kMRMediaRemoteNowPlayingInfoArtist"
        static let album = "kMRMediaRemoteNowPlayingInfoAlbum"
        static let duration = "kMRMediaRemoteNowPlayingInfoDuration"
        static let elapsedTime = "kMRMediaRemoteNowPlayingInfoElapsedTime"
        static let timestamp = "kMRMediaRemoteNowPlayingInfoTimestamp"
        static let artworkData = "kMRMediaRemoteNowPlayingInfoArtworkData"
        static let playbackRate = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
        static let uniqueIdentifier = "kMRMediaRemoteNowPlayingInfoUniqueIdentifier"
    }
}
