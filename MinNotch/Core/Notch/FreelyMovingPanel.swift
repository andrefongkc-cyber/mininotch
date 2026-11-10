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
/// drag), which sets the origin directly, and nothing constrains that. The pointer cannot leave
/// the screen, so some of the window is always left on it to drag back.
final class FreelyMovingPanel: NSPanel {
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
                    drag.window.setFrameOrigin(NSPoint(x: drag.origin.x + pointer.x - drag.pointer.x,
                                                       y: drag.origin.y + pointer.y - drag.pointer.y))
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
