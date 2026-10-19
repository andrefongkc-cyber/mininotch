import AppKit
import SwiftUI

/// One change a user can see, with where to find it.
struct ReleaseNote: Identifiable {
    var symbol: String
    var title: String
    var detail: String
    /// Where to find it or how to turn it on. Nil when there is nothing to do.
    var howTo: String?

    var id: String { title }
}

/// What changed in one release, in the words someone using the app would use.
///
/// Written for users, not for this repository: nothing internal, only what they will notice,
/// and for anything new, where it is and how to switch it on. Keep each note to a sentence or
/// two; the window is read once, at launch, by someone who wanted the app and not a document.
struct ReleaseNotes {
    /// Identifies the release. The window shows again whenever this changes, so change it for
    /// every release that gets notes, even one whose version number was forgotten.
    var id: String
    var version: String
    var added: [ReleaseNote]
    var improved: [ReleaseNote]
    var removed: [ReleaseNote]

    static let latest = ReleaseNotes(
        id: "0.7.4",
        version: "0.7.4",
        added: [
            ReleaseNote(
                symbol: "rectangle.split.1x2",
                title: "Clock Styles",
                detail: "Show the timer and stopwatch as a flip clock, or as a mechanical seven-segment display whose segments flip over or slide out, in the notch and the pop-out window.",
                howTo: "The style button at the top of the Timer tab, beside Focus."
            ),
            ReleaseNote(
                symbol: "flag",
                title: "Every Lap",
                detail: "The stopwatch lists all your laps beside the time, the current one ticking, the fastest in green and the slowest in red. The .00 button shows or hides hundredths.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "arrow.up.left.and.arrow.down.right",
                title: "Bigger Pop-Out Timer",
                detail: "Expand the pop-out timer, or drag its edges, and the time grows with it.",
                howTo: "Hover the pop-out window and click the expand button, top left."
            ),
            ReleaseNote(
                symbol: "bolt.batteryblock",
                title: "Apps Using the Battery",
                detail: "See which apps have used the most energy since you unplugged.",
                howTo: "Settings > Battery > Battery Use."
            ),
            ReleaseNote(
                symbol: "arrow.down.circle",
                title: "Install Updates Automatically",
                detail: "Choose to have new versions install by themselves, once the notch is closed and no timer is running, or keep being asked first.",
                howTo: "Settings > About > New Versions."
            ),
        ],
        improved: [
            ReleaseNote(
                symbol: "stopwatch",
                title: "Stopwatch in the Closed Notch",
                detail: "A running stopwatch shows in the closed notch, as a countdown does.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "display.2",
                title: "External Displays in Layout",
                detail: "The settings for the notch on displays without one now sit in Settings > Layout, under the Closed Pill, and searching \"monitor\" finds them.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "sparkles",
                title: "Menus in the Notch",
                detail: "The top bar's What's New button and the clock style button open their menus inside the notch, where they can be seen and clicked.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "timer",
                title: "Smoother Stopwatch",
                detail: "The stopwatch counts every hundredth, and slows to tenths in Low Power Mode or on a low battery.",
                howTo: nil
            ),
        ],
        removed: []
    )
}

/// Shows the release notes once per release, at launch.
///
/// Not on a first launch: someone who has just installed the app has nothing to compare it to,
/// and gets the tutorial instead, so the release they installed is marked as seen. Closing the
/// window any way counts as having seen it.
@MainActor
final class WhatsNewCoordinator: NSObject, NSWindowDelegate {
    private static let seenKey = "whatsNew.seenRelease"

    private let defaults: UserDefaults
    private var window: NSWindow?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var shouldPresent: Bool {
        defaults.string(forKey: Self.seenKey) != ReleaseNotes.latest.id
    }

    func markSeen() {
        defaults.set(ReleaseNotes.latest.id, forKey: Self.seenKey)
    }

    func present() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = Self.makeWindow(onClose: { [weak self] in self?.window?.close() })
        window.delegate = self
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// Builds the window without showing it. Shared with `--capture-whats-new`.
    static func makeWindow(onClose: @escaping () -> Void) -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: WhatsNewView.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "What's New in MiniNotch"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: WhatsNewView(notes: .latest, onClose: onClose))
        window.setContentSize(WhatsNewView.size)
        return window
    }

    func windowWillClose(_ notification: Notification) {
        markSeen()
        window = nil
    }
}
