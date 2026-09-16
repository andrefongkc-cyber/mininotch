import Observation
import SwiftUI

/// Drives the replacement volume, brightness, and keyboard backlight indicators.
///
/// Volume is event driven through CoreAudio. Brightness and keyboard backlight have no
/// change notification, so they are polled, but only while their toggle is on and only at a
/// rate fast enough to feel immediate when a key is held down.
///
/// A reading is only shown when the value actually changes. Without that, the first poll
/// after enabling the feature would put a HUD on screen that the user did not ask for.
@Observable
final class HUDCoordinator {
    /// The reading currently on screen, or nil when nothing is showing.
    private(set) var current: HUDReading?

    /// True when this Mac's keyboard reports a backlight level at all.
    var isKeyboardBacklightSupported: Bool { brightness.isKeyboardBacklightSupported }
    /// True when display brightness can be read on this macOS version.
    var isBrightnessSupported: Bool { brightness.isBrightnessSupported }

    /// True while hiding Apple's overlay is switched on but MinNotch is not in the Accessibility
    /// list, so the keys still go to macOS. Settings shows it with a way to fix it.
    private(set) var needsAccessibility = false

    @ObservationIgnored private let volume = VolumeMonitor()
    @ObservationIgnored private let brightness = BrightnessMonitor()
    @ObservationIgnored private let keys = SystemKeyInterceptor()
    @ObservationIgnored private var trustTimer: Timer?

    @ObservationIgnored private var settings: SettingsStore?
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var dismissWork: DispatchWorkItem?

    @ObservationIgnored private var lastVolume: Double?
    @ObservationIgnored private var lastMuted: Bool?
    @ObservationIgnored private var lastBrightness: Double?
    @ObservationIgnored private var lastKeyboard: Double?

    init() {}

    func start(settings: SettingsStore) {
        self.settings = settings

        volume.onChange = { [weak self] level, muted in
            self?.handleVolume(level, muted: muted)
        }
        keys.wantsKey = { [weak self] key in
            self?.takesKey(key) ?? false
        }
        keys.perform = { [weak self] press in
            self?.perform(press) ?? false
        }

        Self.resumeOverlayHelperLeftSuspended()
        applySettings()
    }

    /// Earlier versions hid the overlay by suspending `OSDUIHelper` and resumed it on quit. A
    /// Mac that ran one of those and then crashed, or updated while it was suspended, still has
    /// it suspended, so every launch sends the resume. Harmless when nothing is suspended.
    private static func resumeOverlayHelperLeftSuspended() {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            process.arguments = ["-CONT", "-x", "OSDUIHelper"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }

    // MARK: Taking the keys

    /// Whether any key needs taking: the setting is on and at least one indicator it can stand
    /// in for is on. Keyboard backlight is not one, because its keys are never taken.
    private var wantsKeyInterception: Bool {
        guard let settings, settings.huds.suppressSystemOverlay else { return false }
        return settings.huds.replaceVolumeHUD || settings.huds.replaceBrightnessHUD
    }

    private func takesKey(_ key: SystemKeyInterceptor.Key) -> Bool {
        guard let settings, settings.huds.suppressSystemOverlay else { return false }
        return key.isVolume ? settings.huds.replaceVolumeHUD : settings.huds.replaceBrightnessHUD
    }

    /// Carries out a key MinNotch took, and shows the result at once rather than waiting for
    /// the listener or the next brightness poll. Pressing up at full volume still shows the
    /// indicator, as macOS's own overlay does.
    private func perform(_ press: SystemKeyInterceptor.Press) -> Bool {
        if press.key.isVolume {
            guard let result = volume.apply(press.key, fineStep: press.isFineStep) else { return false }
            lastVolume = result.level
            lastMuted = result.muted
            present(HUDReading(kind: .volume, value: result.level, isMuted: result.muted))
        } else {
            guard let level = brightness.apply(press.key, fineStep: press.isFineStep) else { return false }
            lastBrightness = level
            present(HUDReading(kind: .brightness, value: level))
        }
        return true
    }

    private func applyKeyInterception() {
        guard wantsKeyInterception else {
            keys.stop()
            stopWaitingForTrust()
            needsAccessibility = false
            return
        }
        guard !keys.isRunning else { return }

        if keys.start() {
            stopWaitingForTrust()
            needsAccessibility = false
        } else {
            needsAccessibility = true
            waitForTrust()
        }
    }

    /// Accessibility access is granted in System Settings with no callback, so while it is
    /// wanted and missing, check every couple of seconds and start as soon as it arrives.
    private func waitForTrust() {
        guard trustTimer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard SystemKeyInterceptor.isTrusted else { return }
            self?.stopWaitingForTrust()
            self?.applyKeyInterception()
        }
        RunLoop.main.add(timer, forMode: .common)
        trustTimer = timer
    }

    private func stopWaitingForTrust() {
        trustTimer?.invalidate()
        trustTimer = nil
    }

    /// Asks macOS for Accessibility access. Called when the user switches the setting on, or
    /// presses the button beside the warning, never at launch.
    func requestAccessibility() {
        SystemKeyInterceptor.requestTrust()
        applyKeyInterception()
    }

    func stop() {
        keys.stop()
        stopWaitingForTrust()
        volume.stop()
        pollTimer?.invalidate()
        pollTimer = nil
        dismissWork?.cancel()
        current = nil
    }

    /// Starts and stops the monitors to match the toggles.
    func applySettings() {
        guard let settings, FeatureFlag.hud.isEnabled else {
            stop()
            needsAccessibility = false
            return
        }

        // Keys are taken only while MinNotch shows an indicator in their place. Hiding the
        // system's overlay with nothing drawn instead would leave volume changes silent.
        applyKeyInterception()

        if settings.huds.replaceVolumeHUD {
            volume.start()
            // Seed the baseline so enabling the feature does not immediately show a HUD.
            if lastVolume == nil, let reading = volume.read() {
                lastVolume = reading.0
                lastMuted = reading.1
            }
        } else {
            volume.stop()
            lastVolume = nil
        }

        let needsPolling = settings.huds.replaceBrightnessHUD || settings.huds.replaceKeyboardBacklightHUD
        needsPolling ? startPolling() : stopPolling()
    }

    // MARK: Polling

    private func startPolling() {
        guard pollTimer == nil else { return }

        lastBrightness = brightness.readBrightness()
        lastKeyboard = brightness.readKeyboardBacklight()

        // Fast enough that holding a brightness key looks continuous, slow enough that it is
        // two float reads a second rather than a spin.
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        lastBrightness = nil
        lastKeyboard = nil
    }

    private func poll() {
        guard let settings else { return }

        if settings.huds.replaceBrightnessHUD, let level = brightness.readBrightness() {
            if let previous = lastBrightness, abs(previous - level) > 0.005 {
                present(HUDReading(kind: .brightness, value: level))
            }
            lastBrightness = level
        }

        if settings.huds.replaceKeyboardBacklightHUD, let level = brightness.readKeyboardBacklight() {
            if let previous = lastKeyboard, abs(previous - level) > 0.005 {
                present(HUDReading(kind: .keyboardBacklight, value: level))
            }
            lastKeyboard = level
        }
    }

    private func handleVolume(_ level: Double, muted: Bool) {
        guard let settings, settings.huds.replaceVolumeHUD else { return }

        let changed = lastVolume.map { abs($0 - level) > 0.005 } ?? false
        let muteChanged = lastMuted.map { $0 != muted } ?? false
        lastVolume = level
        lastMuted = muted

        guard changed || muteChanged else { return }
        present(HUDReading(kind: .volume, value: level, isMuted: muted))
    }

    // MARK: Presentation

    private func present(_ reading: HUDReading) {
        current = reading

        dismissWork?.cancel()
        let delay = max(0.5, settings?.huds.dismissDelay ?? 1.5)
        let work = DispatchWorkItem { [weak self] in self?.current = nil }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Shows a reading immediately, used by the Settings pane's preview button so the user
    /// can see what a style looks like without hunting for a volume key.
    func preview(_ kind: HUDReading.Kind) {
        let value: Double
        switch kind {
        case .volume: value = volume.read()?.0 ?? 0.6
        case .brightness: value = brightness.readBrightness() ?? 0.6
        case .keyboardBacklight: value = brightness.readKeyboardBacklight() ?? 0.6
        }
        present(HUDReading(kind: kind, value: value))
    }
}
