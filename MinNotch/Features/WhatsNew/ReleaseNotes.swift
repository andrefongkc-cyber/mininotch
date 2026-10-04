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
        id: "0.5.0",
        version: "0.5",
        added: [
            ReleaseNote(
                symbol: "tray.full",
                title: "Files and Links Together",
                detail: "The Shelf holds your files and your saved links in one tab, files on top with AirDrop, links underneath. Drop either anywhere on it, or press ⌘V to add files you copied in Finder or a link you copied.",
                howTo: "The Shelf tab. Shelf and Links each still switch on and off in Settings > Layout."
            ),
            ReleaseNote(
                symbol: "pin",
                title: "Keep the Notch Open",
                detail: "Press ⌃⌥P and the open panel stays open on whichever display it is on, even while you work on another. Press it again, or click the pin in the top bar, to let it close.",
                howTo: "Change the shortcut in Settings > Shortcuts. The pin can also live in the top bar: Settings > Layout."
            ),
            ReleaseNote(
                symbol: "bolt",
                title: "Charging Power",
                detail: "While plugged in, the System tab shows what the charger is giving, what the Mac is using, and how much of it is going into the battery.",
                howTo: "On by default. Settings > Battery > Show Charging Power."
            ),
            ReleaseNote(
                symbol: "thermometer.medium",
                title: "Temperatures",
                detail: "The chip, battery and SSD temperatures in the System tab, in the units you chose for the weather.",
                howTo: "Settings > Advanced > Show Temperatures."
            ),
            ReleaseNote(
                symbol: "chart.xyaxis.line",
                title: "Graphs in the System Tab",
                detail: "Each reading has a graph of the last five minutes under it, kept while the tab is closed.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "eye.slash",
                title: "Hide the Notch on Other Displays",
                detail: "On a monitor without a notch, MinNotch can stay out of sight until the pointer reaches the top middle of the screen.",
                howTo: "Settings > Advanced > Hide Until Hovered."
            )
        ],
        improved: [
            ReleaseNote(
                symbol: "quote.bubble",
                title: "Lyrics on Time",
                detail: "Fix Timing Automatically now lines the lyrics up with the singing instead of the drums, which pushed some songs early and others late. It waits until it is sure, then remembers each song, so the next play is right from the first line.",
                howTo: "Settings > Media > Fix Timing Automatically."
            ),
            ReleaseNote(
                symbol: "speaker.wave.2",
                title: "A Smaller Volume Indicator",
                detail: "The volume and brightness indicator takes up much less of the menu bar.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "hand.raised",
                title: "Hiding Apple's Volume Overlay",
                detail: "If Apple's overlay still shows beside MinNotch's, Settings now asks macOS for the access it needs instead of only opening System Settings.",
                howTo: "Settings > HUDs > Allow…"
            ),
            ReleaseNote(
                symbol: "leaf",
                title: "Lighter on the Battery",
                detail: "MinNotch only listens to the music while something is playing, rather than all the time.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "dock.rectangle",
                title: "No More Dock Flash",
                detail: "MinNotch no longer shows a Dock icon for a moment when it starts.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "hand.draw",
                title: "Swiping Between Tabs",
                detail: "Swiping goes through the tabs in the order the top bar shows them, including ones you moved.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "battery.100percent",
                title: "Clearer System Tab",
                detail: "The battery temperature is labelled, and changing numbers roll instead of blurring together.",
                howTo: nil
            )
        ],
        removed: [
            ReleaseNote(
                symbol: "link",
                title: "The Separate Links Tab",
                detail: "Links now sit in the Shelf tab, under your files.",
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
