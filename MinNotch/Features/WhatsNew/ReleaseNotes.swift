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
        id: "0.4.0",
        version: "0.4",
        added: [
            ReleaseNote(
                symbol: "text.below.photo",
                title: "Lyrics With the Notch Closed",
                detail: "The line being sung sits just under the closed notch while a song plays, the current word lit up.",
                howTo: "Click the button beside the lyrics, or Settings > Media > Show Lyrics When Closed."
            ),
            ReleaseNote(
                symbol: "textformat",
                title: "The Song in the Closed Notch",
                detail: "The closed notch shows the song's title beside its cover. Prefer the artist? You can switch.",
                howTo: "Settings > Layout > Song Shows. Drag Song in the Arrangement to move it."
            ),
            ReleaseNote(
                symbol: "lock.display",
                title: "Volume on the Lock Screen",
                detail: "Volume and brightness show at the notch while your Mac is locked, too.",
                howTo: "On by default. Settings > HUDs > Show on the Lock Screen."
            ),
            ReleaseNote(
                symbol: "timer",
                title: "Sneak Peek Length",
                detail: "Choose how long the new song stays on screen when it changes.",
                howTo: "Settings > Media > Sneak Peek Length."
            ),
            ReleaseNote(
                symbol: "sparkles",
                title: "New in Settings",
                detail: "Settings marks what is new in each update, and the sidebar shows which sections have something new.",
                howTo: nil
            )
        ],
        improved: [
            ReleaseNote(
                symbol: "hand.draw",
                title: "Easier Rearranging",
                detail: "Icons land where you let go, with a marker showing the spot. Moving one left is now as easy as moving it right.",
                howTo: "Settings > Layout."
            ),
            ReleaseNote(
                symbol: "rectangle.split.3x1",
                title: "A Real Preview",
                detail: "Layout's picture of the closed notch shows your actual cover, song and battery.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "circle.dashed",
                title: "An Even Glow",
                detail: "The glow around the closed notch is as bright down the sides as along the bottom.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "shadow",
                title: "Panel Shadow",
                detail: "The shadow no longer makes the panel come apart as it opens.",
                howTo: "Settings > Appearance > Panel Shadow."
            ),
            ReleaseNote(
                symbol: "metronome",
                title: "The Glow Keeps the Song's Tempo",
                detail: "New setups follow the song's own BPM from Music by default.",
                howTo: "Settings > Appearance > Tempo."
            ),
            ReleaseNote(
                symbol: "waveform",
                title: "Playing Indicator",
                detail: "It shows whenever music plays, even with the album art beside it.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "checklist",
                title: "Permissions in the Tutorial",
                detail: "Every permission is listed, with Allow buttons for Accessibility and system audio as well.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "quote.bubble",
                title: "Clearer Lyrics Timing",
                detail: "Match to the Audio is now Fix Timing Automatically, because it moves the lyrics, not the glow.",
                howTo: "Settings > Media > Fix Timing Automatically."
            )
        ],
        removed: [
            ReleaseNote(
                symbol: "text.line.first.and.arrowtriangle.forward",
                title: "Up Next, for Now",
                detail: "Music told MinNotch that playlists were shuffling when they were not, so the list was often wrong.",
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
