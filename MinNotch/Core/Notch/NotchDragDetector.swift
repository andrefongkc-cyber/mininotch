import AppKit

/// Notices a file or link being dragged anywhere on screen, and where the pointer is while it is.
///
/// The notch used to find out about a drag the ordinary way, from the drop target on its own
/// window (`NotchRootView`'s `NotchDragOpener`). Since the notch moved into a window server space
/// of its own (`NotchSpace`), dragging a file to the closed notch no longer opened it: the user
/// dragged files to the notch for AirDrop and nothing happened (2026-10-22). Boring Notch, which
/// keeps its notch in such a space too, watches the drag itself (its `DragDetector`), and so does
/// this: a global monitor on the mouse while the left button is held, and the drag pasteboard,
/// whose change count moves when a drag session starts with something on it.
///
/// Global monitors for mouse events need no permission (keyboard ones do), and they only fire
/// while the mouse is down and moving, so there is no cost at rest.
@MainActor
final class NotchDragDetector {
    enum Payload {
        case files
        case link
    }

    /// The pointer's place on screen while something is being dragged, in screen coordinates, and
    /// what is being dragged.
    var onDragMove: ((CGPoint, Payload) -> Void)?
    /// The drag is over, dropped or not.
    var onDragEnd: (() -> Void)?

    private let pasteboard = NSPasteboard(name: .drag)
    private var monitors: [Any] = []
    private var changeCountAtMouseDown = -1
    private var isMouseDown = false
    private var payload: Payload?

    func start() {
        guard monitors.isEmpty else { return }
        let down = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown() }
        }
        let dragged = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDragged() }
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseUp() }
        }
        monitors = [down, dragged, up].compactMap { $0 }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        isMouseDown = false
        payload = nil
    }

    private func mouseDown() {
        changeCountAtMouseDown = pasteboard.changeCount
        isMouseDown = true
        payload = nil
    }

    private func mouseDragged() {
        guard isMouseDown else { return }
        // Something is being dragged once the drag pasteboard has changed since the button went
        // down; a plain drag (selecting text, moving a window) leaves it alone.
        if payload == nil, pasteboard.changeCount != changeCountAtMouseDown {
            payload = Self.payload(of: pasteboard)
        }
        guard let payload else { return }
        onDragMove?(NSEvent.mouseLocation, payload)
    }

    private func mouseUp() {
        guard isMouseDown else { return }
        let wasDragging = payload != nil
        isMouseDown = false
        payload = nil
        if wasDragging { onDragEnd?() }
    }

    /// Files before links: a file is also a URL, and dragging a document must open the Shelf.
    private static func payload(of pasteboard: NSPasteboard) -> Payload? {
        let types = pasteboard.types ?? []
        if types.contains(.fileURL) { return .files }
        if types.contains(.URL) || types.contains(.string) { return .link }
        return nil
    }
}
