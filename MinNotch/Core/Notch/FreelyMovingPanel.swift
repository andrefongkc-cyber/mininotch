import AppKit

/// A panel that stays wherever it is left, menu bar included.
///
/// AppKit runs every window's new frame through `constrainFrameRect(_:to:)` after a move, and
/// that pushes a window back down below the menu bar. The pop-out windows carry transparent room
/// around what they draw (the Now Playing card has the glow's margin and its drag strip above
/// it), so the card itself stopped well short of the top of the screen, which read as an
/// invisible boundary (2026-11-10, "make it so that this pop out can go anywhere on the
/// screen"). The pointer cannot leave the screen while dragging, so some of the window is
/// always left on it to drag back.
final class FreelyMovingPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
