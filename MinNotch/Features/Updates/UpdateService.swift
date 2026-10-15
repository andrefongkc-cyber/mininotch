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
/// on, that is one small file from GitHub every three hours, or as often as Settings > About > How
/// Often says; nothing about the Mac or its user is sent.
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
            if let updater = controller?.updater, updater.automaticallyChecksForUpdates != checksAutomatically {
                updater.automaticallyChecksForUpdates = checksAutomatically
            }
        }
    }

    /// Seconds between scheduled checks: Settings > About > How Often. Sparkle keeps it in the
    /// defaults (`SUScheduledCheckInterval`, whose default in `Config/Info.plist` is three hours).
    var checkInterval: TimeInterval = UpdateService.defaultInterval {
        didSet {
            if let updater = controller?.updater, updater.updateCheckInterval != checkInterval {
                updater.updateCheckInterval = checkInterval
            }
        }
    }

    static let defaultInterval: TimeInterval = 3 * 3600

    /// From an hour to a week. The user asked for half an hour at the short end, but Sparkle will
    /// not schedule checks less than an hour apart, and the user chose an hour over a timer of
    /// MiniNotch's own.
    static let intervalChoices: [(seconds: TimeInterval, title: String)] = [
        (3600, "Every Hour"),
        (3 * 3600, "Every 3 Hours"),
        (6 * 3600, "Every 6 Hours"),
        (12 * 3600, "Every 12 Hours"),
        (86400, "Every Day"),
        (3 * 86400, "Every 3 Days"),
        (7 * 86400, "Every Week"),
    ]

    /// Settings > About > New Versions: install a new version without asking, or ask first with a
    /// window listing what is new (Sparkle's own, showing the release notes from the feed). Sparkle
    /// keeps it in the defaults (`SUAutomaticallyUpdate`).
    var installsAutomatically = false {
        didSet {
            if let updater = controller?.updater, updater.automaticallyDownloadsUpdates != installsAutomatically {
                updater.automaticallyDownloadsUpdates = installsAutomatically
            }
        }
    }

    /// Whether relaunching now would interrupt something: the notch open, a timer or the stopwatch
    /// running, none of which survives a restart. `AppEnvironment` answers it.
    @ObservationIgnored var isBusy: (() -> Bool)?

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var pendingInstall: (() -> Void)?
    @ObservationIgnored private var installRetry: Timer?

    func start() {
        #if DEBUG
        isAvailable = false
        #else
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
        checkInterval = controller.updater.updateCheckInterval
        installsAutomatically = controller.updater.automaticallyDownloadsUpdates
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

extension UpdateService: SPUUpdaterDelegate {
    /// With Install Automatically on, Sparkle has downloaded the update and would install it when
    /// MiniNotch quits, which for an app in the background can be days. This installs and relaunches
    /// as soon as nothing would be interrupted, checking again each minute until then; the What's New
    /// window then says what changed.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        guard installsAutomatically else { return false }
        pendingInstall = immediateInstallHandler
        installWhenIdle()
        return true
    }

    private func installWhenIdle() {
        installRetry?.invalidate()
        installRetry = nil
        guard let install = pendingInstall else { return }
        if isBusy?() == true {
            installRetry = Timer.onMain(every: 60) { [weak self] in self?.installWhenIdle() }
            return
        }
        pendingInstall = nil
        install()
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
