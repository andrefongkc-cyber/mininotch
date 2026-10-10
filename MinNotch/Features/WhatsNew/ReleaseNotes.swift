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
        id: "0.7.0",
        version: "0.7",
        added: [
            ReleaseNote(
                symbol: "paintpalette",
                title: "Notch Styles",
                detail: "Six looks for the notch: Minimal, Bento, Glass, Neumorphic, Clay and Skeuomorphic, each in dark, light, or Auto to follow your Mac. Minimal Dark is the notch you know.",
                howTo: "Settings > Appearance > Notch Style."
            ),
            ReleaseNote(
                symbol: "drop",
                title: "Liquid Glass",
                detail: "Any style can sit on Apple's Liquid Glass, see-through and bending what is behind the notch. Glass Opacity sets how clear it is, from glass to nearly solid. Needs macOS 26.",
                howTo: "Settings > Appearance > Notch Style > Background."
            ),
            ReleaseNote(
                symbol: "arrow.down.circle",
                title: "Automatic Updates",
                detail: "MiniNotch now checks for a new version once a day and asks before installing it. This is the last version you have to download by hand.",
                howTo: "Check now from the menu bar icon, or switch it off in Settings > About."
            ),
            ReleaseNote(
                symbol: "lock",
                title: "Private Clipboard",
                detail: "The Clipboard tab stays blurred until you unlock it with Touch ID or your password, and blurs again when it closes. Anything copied in the Passwords app or Keychain Access is never kept.",
                howTo: "On by default. Switch it off in Settings > Tabs > Clipboard."
            ),
        ],
        improved: [
            ReleaseNote(
                symbol: "hand.draw",
                title: "Smoother Swipes",
                detail: "Two-finger swipes work anywhere on the open notch, quick flicks count, the direction is right with Natural Scrolling off, and the notch resizes along with the tab you swipe to.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "gauge.with.dots.needle.33percent",
                title: "Lighter While Playing",
                detail: "Much less work for your Mac while music plays, which you would have felt in Mission Control and with Settings open. The open notch also closes when you switch desktops.",
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
