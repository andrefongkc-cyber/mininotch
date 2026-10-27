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
        id: "0.8.0",
        version: "0.8.0",
        added: [
            ReleaseNote(
                symbol: "clock",
                title: "The Time in the Notch",
                detail: "A clock beside the camera, in your Mac's 12 or 24 hour time, with the day if you like.",
                howTo: "Settings > Layout > Closed Pill: drag Clock onto either side, with Show Indicators When Closed on. Clock Shows picks Time or Day and Time."
            ),
            ReleaseNote(
                symbol: "text.line.first.and.arrowtriangle.forward",
                title: "Up Next",
                detail: "A new button beside Next shows what plays after this song. Apple Music shares it for a playlist or album playing in order; for Spotify, connect your account once.",
                howTo: "The button is added after Next for you; move it in Settings > Layout. Connect Spotify in Settings > Music > Up Next."
            ),
            ReleaseNote(
                symbol: "globe",
                title: "MiniNotch Has a Website",
                detail: "Every feature, the six Notch Styles, and the easiest way to install, to share with friends. We plan to move it to mininotch.app soon.",
                howTo: "andrefongkc-cyber.github.io/mininotch"
            ),
        ],
        improved: [
            ReleaseNote(
                symbol: "gearshape",
                title: "Simpler Settings",
                detail: "Settings is sorted by what you are changing: Music, Lock Screen, Weather, Timer, Shelf & Notes and more. Each section shows what most people change, with the rest under More Options, and search still finds everything.",
                howTo: "Open Settings from the menu bar icon."
            ),
            ReleaseNote(
                symbol: "tray.and.arrow.down",
                title: "Drag Files to the Notch Again",
                detail: "Dragging a file or a link to the closed notch opens the Shelf again, ready to keep it or send it with AirDrop.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "playpause",
                title: "Play, Pause and Skip Right Away",
                detail: "The buttons answer the moment you click them instead of half a second later, in the notch, the pop-out player and the lock screen.",
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
