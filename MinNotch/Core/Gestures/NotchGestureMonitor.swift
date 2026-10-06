import AppKit

/// Recognises two-finger trackpad swipes over the notch.
///
/// A listen-only event tap on scroll events, consulted only while the pointer is over a notch
/// (`pointerPanel`), so scrolling the Settings window or any other app never moves it. It used to
/// be a local event monitor, which worked over the top bar and nowhere else: a scroll view under
/// the pointer (the clipboard, the calendar's list, the shelf, Notes, the lyrics) takes a trackpad
/// gesture's events for itself after the first, straight off the queue, so the monitor never saw
/// the swipe. A tap sees every event before any window does. It needs no permission, since it only
/// listens; if it cannot be made, the local monitor is the fallback.
///
/// A view in the hierarchy handling `scrollWheel` would have to win hit-testing to get the events,
/// and winning it would also swallow the clicks the panel needs, which is why neither approach is
/// a view.
@MainActor
final class NotchGestureMonitor {
    enum Direction {
        case left, right, up, down
    }

    /// Fired once per gesture, on the main thread.
    var onSwipe: ((Direction) -> Void)?

    /// The notch panel the pointer is over, if any. `AppEnvironment` answers it from the panels'
    /// hover state.
    var pointerPanel: (() -> NotchPanel?)?

    private var monitor: Any?
    nonisolated(unsafe) private var tap: CFMachPort?
    nonisolated(unsafe) private var tapSource: CFRunLoopSource?
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
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tap = nil
        tapSource = nil
        reset()
    }

    private func install() {
        guard monitor == nil, tap == nil else { return }

        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<NotchGestureMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.handleTapped(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }
        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1) << CGEventType.scrollWheel.rawValue,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            self.tap = tap
            tapSource = source
            return
        }

        AppLog.app.notice("Swipe tap unavailable; listening inside the notch's windows instead")
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            if let window = event.window as? NotchPanel { self?.handle(event, in: window) }
            return event
        }
    }

    /// From the tap, on the main run loop.
    private func handleTapped(type: CGEventType, event: CGEvent) {
        // The system switches off a tap whose callback was slow, or during secure input.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .scrollWheel,
              let window = pointerPanel?(),
              let nsEvent = NSEvent(cgEvent: event) else { return }
        handle(nsEvent, in: window)
    }

    private func reset() {
        accumulatedX = 0
        accumulatedY = 0
        hasFiredThisGesture = false
        beganOverScrollableList = false
    }

    private func handle(_ event: NSEvent, in window: NotchPanel) {
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
        // From the pointer, not the event: an event from the tap belongs to no window, so its
        // location is not in this one's coordinates.
        let point = content.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
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
