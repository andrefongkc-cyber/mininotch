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
        id: "0.8.1",
        version: "0.8.1",
        added: [],
        improved: [
            ReleaseNote(
                symbol: "arrow.down.app",
                title: "Updates Install Themselves",
                detail: "New versions now download and install on their own, once the notch is closed and no timer or stopwatch is running, and What's New tells you what changed. If you chose Ask First before, that stays.",
                howTo: "To be asked first instead: Settings > About > New Versions > Ask First."
            ),
            ReleaseNote(
                symbol: "macwindow.on.rectangle",
                title: "Update Window in Front",
                detail: "With Ask First, the window offering a new version now always opens in front of your other apps.",
                howTo: nil
            ),
        ],
        removed: []
    )
}

extension ReleaseNotes {
    /// Every release newer than `seenID`, newest first. A seen release this build does not know
    /// (nil, or from a build with notes that were never kept) gets the latest alone, rather than
    /// the whole history back to 0.2.
    static func since(_ seenID: String?) -> [ReleaseNotes] {
        guard let seenID, let index = history.firstIndex(where: { $0.id == seenID }) else { return [latest] }
        return Array(history.prefix(index))
    }
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

    /// The releases to show at launch: every one since the last seen, so skipping versions skips
    /// nothing. The menu bar's What's New passes no seen release and gets the latest alone.
    var unseen: [ReleaseNotes] {
        ReleaseNotes.since(defaults.string(forKey: Self.seenKey))
    }

    func markSeen() {
        defaults.set(ReleaseNotes.latest.id, forKey: Self.seenKey)
    }

    /// Shows `releases`, newest first; the latest alone when nil.
    func present(_ releases: [ReleaseNotes]? = nil) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = Self.makeWindow(releases: releases ?? [.latest], onClose: { [weak self] in self?.window?.close() })
        window.delegate = self
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// Builds the window without showing it. Shared with `--capture-whats-new`.
    static func makeWindow(releases: [ReleaseNotes] = [.latest], onClose: @escaping () -> Void) -> NSWindow {
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
        window.contentView = NSHostingView(rootView: WhatsNewView(releases: releases, onClose: onClose))
        window.setContentSize(WhatsNewView.size)
        return window
    }

    func windowWillClose(_ notification: Notification) {
        markSeen()
        window = nil
    }
}
