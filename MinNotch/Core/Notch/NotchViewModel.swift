import AppKit
import Observation

/// What the notch surface is currently showing.
enum NotchState: Equatable {
    /// The thin pill.
    case collapsed
    /// The full panel.
    case expanded
    /// A brief automatic expansion that collapses itself again, used by the V2 sneak-peek
    /// on track change. Treated as collapsed for hit-testing purposes.
    case peeking
}

/// Drives one notch surface: its open/closed state, the selected tab, and hover intent.
///
/// One instance exists per display that shows a notch, so two displays can be expanded
/// independently. Shared data (now playing, calendar, battery) lives in services owned by
/// `AppEnvironment` and is read by every instance.
@Observable
@MainActor
final class NotchViewModel {
    private(set) var state: NotchState = .collapsed
    private(set) var geometry: NotchGeometry

    /// True while the pointer is inside the notch's interactive area.
    private(set) var isHovering = false

    /// Blocks the automatic close. Set while a text field in the panel has focus, because
    /// collapsing the panel out from under someone who is typing loses what they typed.
    var isInteractionLocked = false

    /// Kept open on purpose, by the Keep the Notch Open shortcut or the top bar's pin: the
    /// pointer leaving does not close it, and neither does a click on the panel. Anything that
    /// closes it on purpose (a swipe up, the shortcut that toggles it, a button that opens a
    /// window) also lets it go, so it can never be stuck open.
    private(set) var isKeptOpen = false
    /// Until when a pointer leaving does not close the panel. See `holdOpen(for:)`.
    @ObservationIgnored private var holdOpenUntil = Date.distantPast

    var selectedTab: NotchTab {
        didSet {
            // Links lives in the Shelf tab now; asking for it opens that.
            if selectedTab == .links { selectedTab = .shelf }
            // Anything that picks a tab while the panel is closed (a drag opening the Shelf, the
            // Notes shortcut) is choosing what to open on, so the default does not override it.
            if !isApplyingDefaultTab { returnsToDefaultTab = false }
            guard oldValue != selectedTab else { return }
            // Only the real notch writes the remembered tab. `lastTab` is one value shared
            // by every surface, so a virtual notch on a second monitor writing to it would
            // mean the two instances overwrote each other continuously, and whichever was
            // touched last decided what the built-in display opened on next launch.
            if geometry.hasPhysicalNotch {
                settings.general.lastTab = selectedTab
            }
            // Going back to the default happens as the panel opens, which already ticks.
            guard !isApplyingDefaultTab else { return }
            Haptics.perform(enabled: settings.advanced.hapticFeedbackEnabled, strength: settings.advanced.hapticStrength)
        }
    }

    @ObservationIgnored private let settings: SettingsStore
    /// Set when the panel closes with Remember Last Tab off, so the next open goes back to the
    /// Default Tab. Without it, Default Tab only chose the tab at launch and the panel then
    /// reopened on whatever was used last, which is what Remember Last Tab off says it will not do.
    @ObservationIgnored private var returnsToDefaultTab = false
    @ObservationIgnored private var isApplyingDefaultTab = false
    @ObservationIgnored private var hoverOpenWork: DispatchWorkItem?
    @ObservationIgnored private var peekCollapseWork: DispatchWorkItem?

    /// Called whenever the surface needs the window to change its click-through behaviour.
    @ObservationIgnored var onStateChange: ((NotchState) -> Void)?

    init(settings: SettingsStore, geometry: NotchGeometry) {
        self.settings = settings
        self.geometry = geometry
        self.selectedTab = Self.initialTab(settings: settings, geometry: geometry).panelTab
    }

    /// The tab this surface opens on.
    ///
    /// A display with no physical notch gets its own default. The distinction is not
    /// cosmetic: on the built-in display the closed pill sits behind the camera housing and
    /// is invisible, so opening on Now Playing with nothing playing costs nothing. On an
    /// external monitor the same surface is a black tab stuck to the top of the screen with
    /// no hardware to blend into, and it should be showing something worth the space it is
    /// taking. It also does not follow `lastTab`, because that value belongs to the real
    /// notch and this surface no longer writes to it.
    private static func initialTab(settings: SettingsStore, geometry: NotchGeometry) -> NotchTab {
        guard geometry.hasPhysicalNotch else {
            return settings.advanced.nonNotchDefaultTab
        }
        return settings.general.rememberLastTab
            ? settings.general.lastTab
            : settings.general.defaultTab
    }

    // MARK: Geometry

    /// Width of the open panel on this display.
    ///
    /// Capped by the geometry's ceiling, which is what lets the preview renderer squeeze the
    /// panel narrower than its content for the clip check.
    var expandedPanelWidth: CGFloat {
        min(
            NotchGeometry.panelWidth(settings: settings, cutoutWidth: geometry.collapsedSize.width),
            geometry.expandedSize.width
        )
    }

    func update(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    /// The open panel's top bar as it is drawn right now: the user's arrangement, placed into the
    /// room there is. One builder for `ExpandedPanelView` and for the swipe between tabs, so the
    /// swipe goes in the order the bar shows. It used to step through `availableTabs`, which is
    /// the registry's fixed order, so after a tab was moved in Settings > Layout the swipe
    /// skipped over it and came back to it out of place.
    func topStripLayout(battery: BatteryStatus) -> TopStripLayout {
        TopStripLayout.make(
            leading: settings.appearance.topStripLeading,
            trailing: settings.appearance.topStripTrailing,
            availableTabs: availableTabs,
            batteryWidth: battery.isPresent
                ? TopStripLayout.batteryWidth(showPercentage: settings.battery.showPercentage)
                : nil,
            showsDebug: settings.advanced.showDebugButtons,
            showsKeepOpen: isKeptOpen,
            panelWidth: expandedPanelWidth,
            cutoutWidth: geometry.collapsedSize.width
        )
    }

    /// Tabs currently worth showing. Recomputed on every read so toggling a feature in
    /// Settings updates the strip immediately.
    var availableTabs: [NotchTab] {
        NotchWidgetRegistry.shownTabs(settings)
    }

    /// Keeps `selectedTab` pointing at something that still exists after a feature is
    /// switched off in Settings.
    func reconcileSelectedTab() {
        let tabs = availableTabs
        if !tabs.contains(selectedTab), let first = tabs.first {
            selectedTab = first
        }
    }

    // MARK: State transitions

    func expand() {
        cancelPendingWork()
        guard state != .expanded else { return }
        applyDefaultTabIfNeeded()
        setState(.expanded)
    }

    func collapse() {
        cancelPendingWork()
        isKeptOpen = false
        releaseSwipeAnchor()
        guard state != .collapsed else { return }
        setState(.collapsed)
        // The real notch only: a display without one never remembers and has its own default.
        returnsToDefaultTab = geometry.hasPhysicalNotch && !settings.general.rememberLastTab
    }

    /// Settings > General > Tabs: with Remember Last Tab off, every open starts on Default Tab,
    /// unless something chose a tab since the panel closed.
    private func applyDefaultTabIfNeeded() {
        guard returnsToDefaultTab else { return }
        returnsToDefaultTab = false
        let tab = settings.general.defaultTab
        guard availableTabs.contains(tab) else { return }
        isApplyingDefaultTab = true
        selectedTab = tab
        isApplyingDefaultTab = false
    }

    /// Opens and holds the panel, or lets it go. Letting go closes it unless the pointer is
    /// over it, the same as if the pointer had just left.
    func setKeptOpen(_ keep: Bool) {
        if keep {
            expand()
            isKeptOpen = true
        } else {
            isKeptOpen = false
            if !isHovering { collapse() }
        }
    }

    func toggle() {
        state == .expanded ? collapse() : expand()
    }

    /// Briefly expands and collapses again. The V2 sneak-peek on track change calls this;
    /// it is wired up now so the animation path is exercised by the shortcut layer.
    func peek(for duration: TimeInterval = 2.0) {
        guard state == .collapsed else { return }
        setState(.peeking)

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state == .peeking else { return }
            self.setState(.collapsed)
        }
        peekCollapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func setState(_ newState: NotchState) {
        let wasCollapsed = state == .collapsed
        state = newState

        // A tick on the way open and on the way closed, matching how the system's own
        // trackpad affordances feel. No-ops on hardware without a Force Touch trackpad.
        if wasCollapsed != (newState == .collapsed) {
            Haptics.perform(enabled: settings.advanced.hapticFeedbackEnabled, strength: settings.advanced.hapticStrength)
        }

        onStateChange?(newState)
    }

    private func cancelPendingWork() {
        hoverOpenWork?.cancel()
        hoverOpenWork = nil
        peekCollapseWork?.cancel()
        peekCollapseWork = nil
    }

    // MARK: Hover intent

    /// Called by the view when the pointer enters or leaves the interactive area.
    ///
    /// The delay is dwell time, not an animation delay: leaving before it elapses cancels
    /// the expansion, so sweeping the pointer across the menu bar does not open the panel.
    func hoverChanged(_ hovering: Bool) {
        isHovering = hovering

        guard settings.general.hoverToOpen else {
            if !hovering { scheduleCloseIfNeeded() }
            return
        }

        if hovering {
            hoverOpenWork?.cancel()
            let delay = max(0, settings.general.hoverOpenDelay)
            guard delay > 0 else { expand(); return }

            let work = DispatchWorkItem { [weak self] in
                guard let self, self.isHovering else { return }
                self.expand()
            }
            hoverOpenWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            hoverOpenWork?.cancel()
            hoverOpenWork = nil
            scheduleCloseIfNeeded()
        }
    }

    /// Keeps the panel open for a moment whatever the pointer does, for a change the panel makes
    /// to itself: a swipe to a shorter tab shrinks it out from under the pointer.
    func holdOpen(for seconds: TimeInterval) {
        holdOpenUntil = Date().addingTimeInterval(seconds)
    }

    /// Changes tab for a two-finger swipe. The panel takes the new tab's height straight away,
    /// on the same spring as the content, and stays the pointer's panel for as long as the
    /// pointer has not moved (`swipeAnchor`), even where a shorter tab has left it over nothing.
    ///
    /// It used to keep the height it had for 0.8 s instead, so a run of swipes stayed under the
    /// fingers, but that made every resize trail the content it was for: the user saw the panel
    /// swap from the Shelf to Notes and only then shrink, "queuing".
    func swipe(to tab: NotchTab) {
        holdOpen(for: 0.8)
        guard state == .expanded else {
            selectedTab = tab
            return
        }
        // The tallest the panel was in this run of swipes, so a second swipe from a short tab
        // is still caught where the first one started.
        swipeCatchHeight = max(swipeCatchHeight, lastPanelHeight)
        swipeAnchor = NSEvent.mouseLocation
        selectedTab = tab
        swipeWatch?.invalidate()
        swipeWatch = Timer.onMain(every: 0.1) { [weak self] in self?.checkSwipeAnchor() }
    }

    /// Where the pointer was at the last swipe that changed tab, while it has not moved since.
    /// Two fingers on a trackpad do not move the pointer, so after a swipe to a shorter tab it
    /// sits below the panel over nothing; until it moves, it still counts as over the panel, so
    /// the next swipe changes tab again and the panel does not close.
    @ObservationIgnored private var swipeAnchor: CGPoint?
    @ObservationIgnored private var swipeWatch: Timer?
    /// How tall the panel's catch area stays while the pointer rests after a swipe
    /// (`NotchRootView.swipeCatcher`). Zero otherwise.
    private(set) var swipeCatchHeight: CGFloat = 0
    /// The open panel's height as last drawn, kept by `NotchRootView` for the catch area.
    @ObservationIgnored var lastPanelHeight: CGFloat = 0

    /// Whether the pointer is resting where it was at the last tab swipe, on an open panel.
    var isHeldBySwipe: Bool { swipeAnchor != nil && state == .expanded }

    private func checkSwipeAnchor() {
        guard let anchor = swipeAnchor, state == .expanded else {
            releaseSwipeAnchor()
            return
        }
        let pointer = NSEvent.mouseLocation
        guard hypot(pointer.x - anchor.x, pointer.y - anchor.y) > 2 else { return }
        releaseSwipeAnchor()
        // Moved off the panel while it was held: the same as the pointer leaving.
        if !isHovering { scheduleCloseIfNeeded() }
    }

    private func releaseSwipeAnchor() {
        swipeWatch?.invalidate()
        swipeWatch = nil
        swipeAnchor = nil
        if swipeCatchHeight != 0 { swipeCatchHeight = 0 }
    }

    private func scheduleCloseIfNeeded() {
        guard !isInteractionLocked, !isKeptOpen else { return }
        guard settings.general.closeOnMouseExit, state == .expanded else { return }
        // A short grace period stops the panel snapping shut when the pointer crosses a
        // gap between two subviews, and lasts until any hold is over.
        let delay = max(0.25, holdOpenUntil.timeIntervalSinceNow)
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isHovering, !self.isInteractionLocked, !self.isKeptOpen,
                  !self.isHeldBySwipe else { return }
            self.collapse()
        }
        hoverOpenWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Click on the collapsed pill.
    func clicked() {
        guard settings.general.clickToOpen, !isKeptOpen else { return }
        toggle()
    }
}
