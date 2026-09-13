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
    }

    private func handle(_ event: NSEvent) {
        guard event.window is NotchPanel else { return }

        // Momentum is the coasting after the fingers lift. Counting it would let one flick
        // fire several times as the deltas trail off.
        guard event.momentumPhase == [] else { return }

        switch event.phase {
        case .began:
            reset()
        case .ended, .cancelled:
            reset()
            return
        default:
            break
        }

        guard !hasFiredThisGesture else { return }

        accumulatedX += event.scrollingDeltaX
        accumulatedY += event.scrollingDeltaY

        let threshold = Self.threshold(for: settings?.advanced.gestureSensitivity ?? 0.5)
        let horizontal = abs(accumulatedX)
        let vertical = abs(accumulatedY)

        guard max(horizontal, vertical) >= threshold else { return }
        hasFiredThisGesture = true

        // Whichever axis moved furthest wins, so a slightly diagonal swipe still does the
        // thing the user obviously meant.
        let direction: Direction
        if horizontal >= vertical {
            direction = accumulatedX < 0 ? .left : .right
        } else {
            direction = accumulatedY < 0 ? .up : .down
        }

        let callback = onSwipe
        DispatchQueue.main.async { callback?(direction) }
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
