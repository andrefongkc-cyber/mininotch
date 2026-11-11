import AppKit
import SwiftUI

/// A panel that stays wherever it is dragged, menu bar included.
///
/// The pop-out windows carry transparent room around what they draw (the Now Playing card has
/// the glow's margin and its drag strip above it), and macOS holds a window's top edge below
/// the menu bar, so the card itself stopped well short of the top of the screen, which read as
/// an invisible boundary (2026-11-10, "make it so that this pop out can go anywhere on the
/// screen"). Overriding `constrainFrameRect` alone did not do it: a drag by the window
/// background (`isMovableByWindowBackground`) is run by the window server, which holds the
/// window under the menu bar itself. So the window is moved by `.movesWindow()`, a drag
/// gesture under everything else in the view (a button or the scrubber still takes its own
/// drag), which sets the origin directly, and nothing constrains that. What it draws stops at the
/// screen's edges (`drawnInset`, `keptOnScreen`).
final class FreelyMovingPanel: NSPanel {
    /// Transparent room around what the window draws (the Now Playing card's glow margin).
    /// A drag keeps what is drawn on the screen, edge to edge, up to the menu bar, and lets
    /// this room hang off it (2026-11-10, "make the bounding box the dimensions of the popup
    /// and not just my mouse").
    var drawnInset: CGFloat = 0

    /// The origin for `proposed`, moved just enough that the drawn part of the window stays
    /// on the screen under the pointer.
    func keptOnScreen(_ proposed: NSPoint, pointer: NSPoint) -> NSPoint {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? screen
        else { return proposed }
        // The visible frame: the menu bar and the Dock draw over a floating window, so a card
        // dragged under either was half hidden.
        let bounds = screen.visibleFrame
        let drawn = CGSize(width: frame.width - drawnInset * 2, height: frame.height - drawnInset * 2)
        guard drawn.width <= bounds.width, drawn.height <= bounds.height else { return proposed }
        let x = min(max(proposed.x + drawnInset, bounds.minX), bounds.maxX - drawn.width) - drawnInset
        let y = min(max(proposed.y + drawnInset, bounds.minY), bounds.maxY - drawn.height) - drawnInset
        return NSPoint(x: x, y: y)
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

extension View {
    /// Dragging anywhere that is not a control moves the `FreelyMovingPanel` this is in.
    func movesWindow() -> some View { modifier(MovesWindow()) }
}

private struct MovesWindow: ViewModifier {
    @State private var drag: (window: NSWindow, pointer: NSPoint, origin: NSPoint)?

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { _ in
                    // The pointer on screen, not the gesture's translation: the view moves with
                    // the window, so a translation measured in it would chase itself.
                    let pointer = NSEvent.mouseLocation
                    if drag == nil {
                        // `NSApp.windows`, not `orderedWindows`, which leaves panels out: the
                        // first version used it, found no window, and nothing moved.
                        guard let window = NSApp.windows.first(where: {
                            $0 is FreelyMovingPanel && $0.isVisible && $0.frame.contains(pointer)
                        }) else { return }
                        drag = (window, pointer, window.frame.origin)
                    }
                    guard let drag else { return }
                    var origin = NSPoint(x: drag.origin.x + pointer.x - drag.pointer.x,
                                         y: drag.origin.y + pointer.y - drag.pointer.y)
                    if let panel = drag.window as? FreelyMovingPanel {
                        origin = panel.keptOnScreen(origin, pointer: pointer)
                    }
                    drag.window.setFrameOrigin(origin)
                }
                .onEnded { _ in
                    if let window = drag?.window, !window.frameAutosaveName.isEmpty {
                        window.saveFrame(usingName: window.frameAutosaveName)
                    }
                    drag = nil
                }
        )
    }
}
