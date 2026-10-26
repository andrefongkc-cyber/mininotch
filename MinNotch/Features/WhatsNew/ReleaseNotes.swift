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
        id: "0.7.7",
        version: "0.7.7",
        added: [
            ReleaseNote(
                symbol: "pin",
                title: "Settings in the Menu Bar",
                detail: "Pin the switches you use most to the menu bar icon's menu, and turn them on and off without opening Settings.",
                howTo: "Settings > General > Pin Settings to the Menu."
            ),
            ReleaseNote(
                symbol: "display.2",
                title: "Lyrics on Your Choice of Display",
                detail: "Show the lyrics under the closed notch on every display, only the Mac's own, or only the others.",
                howTo: "The lyrics button on the music card, or Settings > Media > Show Lyrics On."
            ),
            ReleaseNote(
                symbol: "pip",
                title: "Glow Around the Pop-Out Player",
                detail: "Ambient Lighting now glows around the pop-out music window too, and can light the lyrics under the closed notch on their own.",
                howTo: "Option-click the effects button on the music card, or Settings > Appearance > Ambient Lighting > Where It Shows."
            ),
        ],
        improved: [
            ReleaseNote(
                symbol: "exclamationmark.triangle",
                title: "Opens Again",
                detail: "0.7.6 could close straight away every time it was opened while the Mac was plugged in, after it had last been quit on battery. Fixed.",
                howTo: "If 0.7.6 will not open, it cannot update itself: download this version, or open 0.7.6 once with the Mac unplugged and it will update."
            ),
            ReleaseNote(
                symbol: "sparkles",
                title: "Glow Menu You Can See",
                detail: "The glow's style and placement menu on the music card opens inside the notch, where it used to be hidden.",
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
