import AppKit
import Observation

/// Composition root. Owns every long-lived service and wires the side effects between them.
///
/// Views reach it through `@Environment(AppEnvironment.self)`. Services never talk to each
/// other directly: the battery service raises a callback, this type decides that a
/// notification should be posted, and settings changes fan out from one place. That keeps
/// each feature testable on its own and gives V2 features an obvious place to plug in.
@Observable
final class AppEnvironment {
    let settings: SettingsStore
    let nowPlaying = NowPlayingController()
    let calendarService = CalendarService()
    let battery = BatteryService()
    let systemStats = SystemStatsService()
    let bluetooth = BluetoothBatteryService()
    let shelf = ShelfService()
    let hud = HUDCoordinator()
    let audioAnalyzer = AudioAnalyzer()

    @ObservationIgnored private let gestures = NotchGestureMonitor()
    let liveActivities = LiveActivityCenter()
    let clipboard = ClipboardHistoryService()
    let linkShelf = LinkShelfService()
    let timer = TimerService()

    @ObservationIgnored private(set) lazy var notchWindows = NotchWindowManager(environment: self)
    @ObservationIgnored private(set) lazy var floatingNowPlaying = FloatingNowPlayingController(environment: self)
    @ObservationIgnored private(set) lazy var menuBar = MenuBarController(environment: self)
    @ObservationIgnored private(set) lazy var settingsWindow = SettingsWindowController(environment: self)
    @ObservationIgnored private(set) lazy var onboarding = OnboardingCoordinator(environment: self)
    @ObservationIgnored private(set) lazy var whatsNew = WhatsNewCoordinator()

    init(settings: SettingsStore = SettingsStore()) {
        self.settings = settings
    }

    // MARK: Lifecycle

    func start() {
        LaunchAtLogin.reconcile(settings)

        settings.onChange = { [weak self] in self?.settingsChanged() }

        battery.onLowBattery = { [weak self] percentage in
            self?.postLowBatteryNotification(percentage)
        }
        battery.onPowerSourceChange = { [weak self] isPluggedIn in
            self?.postPowerSourceNotification(isPluggedIn)
        }
        nowPlaying.audioLatencyProvider = { [weak self] in
            guard let self, self.audioAnalyzer.isRunning else { return nil }
            return self.audioAnalyzer.outputLatency
        }
        // The tap hears a voice come in; the controller knows where the track was at that
        // moment. Neither knows about the other, so the wiring lives here.
        audioAnalyzer.onVocalOnset = { [weak self] date, strength in
            self?.nowPlaying.noteAudioOnset(at: date, strength: strength)
        }
        nowPlaying.onTrackChange = { [weak self] track in
            self?.trackChanged(track)
        }
        // The timer service raises these and knows nothing about either the pill or
        // notifications, the same way the battery service raises `onLowBattery`.
        timer.onChange = { [weak self] in
            self?.syncTimerActivity()
        }
        timer.onCompletion = { [weak self] phase in
            self?.postTimerNotification(for: phase)
        }

        HotkeyManager.shared.onAction = { [weak self] action in
            self?.perform(action)
        }
        HotkeyManager.shared.apply(settings.shortcuts)

        battery.start(settings: settings)
        systemStats.start(settings: settings)
        bluetooth.start(settings: settings)
        shelf.start(settings: settings)
        hud.start(settings: settings)
        applyAudioAnalysisSetting()

        gestures.onSwipe = { [weak self] direction in
            guard let self else { return }
            self.notchWindows.handleSwipe(direction, environment: self)
            Haptics.perform(enabled: self.settings.advanced.hapticFeedbackEnabled, strength: self.settings.advanced.hapticStrength)
        }
        gestures.start(settings: settings)
        calendarService.start(settings: settings)
        nowPlaying.start(settings: settings)
        clipboard.start(settings: settings)
        linkShelf.start(settings: settings)
        timer.start(settings: settings)

        notchWindows.start()
        // Opens only if the setting is on; the same call closes it when it is not.
        floatingNowPlaying.settingsChanged()
        menuBar.update()

        if onboarding.shouldPresentOnboarding {
            // After the notch is on screen rather than during launch, so the first thing
            // someone sees is the window pointing at a notch that already exists.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.onboarding.present()
            }
            // A first launch has nothing to compare against, so this release counts as seen.
            whatsNew.markSeen()
        } else if whatsNew.shouldPresent {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.whatsNew.present()
            }
        }
    }

    func stop() {
        nowPlaying.stop()
        calendarService.stop()
        clipboard.stop()
        linkShelf.stop()
        timer.stop()
        battery.stop()
        shelf.stop()
        // Also removes the key tap, so the volume and brightness keys go straight back to macOS.
        hud.stop()
        audioAnalyzer.stop()
        notchWindows.stop()
        floatingNowPlaying.hide()
        gestures.stop()
        settings.flush()
    }

    // MARK: Settings fan-out

    /// Reconciles every side effect of a settings change.
    ///
    /// Deliberately coarse: settings changes are rare and human-paced, so re-applying all
    /// of them is simpler and less bug-prone than tracking which key changed.
    private func settingsChanged() {
        LaunchAtLogin.reconcile(settings)
        HotkeyManager.shared.apply(settings.shortcuts)
        menuBar.update()
        notchWindows.settingsChanged()
        floatingNowPlaying.settingsChanged()
        nowPlaying.settingsChanged()
        systemStats.settingsChanged()
        bluetooth.refresh()
        shelf.settingsChanged()
        clipboard.settingsChanged()
        linkShelf.settingsChanged()
        hud.applySettings()
        applyAudioAnalysisSetting()
        gestures.applySettings()
        calendarService.refresh()
        battery.refresh()
    }

    /// Starts or stops the audio tap to match the settings.
    ///
    /// The tap is the one part of the glow that costs anything real and needs a permission, so
    /// it runs only when something actually wants it: the glow following the beat, or the lyric
    /// strip matching itself to the audio.
    private func applyAudioAnalysisSetting() {
        let glow = settings.appearance.ambientGlow
        let glowWantsAudio = glow.isActive(isLowPower: battery.status.isLowPowerMode) && glow.isAudioReactive
        let lyricsWantAudio = settings.media.enabled
            && settings.media.showLyrics
            && settings.media.matchLyricsToAudio
            && FeatureFlag.lyrics.isEnabled
        let wanted = glowWantsAudio || lyricsWantAudio

        if wanted {
            // `start()` refuses to run again after a failure, so a refused permission cannot
            // turn into a prompt on every settings change.
            audioAnalyzer.start()
        } else {
            // Stopping also clears the recorded failure, which makes switching the setting
            // off and on the natural way to ask again.
            audioAnalyzer.stop()
        }
    }

    // MARK: Actions

    func perform(_ action: HotkeyAction) {
        guard action.isAvailable else { return }

        switch action {
        case .toggleNotch:
            notchWindows.toggleFrontmost()
        case .openSettings:
            openSettings()
        case .playPause:
            nowPlaying.send(.playPause)
        case .nextTrack:
            nowPlaying.send(.nextTrack)
        case .previousTrack:
            nowPlaying.send(.previousTrack)
        case .toggleShelf, .quickNote, .startTimer:
            // Handled once the matching feature lands; the binding is already recordable.
            AppLog.app.debug("Action \(action.rawValue, privacy: .public) is not implemented yet")
        }
    }

    func openSettings() {
        settingsWindow.show()
    }

    func quit() {
        stop()
        NSApp.terminate(nil)
    }

    // MARK: Cross-service reactions

    private func trackChanged(_ track: NowPlayingTrack) {
        guard settings.media.enabled else { return }

        liveActivities.present(
            LiveActivity(
                id: "media.current",
                kind: .media,
                symbolName: "music.note",
                title: track.title,
                detail: track.artist.isEmpty ? nil : track.artist,
                tint: nowPlaying.palette.primary,
                priority: 10
            )
        )

        // Only for a track that is actually playing. A paused track loading when a player
        // opens is not news, and peeking for it announces a song nobody is hearing.
        guard FeatureFlag.liveActivities.isEnabled,
              settings.media.sneakPeekOnTrackChange,
              track.isPlaying else { return }
        notchWindows.peekAll(duration: 2.6)
    }

    /// Mirrors the timer into the pill, so a countdown is visible with the notch closed.
    ///
    /// The service raises `onChange` on every tick and this decides what, if anything, that
    /// means for the surface. An idle timer removes its activity rather than presenting an
    /// empty one, which is what keeps the pill clear when nothing is running.
    /// Internal rather than private so `--capture-notch --timer` can drive the real path
    /// instead of pushing a stand-in activity that proves nothing.
    func syncTimerActivity() {
        guard FeatureFlag.liveActivities.isEnabled, settings.timer.enabled, timer.isActive else {
            liveActivities.dismiss(id: Self.timerActivityID)
            return
        }

        liveActivities.present(
            LiveActivity(
                id: Self.timerActivityID,
                kind: .timer,
                symbolName: timer.phase.symbolName,
                title: timer.phase.title,
                detail: timer.state == .finished ? "Done" : timer.remainingText,
                progress: timer.progress,
                tint: timer.phase.tint,
                // No expiry: the service ends this activity itself when the timer is reset,
                // and an expiry would let the pill clear while the timer was still running.
                expiresAt: nil,
                priority: 60
            )
        )
    }

    private static let timerActivityID = "timer.current"

    private func postTimerNotification(for phase: TimerPhase) {
        guard settings.timer.notifyOnCompletion else { return }

        let body: String
        switch phase {
        case .countdown: body = "Your countdown has finished."
        case .work: body = "Time for a break."
        case .shortBreak, .longBreak: body = "Break over. Back to it."
        }

        NotificationCenterBridge.post(
            identifier: "timer.completed",
            title: "\(phase.title) Finished",
            body: body,
            sound: true
        )
    }

    private func postLowBatteryNotification(_ percentage: Int) {
        NotificationCenterBridge.post(
            identifier: "battery.low",
            title: "Low Battery",
            body: "\(percentage)% remaining. Connect a power adapter.",
            sound: true
        )
    }

    private func postPowerSourceNotification(_ isPluggedIn: Bool) {
        NotificationCenterBridge.post(
            identifier: "battery.source",
            title: isPluggedIn ? "Power Adapter Connected" : "Running on Battery",
            body: isPluggedIn
                ? "Your Mac is charging."
                : "\(battery.status.percentage)% remaining."
        )
    }
}
