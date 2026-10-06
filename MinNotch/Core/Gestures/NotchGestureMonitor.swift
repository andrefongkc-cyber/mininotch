import AppKit

/// Recognises two-finger trackpad swipes over the notch.
///
/// Implemented as a local event monitor rather than as a view that handles `scrollWheel`.
/// A view in the hierarchy would have to win AppKit hit-testing to receive scroll events,
/// and winning it would also swallow the clicks the panel needs. A monitor sees the events
/// without being in the responder chain at all.
///
/// Only events destined for a `NotchPanel` are considered, so scrolling the Settings window
/// or any other window never moves the notch.
@MainActor
final class NotchGestureMonitor {
    enum Direction {
        case left, right, up, down
    }

    /// Fired once per gesture, on the main thread.
    var onSwipe: ((Direction) -> Void)?

    private var monitor: Any?
    private var settings: SettingsStore?

    private var accumulatedX: CGFloat = 0
    private var accumulatedY: CGFloat = 0
    /// One swipe should do one thing, however long the fingers keep moving.
    private var hasFiredThisGesture = false
    /// Whether this gesture began over a list that can scroll, where an up or down swipe is the
    /// list scrolling and not a request to open or close the notch.
    private var beganOverScrollableList = false
    /// A mouse wheel sends no phases, so there is no "began" to start a new gesture: a pause
    /// between clicks of the wheel has to stand in for one.
    private var lastEventAt = Date.distantPast

    func start(settings: SettingsStore) {
        self.settings = settings
        applySettings()
    }

    /// Installs or removes the monitor to match the current setting.
    func applySettings() {
        let enabled = settings?.advanced.twoFingerGesturesEnabled ?? false
        enabled ? install() : stop()
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        reset()
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    private func reset() {
        accumulatedX = 0
        accumulatedY = 0
        hasFiredThisGesture = false
        beganOverScrollableList = false
    }

    private func handle(_ event: NSEvent) {
        guard let window = event.window as? NotchPanel else { return }

        let now = Date()
        defer { lastEventAt = now }

        // Momentum is the coasting after the fingers lift, and it belongs to the swipe that
        // started it: a quick flick does most of its travel there, so ignoring it, as this
        // once did, dropped flicks that never reached the threshold with the fingers down.
        // Counted towards the same gesture, which still fires once, so the trailing deltas can
        // never fire it again. The gesture is only over when the next one begins.
        if event.momentumPhase != [] {
            guard !hasFiredThisGesture else { return }
            accumulate(event, window: window)
            return
        }

        switch event.phase {
        case .began:
            reset()
            beganOverScrollableList = Self.isOverScrollableList(event, in: window)
        case .ended, .cancelled:
            return
        case []:
            // A mouse wheel: no phases at all, so a quiet moment starts the next gesture.
            if now.timeIntervalSince(lastEventAt) > 0.35 {
                reset()
                beganOverScrollableList = Self.isOverScrollableList(event, in: window)
            }
        default:
            break
        }

        guard !hasFiredThisGesture else { return }
        accumulate(event, window: window)
    }

    private func accumulate(_ event: NSEvent, window: NSWindow) {
        // In the direction the fingers moved, whichever way Natural Scrolling has the content
        // go. The deltas follow the content, so with Natural Scrolling off every swipe used to
        // come out backwards.
        let sign: CGFloat = event.isDirectionInvertedFromDevice ? -1 : 1
        accumulatedX += event.scrollingDeltaX * sign
        accumulatedY += event.scrollingDeltaY * sign

        let threshold = Self.threshold(for: settings?.advanced.gestureSensitivity ?? 0.5)
        let horizontal = abs(accumulatedX)
        let vertical = abs(accumulatedY)

        guard max(horizontal, vertical) >= threshold else { return }
        hasFiredThisGesture = true

        // Over a list that scrolls, up and down belong to the list: scrolling the clipboard or
        // the calendar used to close the notch once the fingers had travelled far enough.
        // Sideways still changes tab.
        if beganOverScrollableList, vertical > horizontal {
            hasFiredThisGesture = true
            return
        }

        // Whichever axis moved furthest wins, so a slightly diagonal swipe still does the
        // thing the user obviously meant. Fingers moving left or up give positive values.
        let direction: Direction
        if horizontal >= vertical {
            direction = accumulatedX > 0 ? .left : .right
        } else {
            direction = accumulatedY > 0 ? .up : .down
        }

        let callback = onSwipe
        DispatchQueue.main.async { callback?(direction) }
    }

    /// Whether the pointer is over a scroll view with more in it than shows, which SwiftUI's
    /// `ScrollView` is on the Mac.
    private static func isOverScrollableList(_ event: NSEvent, in window: NSWindow) -> Bool {
        guard let content = window.contentView else { return false }
        let point = content.convert(event.locationInWindow, from: nil)
        var view = content.hitTest(point)
        while let current = view {
            if let scroll = current as? NSScrollView,
               let document = scroll.documentView,
               document.frame.height > scroll.contentView.bounds.height + 1 {
                return true
            }
            view = current.superview
        }
        return false
    }

    /// Maps the 0...1 sensitivity slider onto a scroll distance.
    ///
    /// Inverted, because a higher sensitivity should mean less finger travel. The range is
    /// chosen so the low end still needs a deliberate swipe and the high end does not fire
    /// on an accidental brush.
    private static func threshold(for sensitivity: Double) -> CGFloat {
        let clamped = min(max(sensitivity, 0), 1)
        return 130 - (clamped * 100)
    }
}
