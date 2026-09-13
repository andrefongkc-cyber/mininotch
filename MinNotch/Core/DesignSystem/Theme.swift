import SwiftUI

/// Layout constants shared by the notch surface and the Settings window.
///
/// These deliberately mirror the metrics macOS System Settings uses so panels read
/// as system UI rather than as app chrome. Anything tunable by the user lives in
/// `AppearanceSettings` instead; this file is for values that never change.
enum Metrics {

    // MARK: Settings window

    /// Corner radius of a settings card. System Settings uses a continuous ~10pt curve.
    static let cardCornerRadius: CGFloat = 10
    /// Minimum height of a single control row inside a card.
    static let rowHeight: CGFloat = 40
    /// Height of a row that carries a secondary helper line beneath the control.
    static let tallRowHeight: CGFloat = 56
    /// Horizontal inset inside a card, from the card edge to its content.
    static let cardHorizontalPadding: CGFloat = 14
    /// Outer margin around the stack of cards in a detail pane.
    static let paneMargin: CGFloat = 20
    /// Vertical space between two cards.
    static let cardSpacing: CGFloat = 18
    /// Space between a section header and the card it introduces.
    static let headerSpacing: CGFloat = 7

    static let settingsWindowMinWidth: CGFloat = 720
    static let settingsWindowMinHeight: CGFloat = 520
    static let sidebarMinWidth: CGFloat = 190
    static let sidebarIdealWidth: CGFloat = 210

    // MARK: Notch surface

    /// Corner radius of the expanded panel.
    static let notchPanelCornerRadius: CGFloat = 22
    /// Radius of the two "inverted" shoulders where the notch meets the menu bar.
    static let notchShoulderRadius: CGFloat = 9
    /// Room kept clear outside the notch outline for the ambient glow to fall away into.
    ///
    /// A blur is only soft if it has somewhere to fade to. Clipped short it ends on a hard
    /// edge, and on a transparent window that edge composites against the desktop rather
    /// than against the panel, so it reads as a translucent strip beside the notch instead
    /// of as light. Twice the widest glow radius is enough for the falloff to reach nothing.
    static let notchGlowSpill: CGFloat = 56
    /// Inner padding of the expanded panel.
    static let notchPanelPadding: CGFloat = 14
    /// Size of the album artwork thumbnail in the expanded Now Playing card.
    static let artworkSize: CGFloat = 104
    /// Size of the album artwork thumbnail shown in the collapsed pill.
    static let pillArtworkSize: CGFloat = 18

    /// Tallest the expanded panel may grow. The window is sized from this once, so the
    /// panel can change height between tabs without the window ever being resized.
    static let maxPanelHeight: CGFloat = 420
    /// Inset from the panel edge to the buttons in the top strip. Smaller than the body
    /// inset because those buttons sit in the menu bar band and should hug the edges.
    static let topStripPadding: CGFloat = 6
}

/// Typography ramp. Every face is the system font so the app inherits San Francisco,
/// dynamic weights, and the user's text-size settings.
enum Typography {
    /// Bold header above a settings card, and section titles inside the notch panel.
    static let sectionHeader = Font.system(size: 13, weight: .semibold)
    /// Large header at the top of a settings detail pane.
    static let paneTitle = Font.system(size: 15, weight: .bold)
    /// Standard control label.
    static let body = Font.system(size: 13, weight: .regular)
    /// Emphasised body, e.g. a now-playing track title.
    static let bodyEmphasised = Font.system(size: 13, weight: .semibold)
    /// Grey helper text under a control.
    static let helper = Font.system(size: 11, weight: .regular)
    /// Text inside a "Beta" / "Coming soon" pill.
    static let badge = Font.system(size: 10, weight: .semibold)
    /// Monospaced digits for timecodes and percentages, so they do not jitter.
    static let timecode = Font.system(size: 11, weight: .medium).monospacedDigit()
}

/// Semantic colours. Nothing here is a literal hex value: every colour resolves through
/// AppKit's semantic palette so light mode, dark mode, increased contrast, and the
/// system accent colour all work without extra code.
enum Palette {
    static let primaryText = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    static let separator = Color(nsColor: .separatorColor)
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let paneBackground = Color(nsColor: .windowBackgroundColor)
    static let selectionTint = Color(nsColor: .selectedContentBackgroundColor)
    static let controlAccent = Color(nsColor: .controlAccentColor)

    /// Fill used for the collapsed pill. Always near-black so it blends with the
    /// physical notch on a notched display, in both appearances.
    static let notchFill = Color.black
}

/// Transition timings. Everything user-visible should pick from this list so the app has
/// one motion personality.
///
/// The open and close is deliberately unhurried: the notch is a large shape appearing over
/// the menu bar, and a fast transition there reads as a flicker rather than as something
/// sliding out of the hardware. Damping stays high so it settles without bouncing.
enum Motion {
    /// Collapsed <-> expanded notch transition.
    static let notch = Animation.spring(response: 0.52, dampingFraction: 0.92, blendDuration: 0)
    /// Cross-fade of the content inside the surface as it opens and closes.
    static let fade = Animation.easeInOut(duration: 0.38)
    /// Content swap inside an already-open panel, such as changing tab.
    static let content = Animation.easeOut(duration: 0.26)
    /// Hover highlight and other micro-feedback, which should still feel immediate.
    static let hover = Animation.easeOut(duration: 0.16)
    /// Sneak-peek expand-and-collapse on track change (V2).
    static let peek = Animation.spring(response: 0.42, dampingFraction: 0.86, blendDuration: 0)
}
