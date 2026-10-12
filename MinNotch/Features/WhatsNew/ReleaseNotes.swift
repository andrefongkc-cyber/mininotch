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
        id: "0.7.1",
        version: "0.7.1",
        added: [
            ReleaseNote(
                symbol: "lock.rectangle.stack",
                title: "Lock Screen Player",
                detail: "While your Mac is locked, what is playing shows in the middle of the screen: the cover, its controls, and the synced lyrics sliding along with the song.",
                howTo: "Settings > Media > Lock Screen. Pick a layout, or keep the small strip under the notch."
            ),
            ReleaseNote(
                symbol: "globe",
                title: "Spotify in Chrome",
                detail: "Now Playing picks up Spotify's web player in Google Chrome. For the cover, the time, the buttons and lyrics, Chrome has to allow it once.",
                howTo: "In Chrome: View > Developer > Allow JavaScript from Apple Events."
            ),
            ReleaseNote(
                symbol: "arrow.left.and.right",
                title: "Panel Size",
                detail: "Small, Medium, Large, a width of your own, or Fit to Top Bar, which narrows the panel when you have fewer tabs. The music card's text and controls scale with it.",
                howTo: "Settings > Appearance > Panel Size."
            ),
        ],
        improved: [
            ReleaseNote(
                symbol: "square.stack.3d.up",
                title: "One Place for Every Tab",
                detail: "Settings has a Tabs pane with the Shelf, links, Timer, Weather, Notes, Clipboard and System settings together.",
                howTo: "Settings > Tabs."
            ),
            ReleaseNote(
                symbol: "play.circle",
                title: "Tidier Music Card",
                detail: "Play sits in the middle of the controls, the title is a little smaller, and lyrics are found for more songs whose length differs slightly.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "rectangle.on.rectangle",
                title: "Steadier Notch",
                detail: "The notch stays put when you swipe between desktops, the top bar's icons clear the camera, and Default Tab applies every time the notch opens.",
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
