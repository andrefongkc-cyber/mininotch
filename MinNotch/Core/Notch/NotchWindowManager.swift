import AppKit

/// Creates and tears down notch surfaces as displays come and go.
///
/// Multi-display is treated as the normal case rather than an afterthought. Three
/// behaviours are supported: follow the pointer with a single surface, pin to the built-in
/// display, or put one surface on every display. Displays without a physical notch are
/// eligible in all three, gated only by the Advanced setting.
@MainActor
final class NotchWindowManager {
    private unowned let environment: AppEnvironment
    private var controllers: [CGDirectDisplayID: NotchWindowController] = [:]
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var pointerMonitor: Any?
    private var lastPointerDisplay: CGDirectDisplayID?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var allViewModels: [NotchViewModel] { controllers.values.map(\.viewModel) }

    // MARK: Lifecycle

    func start() {
        rebuild()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }

        // Moving to another desktop puts an open panel away, unless it is being kept open. The
        // panel stays on screen through the move, above everything, and anything animating in
        // it (the visualizer, the lyrics, the glow) had macOS redraw the whole transition, and
        // Mission Control, for every frame: the user saw the GPU climb.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                for viewModel in self?.allViewModels ?? [] where viewModel.state == .expanded && !viewModel.isKeptOpen {
                    viewModel.collapse()
                }
            }
        }

        startPointerTrackingIfNeeded()
    }

    func stop() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        spaceObserver = nil
        stopPointerTracking()
        controllers.values.forEach { $0.hide() }
        controllers.removeAll()
    }

    /// Re-evaluates which displays should have a surface, keeping existing ones in place.
    func rebuild() {
        let targets = targetScreens()
        let wantedIDs = Set(targets.map(NotchGeometry.displayID(of:)))

        for (id, controller) in controllers where !wantedIDs.contains(id) {
            controller.hide()
            controllers.removeValue(forKey: id)
        }

        for screen in targets {
            let id = NotchGeometry.displayID(of: screen)
            if let existing = controllers[id] {
                existing.updateGeometry()
            } else {
                let controller = NotchWindowController(screen: screen, environment: environment)
                controllers[id] = controller
                controller.show()
            }
        }

        startPointerTrackingIfNeeded()
    }

    /// Applies a settings change that affects size or which displays are used.
    func settingsChanged() {
        rebuild()
        controllers.values.forEach { $0.viewModel.reconcileSelectedTab() }
    }

    private func targetScreens() -> [NSScreen] {
        let settings = environment.settings
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return [] }

        let eligible = settings.advanced.showOnNonNotchDisplays
            ? screens
            : screens.filter { $0.safeAreaInsets.top > 0 }

        // Never leave the user with nothing: if the filter removed every display, fall back
        // to the main one rather than silently hiding the app.
        let pool = eligible.isEmpty ? Array(screens.prefix(1)) : eligible

        switch settings.advanced.displayTargeting {
        case .allDisplays:
            return pool
        case .builtInOnly:
            let builtIn = pool.filter(\.isBuiltIn)
            return builtIn.isEmpty ? Array(pool.prefix(1)) : builtIn
        case .activeDisplay:
            let pointerScreen = NSScreen.underPointer
            if let pointerScreen, pool.contains(where: {
                NotchGeometry.displayID(of: $0) == NotchGeometry.displayID(of: pointerScreen)
            }) {
                return [pointerScreen]
            }
            return Array(pool.prefix(1))
        }
    }

    // MARK: Following the pointer

    /// Watches the pointer only in `.activeDisplay` mode, and only when more than one
    /// display is attached, so the common single-display case installs no monitor at all.
    private func startPointerTrackingIfNeeded() {
        let needsTracking = environment.settings.advanced.displayTargeting == .activeDisplay
            && NSScreen.screens.count > 1

        guard needsTracking else { stopPointerTracking(); return }
        guard pointerMonitor == nil else { return }

        // A global monitor for mouse movement needs no Accessibility permission, unlike a
        // keyboard monitor, so this costs the user nothing.
        pointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.pointerMoved()
        }
    }

    private func stopPointerTracking() {
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        pointerMonitor = nil
        lastPointerDisplay = nil
    }

    private func pointerMoved() {
        guard let screen = NSScreen.underPointer else { return }
        let id = NotchGeometry.displayID(of: screen)
        guard id != lastPointerDisplay else { return }
        lastPointerDisplay = id

        guard let controller = controllers.values.first else { return }
        guard controller.viewModel.state == .collapsed else { return }

        controllers.removeValue(forKey: controller.displayID)
        controller.move(to: screen)
        controllers[id] = controller
    }

    // MARK: Commands

    /// Toggles the surface the user is most likely looking at.
    func toggleFrontmost() {
        guard let controller = preferredController() else { return }
        controller.viewModel.toggle()
    }

    /// Keeps the open panel open, on whichever display it is open on, or lets it go.
    ///
    /// The panel already stays on its display while it is open, even when the notch follows the
    /// pointer between displays; what closes it is the pointer leaving. So the target is the
    /// panel that is open, the one just clicked, and only with none open the one under the
    /// pointer, which opens. Pressed again, every kept panel is let go.
    func toggleKeepOpen() {
        let kept = controllers.values.filter { $0.viewModel.isKeptOpen }
        guard kept.isEmpty else {
            kept.forEach { $0.viewModel.setKeptOpen(false) }
            return
        }
        let open = controllers.values.first { $0.viewModel.state == .expanded }
        (open ?? preferredController())?.viewModel.setKeptOpen(true)
    }

    /// Opens the Notes tab ready to type into, on the panel that is open or the one under the
    /// pointer. The panel takes the keyboard here, because the shortcut that calls this is pressed
    /// with another app in front.
    func openNotes() {
        let open = controllers.values.first { $0.viewModel.state == .expanded }
        guard let controller = open ?? preferredController() else { return }
        controller.viewModel.selectedTab = .notes
        controller.viewModel.expand()
        controller.takeKeyboard()
    }

    func peekAll(duration: TimeInterval = 2.0) {
        controllers.values.forEach { $0.viewModel.peek(for: duration) }
    }

    func collapseAll() {
        controllers.values.forEach { $0.viewModel.collapse() }
    }

    /// Applies a swipe to whichever surface the pointer is over.
    ///
    /// Horizontal cycles tabs when open, and cycles Live Activities when closed, since that
    /// is the only thing there is to cycle in that state. Vertical opens and closes.
    func handleSwipe(_ direction: NotchGestureMonitor.Direction, environment: AppEnvironment) {
        guard let controller = preferredController() else { return }
        let viewModel = controller.viewModel

        switch direction {
        case .down:
            viewModel.expand()
        case .up:
            // Closed already: a swipe up puts away a download or connection notice.
            if viewModel.state == .expanded {
                viewModel.collapse()
            } else {
                environment.liveActivities.dismissCurrentNotice()
            }
        case .left, .right:
            let natural = direction == .right ? 1 : -1
            let offset = environment.settings.advanced.invertGestureDirection ? -natural : natural
            guard viewModel.state == .expanded else {
                environment.liveActivities.cycle(by: offset)
                return
            }
            // In the order the top bar shows them, which is the user's arrangement, not the
            // order features were registered in.
            let tabs = viewModel.topStripLayout(battery: environment.battery.status).tabsInOrder
            guard tabs.count > 1,
                  let index = tabs.firstIndex(of: viewModel.selectedTab) else { return }
            let next = (index + offset + tabs.count) % tabs.count
            // The new tab can be shorter, which takes the panel out from under the pointer as it
            // resizes; that read as the pointer leaving and closed it mid-swipe.
            viewModel.holdOpen(for: 0.8)
            viewModel.selectedTab = tabs[next]
        }
    }

    private func preferredController() -> NotchWindowController? {
        if let pointerScreen = NSScreen.underPointer,
           let match = controllers[NotchGeometry.displayID(of: pointerScreen)] {
            return match
        }
        return controllers.values.first
    }
}
