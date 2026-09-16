import AppKit

/// Where the notch surface sits on a given display, and how big it is in each state.
///
/// A display without a physical notch is a first-class case, not a fallback: every Mac
/// mini, Studio, and external monitor lands here, so the virtual notch gets its size from
/// `AdvancedSettings` and is drawn with the same shape as a real one.
struct NotchGeometry: Equatable {
    /// Stable identifier of the display this describes.
    let displayID: CGDirectDisplayID
    /// The display's full frame in global (bottom-left origin) coordinates.
    let screenFrame: CGRect
    /// True when the display has a hardware notch cut into the menu bar.
    let hasPhysicalNotch: Bool
    /// Size of the closed pill.
    let collapsedSize: CGSize
    /// Maximum size the expanded panel may take.
    let expandedSize: CGSize
    /// Frame of the borderless window that hosts both states.
    let windowFrame: CGRect

    /// Slack around the panel so the ambient glow, the shadow, and the sneak-peek overshoot
    /// are not clipped. The glow is the widest of the three and sets the number: it needs
    /// `Metrics.notchGlowSpill` on every side or its blur is cut off at the window edge.
    private static let windowPadding = CGSize(
        width: Metrics.notchGlowSpill * 2,
        height: Metrics.notchGlowSpill * 2
    )

    static func make(for screen: NSScreen, settings: SettingsStore) -> NotchGeometry {
        let frame = screen.frame
        let physical = physicalNotchSize(of: screen)

        let collapsed: CGSize
        switch settings.advanced.notchHeightMode {
        case .matchPhysical:
            collapsed = physical ?? CGSize(
                width: CGFloat(settings.advanced.virtualNotchWidth),
                height: CGFloat(settings.advanced.virtualNotchHeight)
            )
        case .fixed:
            collapsed = CGSize(
                width: physical?.width ?? CGFloat(settings.advanced.virtualNotchWidth),
                height: CGFloat(settings.advanced.virtualNotchHeight)
            )
        }

        let expanded = CGSize(
            width: max(panelWidth(settings: settings, cutoutWidth: collapsed.width), collapsed.width + 260),
            height: Metrics.maxPanelHeight
        )

        let windowSize = CGSize(
            width: min(expanded.width + windowPadding.width, frame.width),
            height: min(expanded.height + windowPadding.height, frame.height)
        )

        // Anchor to the top edge of this display, horizontally centred on the notch.
        let windowFrame = CGRect(
            x: frame.midX - windowSize.width / 2,
            y: frame.maxY - windowSize.height,
            width: windowSize.width,
            height: windowSize.height
        )

        return NotchGeometry(
            displayID: displayID(of: screen),
            screenFrame: frame,
            hasPhysicalNotch: physical != nil,
            collapsedSize: collapsed,
            expandedSize: expanded,
            windowFrame: windowFrame
        )
    }

    /// Width of the open panel: the user's choice, widened only if the top bar cannot fit every
    /// item either side of the cutout even with its buttons at their tightest.
    ///
    /// The top bar puts controls either side of the cutout, so the panel also has to leave
    /// usable room on both flanks, which `make` adds on top.
    static func panelWidth(settings: SettingsStore, cutoutWidth: CGFloat) -> CGFloat {
        let minimum = TopStripLayout.minimumPanelWidth(
            leading: settings.appearance.topStripLeading,
            trailing: settings.appearance.topStripTrailing,
            availableTabs: NotchWidgetRegistry.shownTabs(settings),
            showPercentage: settings.battery.showPercentage,
            showsDebug: settings.advanced.showDebugButtons,
            cutoutWidth: cutoutWidth
        )
        return max(CGFloat(settings.appearance.expandedWidth), minimum)
    }

    /// Measures the hardware notch, or returns nil when the display has none.
    ///
    /// `safeAreaInsets.top` gives the height. The width comes from the two auxiliary menu
    /// bar areas either side of the cutout: whatever the screen is not covering with those
    /// is the notch itself.
    private static func physicalNotchSize(of screen: NSScreen) -> CGSize? {
        let topInset = screen.safeAreaInsets.top
        guard topInset > 0 else { return nil }

        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else {
            // Notched, but the auxiliary areas are unavailable. Apple's cutouts are all
            // close to this width, so it is a better guess than giving up.
            return CGSize(width: 200, height: topInset)
        }

        let width = screen.frame.width - left.width - right.width
        guard width > 0 else { return CGSize(width: 200, height: topInset) }
        return CGSize(width: width, height: topInset)
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return screen.deviceDescription[key] as? CGDirectDisplayID ?? 0
    }

    /// Rect of the collapsed pill inside the window's own coordinate space.
    var collapsedRectInWindow: CGRect {
        CGRect(
            x: (windowFrame.width - collapsedSize.width) / 2,
            y: windowFrame.height - collapsedSize.height,
            width: collapsedSize.width,
            height: collapsedSize.height
        )
    }
}

extension NSScreen {
    /// The display that currently contains the pointer, or the main display.
    static var underPointer: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(location) } ?? .main
    }

    var isBuiltIn: Bool {
        CGDisplayIsBuiltin(NotchGeometry.displayID(of: self)) != 0
    }
}
