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
        id: "0.8.2",
        version: "0.8.2",
        added: [
            ReleaseNote(
                symbol: "paintpalette",
                title: "Four New Notch Styles",
                detail: "Clear draws no panel at all, only what is on it. Aurora has soft colour drifting behind the panel in the colours of the song, Brutalism hard outlines and loud yellow, Retro Web bevelled buttons and scanlines. The last three are always dark, and turn plain under Reduce Transparency or Increase Contrast.",
                howTo: "Settings > Appearance > Notch Style."
            ),
            ReleaseNote(
                symbol: "text.viewfinder",
                title: "Answers",
                detail: "Read Screen reads the window in front and answers the questions in it, using Apple Intelligence on your Mac. Nothing leaves your Mac. Needs macOS 26 with Apple Intelligence on, and Screen Recording.",
                howTo: "Settings > Shelf & Notes > Show Answers, then the Answers tab. A shortcut can do it in one go: Settings > General > Keyboard Shortcuts."
            ),
        ],
        improved: [
            ReleaseNote(
                symbol: "airpods",
                title: "AirPods When They Connect",
                detail: "Connecting AirPods or other Bluetooth headphones now shows their charge in the notch, and the System tab lists each accessory once, with left, right and case together.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "note.text",
                title: "Tidier Notes",
                detail: "Scrolling a long note or a list no longer closes the notch or switches tabs. The hint in an empty note fades as you click in, and there is no ring round the note while you type.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "pin",
                title: "Another Menu Bar Pin",
                detail: "Show on Displays Without a Notch can now be pinned to the menu bar icon's menu.",
                howTo: "Settings > General > Menu Bar > Pin Settings to the Menu."
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
