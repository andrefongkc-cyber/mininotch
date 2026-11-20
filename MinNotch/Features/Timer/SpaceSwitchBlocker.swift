import AppKit
import ApplicationServices
import CoreGraphics

/// Keeps the user on the desktop they are on while Focus is switched on in the Timer tab
/// (2026-11-19, the user's "when u press the focus button … u cannot swipe desktop screens").
///
/// A session event tap that drops what moves between desktops before the Dock sees it:
/// - the trackpad's dock swipe, which reaches the Dock as event type 30 (`kCGSEventDockControl`)
///   and as gesture events (type 29) whose HID type (field 110) is 23, `kIOHIDEventTypeDockSwipe`.
///   Mac Mouse Fix makes the Dock switch desktops by posting exactly these, which is why dropping
///   them is expected to stop it. That covers swiping between desktops and full-screen apps, and
///   the swipe up for Mission Control, which is another way to change desktop;
/// - Control with ← or → and Control with a number, the keyboard's way to the next desktop or to
///   a numbered one.
///
/// Dropping events needs Accessibility, as the volume keys' tap does; without it this does
/// nothing and says so in the log. Not tried against a real swipe here: the tap cannot be
/// checked without moving the user's own desktops.
///
/// `@unchecked Sendable` rather than `@MainActor`, as `SystemKeyInterceptor` is: the tap's
/// callback hands it a `CGEvent`, which is not `Sendable`, and it is only ever started, stopped
/// and called on the main thread, since the tap's source is on the main run loop.
final class SpaceSwitchBlocker: @unchecked Sendable {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    /// Installs the tap. False without Accessibility.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard AXIsProcessTrusted() else {
            AppLog.app.notice("Focus cannot stop desktop swipes: MiniNotch has no Accessibility access")
            return false
        }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let blocker = Unmanaged<SpaceSwitchBlocker>.fromOpaque(context).takeUnretainedValue()
            return blocker.handle(type: type, event: event)
        }
        let mask = (CGEventMask(1) << Self.gestureType)
            | (CGEventMask(1) << Self.dockControlType)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            AppLog.app.error("Could not install the desktop swipe tap")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        AppLog.app.notice("Focus: desktop swipes blocked")
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        self.source = nil
        AppLog.app.notice("Focus: desktop swipes allowed again")
    }

    // MARK: Events

    private static let gestureType: CGEventType.RawValue = 29
    private static let dockControlType: CGEventType.RawValue = 30
    /// `kCGEventGestureHIDType`, and the value it has for a dock swipe.
    private static let gestureHIDTypeField = CGEventField(rawValue: 110)!
    private static let dockSwipeHIDType: Int64 = 23

    /// ←, →, and the number row's 1 to 9.
    private static let desktopKeys: Set<Int64> = [123, 124, 18, 19, 20, 21, 23, 22, 26, 28, 25]

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        switch type.rawValue {
        case Self.dockControlType:
            return nil
        case Self.gestureType:
            return event.getIntegerValueField(Self.gestureHIDTypeField) == Self.dockSwipeHIDType
                ? nil : Unmanaged.passUnretained(event)
        case CGEventType.keyDown.rawValue, CGEventType.keyUp.rawValue:
            let flags = event.flags
            let onlyControl = flags.contains(.maskControl)
                && !flags.contains(.maskCommand) && !flags.contains(.maskAlternate)
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            return onlyControl && Self.desktopKeys.contains(key) ? nil : Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
