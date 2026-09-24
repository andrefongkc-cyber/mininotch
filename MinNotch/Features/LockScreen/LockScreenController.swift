import AppKit
import SwiftUI

/// What MinNotch shows over the lock screen: the volume and brightness HUD, and the song
/// playing with its controls.
///
/// While the screen is locked, a small window at the top of the built-in display draws the HUD
/// while there is a reading, and otherwise the song, as the sneak peek lays it out, with
/// previous, play or pause, and next. Each has its own switch: Settings > HUDs > Show on the Lock
/// Screen, and Settings > Media > Controls on the Lock Screen. The window exists only between lock
/// and unlock, can never become key, and lives in `LockScreenSpace`, the private window server
/// space drawn above the lock screen. Its own window rather than the notch's, so the private API
/// only ever touches a window that is thrown away on unlock and cannot strand the real notch in a
/// space it should not be in.
///
/// It takes clicks only while the song's controls are on screen. The HUD is only looked at, and a
/// window at the top of the lock screen that swallowed clicks for nothing would be a trap.
///
/// Nothing here changes what the HUD reacts to. Volume arrives from Core Audio whether or not the
/// screen is locked, so a key press that macOS handles itself still shows here.
@MainActor
final class LockScreenController {
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

    private var wantsHUD: Bool {
        guard let settings = environment?.settings, FeatureFlag.hud.isEnabled else { return false }
        let huds = settings.huds
        return huds.showOnLockScreen
            && (huds.replaceVolumeHUD || huds.replaceBrightnessHUD || huds.replaceKeyboardBacklightHUD)
    }

    private var wantsMedia: Bool {
        guard let settings = environment?.settings, FeatureFlag.nowPlaying.isEnabled else { return false }
        return settings.media.enabled && settings.media.showOnLockScreen
    }

    private func screenLocked() {
        guard panel == nil, wantsHUD || wantsMedia, isAvailable, let environment else { return }
        guard let screen = NSScreen.screens.first(where: \.isBuiltIn) ?? NSScreen.main else { return }

        let geometry = NotchGeometry.make(for: screen, settings: environment.settings)
        let size = LockScreenView.windowSize(for: geometry)
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
            rootView: LockScreenView(
                geometry: geometry,
                showsHUD: wantsHUD,
                showsMedia: wantsMedia,
                onInteractiveChange: { [weak panel] interactive in panel?.ignoresMouseEvents = !interactive }
            )
            .environment(environment)
            .environment(environment.settings)
        )
        panel.orderFrontRegardless()

        guard LockScreenSpace.shared.adopt(panel) else {
            AppLog.app.error("Could not move the lock screen window above the lock screen")
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
/// Clicks on its buttons still arrive, because a non-activating panel's controls work without
/// the window becoming key; that is how the notch itself works.
private final class LockScreenPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The HUD while there is a reading, else the song and its controls, else nothing.
struct LockScreenView: View {
    let geometry: NotchGeometry
    let showsHUD: Bool
    let showsMedia: Bool
    /// Told whenever the controls appear or go, so the window takes clicks only while they
    /// are there.
    var onInteractiveChange: (Bool) -> Void = { _ in }

    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings

    /// Big enough for the tallest HUD style and for the song strip.
    static func windowSize(for geometry: NotchGeometry) -> CGSize {
        let hudHeight = HUDStyle.allCases.map { HUDView.height(for: geometry, style: $0) }.max() ?? 80
        let media = SneakPeekView.size(for: geometry, pillWidth: geometry.collapsedSize.width)
        return CGSize(
            width: max(HUDView.width(for: geometry), media.width) + 16,
            height: max(hudHeight, media.height) + 8
        )
    }

    private var reading: HUDReading? { showsHUD ? environment.hud.current : nil }
    private var track: NowPlayingTrack? { showsMedia ? environment.nowPlaying.track : nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                if let reading {
                    surface(
                        width: HUDView.width(for: geometry),
                        height: HUDView.height(for: geometry, style: settings.huds.style),
                        bottomRadius: min(CGFloat(settings.appearance.panelCornerRadius), geometry.collapsedSize.height / 2)
                    ) {
                        HUDView(
                            reading: reading,
                            geometry: geometry,
                            style: settings.huds.style,
                            showsNumericValue: settings.huds.showNumericValue,
                            accent: settings.appearance.resolvedAccent
                        )
                    }
                    .transition(.opacity)
                } else if let track {
                    let size = SneakPeekView.size(for: geometry, pillWidth: geometry.collapsedSize.width)
                    surface(width: size.width, height: size.height, bottomRadius: SneakPeekView.cornerRadius) {
                        LockScreenMediaView(geometry: geometry, track: track)
                    }
                    .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .animation(.easeInOut(duration: 0.2), value: reading != nil)
        .animation(.easeInOut(duration: 0.2), value: track?.title)
        .onChange(of: reading == nil && track != nil, initial: true) { _, interactive in
            onInteractiveChange(interactive)
        }
    }

    /// The notch's black surface, clipped once, as `NotchRootView` draws it.
    private func surface<Content: View>(
        width: CGFloat, height: CGFloat, bottomRadius: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: .top) {
            Palette.notchFill
            content()
        }
        .frame(width: width, height: height)
        .clipShape(NotchShape(shoulderRadius: Metrics.notchShoulderRadius, bottomRadius: bottomRadius))
    }
}

/// The song under the camera housing, laid out as the sneak peek is, with its three controls.
private struct LockScreenMediaView: View {
    let geometry: NotchGeometry
    let track: NowPlayingTrack

    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        VStack(spacing: 0) {
            // The band behind the camera housing. Nothing readable goes there.
            Spacer(minLength: 0)
                .frame(height: geometry.collapsedSize.height)

            HStack(spacing: 10) {
                artwork

                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(track.artist.isEmpty ? track.sourceAppName : track.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    control("backward.fill", label: "Previous", .previousTrack)
                    control(track.isPlaying ? "pause.fill" : "play.fill", label: track.isPlaying ? "Pause" : "Play", .playPause)
                    control("forward.fill", label: "Next", .nextTrack)
                }
            }
            // Clear of the shoulder fillets, which are transparency rather than fill.
            .padding(.horizontal, CollapsedPillContent.contentInset + 6)
            .frame(height: SneakPeekView.bodyHeight)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now playing \(track.title) by \(track.artist)")
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = environment.nowPlaying.artwork {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.1))
                .frame(width: 30, height: 30)
        }
    }

    private func control(_ symbol: String, label: String, _ command: MediaCommand) -> some View {
        Button {
            environment.nowPlaying.send(command)
        } label: {
            TransportSymbol.image(symbol, pointSize: 13, weight: .semibold)
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
