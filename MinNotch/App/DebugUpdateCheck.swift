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
@MainActor
enum DebugUpdateCheck {
    static let flag = "--check-update"

    /// Kept alive for the life of the process, as the updater only holds its delegate weakly.
    private static var delegate: Delegate?
    private static var controller: SPUStandardUpdaterController?

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

        let delegate = Delegate(feed: feed, log: log)
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: delegate, userDriverDelegate: nil)
        Self.delegate = delegate
        Self.controller = controller

        let updater = controller.updater
        updater.automaticallyChecksForUpdates = true
        updater.automaticallyDownloadsUpdates = true
        do {
            try updater.start()
        } catch {
            log.say("updater did not start: \(error.localizedDescription)")
            exit(1)
        }
        updater.checkForUpdatesInBackground()

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
