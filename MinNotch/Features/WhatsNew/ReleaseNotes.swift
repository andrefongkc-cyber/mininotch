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
        id: "0.7.3",
        version: "0.7.3",
        added: [
            ReleaseNote(
                symbol: "stopwatch",
                title: "Stopwatch",
                detail: "The Timer tab is now a timer or a stopwatch, with laps. Switch between them at the top of the tab.",
                howTo: "The Timer tab: Timer | Stopwatch, top left."
            ),
            ReleaseNote(
                symbol: "pip.enter",
                title: "Pop-Out Timer",
                detail: "Float the timer or stopwatch in a small window above your other apps, and put it back when you are done.",
                howTo: "The Timer tab's pop-out button, top right."
            ),
            ReleaseNote(
                symbol: "scope",
                title: "Focus",
                detail: "Turn on Focus and the timer pops out when it starts. Switch to another app while a countdown, a Pomodoro focus interval or the stopwatch runs, and it starts over. Breaks and pauses do not count.",
                howTo: "Focus at the top of the Timer tab, or Settings > Tabs > Timer > Focus Timer."
            ),
        ],
        improved: [
            ReleaseNote(
                symbol: "timer",
                title: "Tidier Timer Tab",
                detail: "Choose a Pomodoro rhythm, then press Start: picking a rhythm no longer starts it. Quick countdowns and your own length sit on one row below.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "hand.draw",
                title: "Scrolling Stays Put",
                detail: "Scrolling the Clipboard list or Notes no longer closes the notch, however short they are.",
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
