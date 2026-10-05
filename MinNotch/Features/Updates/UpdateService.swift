import AppKit
import Observation
import Sparkle

/// Finds and installs new versions of MiniNotch, with Sparkle.
///
/// The feed is `appcast.xml` in the repository (`SUFeedURL` in `Config/Info.plist`), and each of
/// its entries points at the DMG on that version's GitHub release. An update is only installed if
/// it carries a signature from the key whose public half is `SUPublicEDKey`, and, because releases
/// are signed with the same Apple team, if the new app's code signature matches this one's.
///
/// Sparkle does its own networking, the one exception to `BoundedHTTPClient`: it fetches the feed
/// and the DMG over HTTPS and refuses anything its signature check does not pass. With checking
/// on, that is one small file from GitHub a day; nothing about the Mac or its user is sent.
///
/// Not started in a Debug build. A development copy shares the bundle identifier with the real
/// app, so it would otherwise offer to replace itself with the last release. `--check-update` runs
/// a whole update end to end, against a local feed and under a separate bundle identifier.
@Observable
@MainActor
final class UpdateService: NSObject {
    /// False in a Debug build, where updates are left to Xcode.
    private(set) var isAvailable = false

    /// Sparkle's own preference, which it keeps in the defaults, mirrored so Settings redraws.
    var checksAutomatically = false {
        didSet {
            guard let updater = controller?.updater, updater.automaticallyChecksForUpdates != checksAutomatically else { return }
            updater.automaticallyChecksForUpdates = checksAutomatically
        }
    }

    @ObservationIgnored private var controller: SPUStandardUpdaterController?

    func start() {
        #if DEBUG
        isAvailable = false
        #else
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
        isAvailable = true
        #endif
    }

    /// Checks now and shows the result, whatever it is, including that there is nothing new.
    func checkForUpdates() {
        guard let controller else { return }
        // The answer is a window, and an app without a Dock icon is never in front on its own.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}

extension UpdateService: @preconcurrency SPUStandardUserDriverDelegate {
    /// MiniNotch runs in the background, so a scheduled check that finds something must bring its
    /// window forward itself; saying so also stops Sparkle warning that a background app should.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if handleShowingUpdate {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
