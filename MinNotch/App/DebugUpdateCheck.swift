#if DEBUG
import AppKit
import Sparkle

/// Runs a whole Sparkle update, from reading a feed to replacing this copy of the app, with no
/// one clicking anything.
///
/// Run from an older test build with `MiniNotch --check-update --feed <feed URL> [--out f]`. It
/// reads the feed, downloads the newer DMG, checks its signature against `SUPublicEDKey`, installs
/// it over this copy and quits without relaunching; whatever started it then reads the version of
/// the bundle on disk. Every step is written to `--out`, since a process LaunchServices started has
/// nowhere else to say anything.
///
/// It refuses to run under the real bundle identifier: the updater keeps its settings in the
/// defaults of the bundle it runs as, and installs over the copy it was started from, so the test
/// builds are made with `PRODUCT_BUNDLE_IDENTIFIER=com.minnotch.MinNotch.updatetest`.
///
/// `--ask` stops at the Ask First window instead, as a scheduled check shows it to someone working
/// in another app, and reports where that window landed among every app's windows: in front, or
/// behind where nobody sees it. Launch it with `open -g` so it starts in the background, as the
/// real app is. `--no-raise` leaves out `UpdateService.bringUpdateWindowForward`, for comparison.
/// No signature is checked before that window, so the real feed will do. The check waits 8 s, past Sparkle's
/// own grace period at launch, as a scheduled check hours later would.
@MainActor
enum DebugUpdateCheck {
    static let flag = "--check-update"

    /// Kept alive for the life of the process, as the updater only holds its delegate weakly.
    private static var delegate: Delegate?
    private static var controller: SPUStandardUpdaterController?
    private static var driverDelegate: AskDriverDelegate?
    private static var keyWindow: NSWindow?

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard arguments.contains(flag) else { return false }

        let log = Log(path: value(after: "--out"))
        guard Bundle.main.bundleIdentifier?.hasSuffix(".updatetest") == true else {
            log.say("refused: build this with PRODUCT_BUNDLE_IDENTIFIER=com.minnotch.MinNotch.updatetest, never the real app")
            exit(3)
        }
        guard let feed = value(after: "--feed") else {
            log.say("refused: no --feed given")
            exit(3)
        }
        log.say("running \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") from \(Bundle.main.bundlePath)")

        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)

        // `--key-window`: MiniNotch active with a window of its own in front, as after typing a
        // note or using Settings, which is when Sparkle sends a scheduled window to the back.
        if arguments.contains("--key-window") {
            let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 240, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
            window.title = "MiniNotch update test"
            keyWindow = window
            DispatchQueue.main.async {
                application.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        }

        let asks = arguments.contains("--ask")
        let delegate = Delegate(feed: feed, log: log)
        let driverDelegate = asks ? AskDriverDelegate(log: log, raises: !arguments.contains("--no-raise")) : nil
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: delegate, userDriverDelegate: driverDelegate)
        Self.delegate = delegate
        Self.controller = controller
        Self.driverDelegate = driverDelegate

        let updater = controller.updater
        updater.automaticallyChecksForUpdates = true
        updater.automaticallyDownloadsUpdates = !asks
        do {
            try updater.start()
        } catch {
            log.say("updater did not start: \(error.localizedDescription)")
            exit(1)
        }
        // Sparkle brings its window forward itself for a check just after launch; a scheduled one
        // hours later is the case that matters, so `--ask` waits until that grace has passed.
        DispatchQueue.main.asyncAfter(deadline: .now() + (asks ? 8 : 0)) {
            updater.checkForUpdatesInBackground()
        }

        // A test that hears nothing must still end.
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) {
            log.say("timed out after 90 seconds")
            exit(2)
        }
        application.run()
        return true
    }

    private static func value(after flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    final class Log {
        let path: String?
        init(path: String?) { self.path = path }

        func say(_ line: String) {
            print(line)
            guard let path else { return }
            let data = Data((line + "\n").utf8)
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                FileManager.default.createFile(atPath: path, contents: data)
            }
        }
    }

    /// Stands in for `UpdateService`'s user driver delegate, then reads the window order.
    @MainActor
    final class AskDriverDelegate: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
        let log: Log
        let raises: Bool

        init(log: Log, raises: Bool) {
            self.log = log
            self.raises = raises
        }

        var supportsGentleScheduledUpdateReminders: Bool { true }

        func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
            do {
                log.say("Sparkle will show \(update.displayVersionString), active: \(NSApp.isActive), key window: \(NSApp.keyWindow != nil), user initiated: \(state.userInitiated)")
                if raises {
                    NSApp.activate(ignoringOtherApps: true)
                    DispatchQueue.main.async { UpdateService.bringUpdateWindowForward() }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.report() }
            }
        }

        /// Every on-screen window at the normal level, front to back.
        private func report() {
            let me = ProcessInfo.processInfo.processIdentifier
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            let normal = list.filter { ($0[kCGWindowLayer as String] as? Int) == 0 }
            let alert = NSApp.windows.first { $0.windowController.map { String(describing: type(of: $0)) } == "SUUpdateAlert" }
            log.say("update window: \(alert == nil ? "none" : "visible \(alert!.isVisible), on screen \(alert!.isOnActiveSpace)")")
            for (index, window) in normal.prefix(4).enumerated() {
                let pid = window[kCGWindowOwnerPID as String] as? Int32 ?? 0
                let number = window[kCGWindowNumber as String] as? CGWindowID
                log.say("  \(index): \(pid != me ? "another app" : number == alert.map { CGWindowID($0.windowNumber) } ? "the update window" : "another window of this app")")
            }
            let alertNumber = alert.map { CGWindowID($0.windowNumber) }
            let position = normal.firstIndex { ($0[kCGWindowNumber as String] as? CGWindowID) == alertNumber }
            log.say(position == 0 ? "result: in front" : "result: behind \(position.map(String.init) ?? "every") other window(s)")
            exit(0)
        }
    }

    final class Delegate: NSObject, SPUUpdaterDelegate {
        let feed: String
        let log: Log

        init(feed: String, log: Log) {
            self.feed = feed
            self.log = log
        }

        func feedURLString(for updater: SPUUpdater) -> String? { feed }

        func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
            log.say("feed read: \(appcast.items.map(\.displayVersionString).joined(separator: ", "))")
        }

        func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
            log.say("found \(item.displayVersionString), downloading")
        }

        func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
            log.say("no update found")
            exit(1)
        }

        func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
            log.say("downloaded \(item.displayVersionString)")
        }

        func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
            log.say("download failed: \(error.localizedDescription)")
            exit(1)
        }

        func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
            log.say("signature and code signing accepted, installing \(item.displayVersionString)")
            immediateInstallHandler()
            return true
        }

        func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
            log.say("installing, then quitting without relaunching")
            // Sparkle's installer is a process of its own and replaces the bundle by itself; this
            // one only has to get out of its way.
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                self.log.say("quit")
                exit(0)
            }
            return false
        }

        func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
            log.say("aborted: \(error.localizedDescription)")
            // The reason is usually a level down: the user-facing message is the same for most.
            var underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError
            while let next = underlying {
                log.say("  because: \(next.domain) \(next.code): \(next.localizedDescription)")
                underlying = next.userInfo[NSUnderlyingErrorKey] as? NSError
            }
            exit(1)
        }
    }
}
#endif
