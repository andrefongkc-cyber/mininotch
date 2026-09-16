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
        id: "0.2.0",
        version: "0.2",
        added: [
            ReleaseNote(
                symbol: "link",
                title: "Link Shelf",
                detail: "Keep web links in the notch. Click one to open it in your browser, or copy it back.",
                howTo: "Turn it on in Settings > Advanced > Link Shelf. Then drag a link onto the notch, or open the Links tab and press ⌘V."
            ),
            ReleaseNote(
                symbol: "list.bullet",
                title: "Up Next",
                detail: "The next song shows under the music controls. Apple Music only, when shuffle is off.",
                howTo: "Settings > Media > Show Up Next."
            ),
            ReleaseNote(
                symbol: "shuffle",
                title: "Shuffle Button",
                detail: "Turn shuffle on or off from the notch. It lights up while shuffle is on.",
                howTo: "In the Now Playing controls. Rearrange them in Settings > Media."
            ),
            ReleaseNote(
                symbol: "music.note",
                title: "Sneak Peek",
                detail: "When the song changes, the notch drops down for a moment to show what's playing.",
                howTo: "On by default. Settings > Media > Sneak Peek on Track Change."
            ),
            ReleaseNote(
                symbol: "rectangle.topthird.inset.filled",
                title: "Arrange the Top Bar",
                detail: "Put any tab on either side of the notch. Tabs that don't fit move to the other side instead of hiding behind it.",
                howTo: "Settings > Appearance > Top Bar."
            ),
            ReleaseNote(
                symbol: "pip.enter",
                title: "Pop-Out Player",
                detail: "Open Now Playing in a small floating window.",
                howTo: "Click the pop-out button on the Now Playing card."
            )
        ],
        improved: [
            ReleaseNote(
                symbol: "speaker.wave.2",
                title: "Hiding Apple's Volume Overlay Now Works",
                detail: "On macOS 26 you now see only MinNotch's volume and brightness indicator.",
                howTo: "Settings > HUDs > Hide the System Overlay. MinNotch asks for Accessibility access the first time."
            ),
            ReleaseNote(
                symbol: "quote.bubble",
                title: "Faster Lyrics",
                detail: "Lyrics for songs you've played before load straight away.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "sparkles",
                title: "Smoother Glow and Clearer Bars",
                detail: "The glow fades smoothly as the notch opens and closes, and the bars over the album art stand out more.",
                howTo: nil
            )
        ],
        removed: [
            ReleaseNote(
                symbol: "photo",
                title: "Glow Around Album Art",
                detail: "The album art now stays still. The glow around the notch is unchanged.",
                howTo: nil
            )
        ]
    )
}

/// Shows the release notes once per release, at launch.
///
/// Not on a first launch: someone who has just installed the app has nothing to compare it to,
/// and gets the tutorial instead, so the release they installed is marked as seen. Closing the
/// window any way counts as having seen it.
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
        window.title = "What's New in MinNotch"
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
