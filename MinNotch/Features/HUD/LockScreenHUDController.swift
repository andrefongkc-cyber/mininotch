import AppKit
import SwiftUI

/// Shows the volume and brightness HUD over the lock screen.
///
/// Settings > HUDs > Show on the Lock Screen. While the screen is locked, a small window at the
/// top of the built-in display draws whatever `HUDCoordinator` is showing, the same HUD as the
/// notch, and nothing otherwise. It exists only between lock and unlock, ignores the mouse, can
/// never become key, and lives in `LockScreenSpace`, the private window server space that is
/// drawn above the lock screen. Its own window rather than the notch's, so the private API only
/// ever touches a window that is thrown away on unlock and cannot strand the real notch in a
/// space it should not be in.
///
/// Nothing here changes what the HUD reacts to. Volume arrives from Core Audio whether or not
/// the screen is locked, so a key press that macOS handles itself still shows here.
@MainActor
final class LockScreenHUDController {
    private weak var environment: AppEnvironment?
    private var panel: NSPanel?
    private var observers: [NSObjectProtocol] = []

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var isAvailable: Bool { LockScreenSpace.shared.isAvailable }

    func start() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenLocked() }
        })
        observers.append(center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenUnlocked() }
        })
    }

    func stop() {
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers.removeAll()
        screenUnlocked()
    }

    private var isWanted: Bool {
        guard let settings = environment?.settings, FeatureFlag.hud.isEnabled else { return false }
        let huds = settings.huds
        return huds.showOnLockScreen
            && (huds.replaceVolumeHUD || huds.replaceBrightnessHUD || huds.replaceKeyboardBacklightHUD)
    }

    private func screenLocked() {
        guard panel == nil, isWanted, isAvailable, let environment else { return }
        guard let screen = NSScreen.screens.first(where: \.isBuiltIn) ?? NSScreen.main else { return }

        let geometry = NotchGeometry.make(for: screen, settings: environment.settings)
        let height = HUDStyle.allCases.map { HUDView.height(for: geometry, style: $0) }.max() ?? 80
        let size = CGSize(width: HUDView.width(for: geometry) + 16, height: height + 8)
        let frame = CGRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )

        let panel = LockScreenPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(
            rootView: LockScreenHUDView(geometry: geometry)
                .environment(environment)
                .environment(environment.settings)
        )
        panel.orderFrontRegardless()

        guard LockScreenSpace.shared.adopt(panel) else {
            AppLog.app.error("Could not move the HUD window above the lock screen")
            panel.close()
            return
        }
        self.panel = panel
    }

    private func screenUnlocked() {
        panel?.close()
        panel = nil
    }
}

/// Never key, never main: nothing on the lock screen may take the keyboard from the password.
private final class LockScreenPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The HUD, drawn as the notch draws it, and nothing at all between readings.
private struct LockScreenHUDView: View {
    let geometry: NotchGeometry

    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                if let reading = environment.hud.current {
                    ZStack(alignment: .top) {
                        Palette.notchFill
                        HUDView(
                            reading: reading,
                            geometry: geometry,
                            style: settings.huds.style,
                            showsNumericValue: settings.huds.showNumericValue,
                            accent: settings.appearance.resolvedAccent
                        )
                    }
                    .frame(
                        width: HUDView.width(for: geometry),
                        height: HUDView.height(for: geometry, style: settings.huds.style)
                    )
                    .clipShape(NotchShape(
                        shoulderRadius: Metrics.notchShoulderRadius,
                        bottomRadius: min(CGFloat(settings.appearance.panelCornerRadius), geometry.collapsedSize.height / 2)
                    ))
                    .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .animation(.easeInOut(duration: 0.2), value: environment.hud.current != nil)
    }
}
