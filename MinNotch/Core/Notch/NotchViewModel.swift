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
final class NotchViewModel {
    private(set) var state: NotchState = .collapsed
    private(set) var geometry: NotchGeometry

    /// True while the pointer is inside the notch's interactive area.
    private(set) var isHovering = false

    /// Blocks the automatic close. Set while a text field in the panel has focus, because
    /// collapsing the panel out from under someone who is typing loses what they typed.
    var isInteractionLocked = false

    var selectedTab: NotchTab {
        didSet {
            guard oldValue != selectedTab else { return }
            // Only the real notch writes the remembered tab. `lastTab` is one value shared
            // by every surface, so a virtual notch on a second monitor writing to it would
            // mean the two instances overwrote each other continuously, and whichever was
            // touched last decided what the built-in display opened on next launch.
            if geometry.hasPhysicalNotch {
                settings.general.lastTab = selectedTab
            }
            Haptics.perform(enabled: settings.advanced.hapticFeedbackEnabled, strength: settings.advanced.hapticStrength)
        }
    }

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private var hoverOpenWork: DispatchWorkItem?
    @ObservationIgnored private var peekCollapseWork: DispatchWorkItem?

    /// Called whenever the surface needs the window to change its click-through behaviour.
    @ObservationIgnored var onStateChange: ((NotchState) -> Void)?

    init(settings: SettingsStore, geometry: NotchGeometry) {
        self.settings = settings
        self.geometry = geometry
        self.selectedTab = Self.initialTab(settings: settings, geometry: geometry)
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

    func update(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    /// Tabs currently worth showing. Recomputed on every read so toggling a feature in
    /// Settings updates the strip immediately.
    var availableTabs: [NotchTab] {
        let tabs = NotchWidgetRegistry.availableTabs(settings)
        return tabs.isEmpty ? [.system] : tabs
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
        setState(.expanded)
    }

    func collapse() {
        cancelPendingWork()
        guard state != .collapsed else { return }
        setState(.collapsed)
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

    private func scheduleCloseIfNeeded() {
        guard !isInteractionLocked else { return }
        guard settings.general.closeOnMouseExit, state == .expanded else { return }
        // A short grace period stops the panel snapping shut when the pointer crosses a
        // gap between two subviews.
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isHovering, !self.isInteractionLocked else { return }
            self.collapse()
        }
        hoverOpenWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// Click on the collapsed pill.
    func clicked() {
        guard settings.general.clickToOpen else { return }
        toggle()
    }
}
