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
        id: "0.3.0",
        version: "0.3",
        added: [
            ReleaseNote(
                symbol: "rectangle.3.group",
                title: "Layout",
                detail: "Arrange the closed notch, the top bar and the music controls on a picture of the notch. Drag icons in, or click them; drag them out, or click ×, to remove them.",
                howTo: "Settings > Layout."
            ),
            ReleaseNote(
                symbol: "calendar",
                title: "Pick a Day",
                detail: "Click any day in the calendar to see what's on it, and use the arrows to go to other weeks or months.",
                howTo: "In the Calendar tab. Click Today to come back."
            ),
            ReleaseNote(
                symbol: "quote.bubble",
                title: "All the Lyrics",
                detail: "Open every line of the song, scrolling along as it plays. Click a line to jump to it.",
                howTo: "Click the expand button beside the lyrics."
            ),
            ReleaseNote(
                symbol: "waveform",
                title: "Lyrics That Match the Song",
                detail: "MinNotch can listen for where the singing starts and line the lyrics up with it.",
                howTo: "Settings > Media > Match to the Audio. Uses the system audio permission."
            ),
            ReleaseNote(
                symbol: "repeat",
                title: "Repeat and Favourite",
                detail: "Repeat works with Apple Music and Spotify, favourite with Apple Music. Both light up when on.",
                howTo: "Add them in Settings > Layout > Now Playing Controls."
            ),
            ReleaseNote(
                symbol: "arrow.down.circle",
                title: "Downloads and AirPods in the Notch",
                detail: "See how far along a download is, and your AirPods' charge when they connect. Swipe up on the notch to put one away.",
                howTo: "Settings > Layout > Live Activities. Show Indicators When Closed must be on."
            ),
            ReleaseNote(
                symbol: "metronome",
                title: "Glow Tempo",
                detail: "Set the glow's beat yourself, tap it out, or use the song's BPM from Music.",
                howTo: "Settings > Appearance > Tempo."
            ),
            ReleaseNote(
                symbol: "play.rectangle",
                title: "VLC",
                detail: "What's playing in VLC shows in the notch, and you can drag to seek.",
                howTo: nil
            )
        ],
        improved: [
            ReleaseNote(
                symbol: "rectangle.on.rectangle",
                title: "Two New Card Styles",
                detail: "Compact, half the height, and Full Artwork, with the cover filling the card.",
                howTo: "Settings > Appearance > Card Style."
            ),
            ReleaseNote(
                symbol: "app.badge",
                title: "Which App Is Playing",
                detail: "A small icon of the playing app sits on the album art.",
                howTo: "Settings > Media > Show Which App Is Playing."
            ),
            ReleaseNote(
                symbol: "gauge.with.dots.needle.33percent",
                title: "System History",
                detail: "The last minute of CPU, GPU, memory and network sits behind each reading, so a spike doesn't flash past.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "sparkles",
                title: "A Glow You Can Trust",
                detail: "The glow and the bars over the album art stay still when nothing is playing and follow the music when Follow the Beat is on.",
                howTo: "Settings > Appearance > What It Is Hearing shows what the glow hears."
            ),
            ReleaseNote(
                symbol: "checklist",
                title: "Reminders Without a Date",
                detail: "They now show at the end of the calendar list.",
                howTo: "Settings > Calendar > Show Reminders Without a Date."
            ),
            ReleaseNote(
                symbol: "app",
                title: "A New Icon",
                detail: "MinNotch has an icon of its own.",
                howTo: nil
            )
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
