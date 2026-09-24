import AppKit
import SwiftUI
import Observation

/// Composition root. Owns every long-lived service and wires the side effects between them.
///
/// Views reach it through `@Environment(AppEnvironment.self)`. Services never talk to each
/// other directly: the battery service raises a callback, this type decides that a
/// notification should be posted, and settings changes fan out from one place. That keeps
/// each feature testable on its own and gives V2 features an obvious place to plug in.
@Observable
@MainActor
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
    let audioOutputs = AudioOutputService()

    @ObservationIgnored private let gestures = NotchGestureMonitor()
    let liveActivities = LiveActivityCenter()
    let downloads = DownloadsMonitor()

    /// When the last tap of a tapped tempo landed, in reference-date seconds, so the glow's beats
    /// fall on the taps. Not saved: a phase from an earlier session lines up with nothing.
    var tappedBeatOrigin: TimeInterval?
    let clipboard = ClipboardHistoryService()
    let linkShelf = LinkShelfService()
    let timer = TimerService()

    @ObservationIgnored private(set) lazy var notchWindows = NotchWindowManager(environment: self)
    @ObservationIgnored private(set) lazy var floatingNowPlaying = FloatingNowPlayingController(environment: self)
    @ObservationIgnored private(set) lazy var menuBar = MenuBarController(environment: self)
    @ObservationIgnored private(set) lazy var settingsWindow = SettingsWindowController(environment: self)
    @ObservationIgnored private(set) lazy var onboarding = OnboardingCoordinator(environment: self)
    @ObservationIgnored private(set) lazy var whatsNew = WhatsNewCoordinator()
    @ObservationIgnored private(set) lazy var lockScreenHUD = LockScreenHUDController(environment: self)

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
        // Only listens for the screen locking; the window exists between lock and unlock.
        lockScreenHUD.start()
        applyAudioAnalysisSetting()

        downloads.onChange = { [weak self] items in self?.syncDownloadActivities(items) }
        bluetooth.onDeviceConnected = { [weak self] devices in self?.announceConnected(devices) }
        applyActivitySources()

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
        lockScreenHUD.stop()
        meetingTimer?.invalidate()
        meetingTimer = nil
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
        applyActivitySources()
    }

    /// The tempo the glow's own pulse should keep, or nil for the Speed slider's.
    ///
    /// Only used while the glow is not following the audio: live analysis has the real beat. A
    /// song's tempo is laid on the song's own position, so its beats move with a seek and stay
    /// put across a pause, rather than drifting against the music.
    func glowTempo(at date: Date = Date()) -> GlowTempo? {
        let glow = settings.appearance.ambientGlow
        switch glow.tempoSource {
        case .speed:
            return nil
        case .manual:
            return GlowTempo(beatsPerMinute: glow.manualBPM, origin: tappedBeatOrigin ?? 0)
        case .song:
            guard let bpm = nowPlaying.track?.beatsPerMinute else { return nil }
            return GlowTempo(
                beatsPerMinute: bpm,
                origin: date.timeIntervalSinceReferenceDate - nowPlaying.elapsed(at: date)
            )
        }
    }

    /// Starts or stops the two notice sources to match the settings. Neither runs unless it is
    /// wanted: the folder watch holds a descriptor open, the registry watch a notification port.
    private func applyActivitySources() {
        let activitiesOn = FeatureFlag.liveActivities.isEnabled
        if activitiesOn, settings.general.showDownloadActivity {
            downloads.start()
        } else {
            downloads.stop()
        }
        if activitiesOn, settings.general.announceConnectedDevices {
            bluetooth.startWatchingConnections()
        } else {
            bluetooth.stopWatchingConnections()
        }
        applyMeetingCountdown()
    }

    // MARK: Meeting countdown

    @ObservationIgnored private var meetingTimer: Timer?

    private var wantsMeetingCountdown: Bool {
        FeatureFlag.liveActivities.isEnabled
            && settings.calendar.enabled
            && settings.calendar.showMeetingCountdown
    }

    /// Starts or stops the countdown's clock. A quarter-minute tick keeps "5m" honest, and costs
    /// a scan of a few dozen events. It runs whenever the countdown is switched on, not only once
    /// the calendar can be read: access is granted from a dialog, with no settings change to
    /// start a clock that was gated on it, so each tick checks for itself.
    private func applyMeetingCountdown() {
        if wantsMeetingCountdown {
            if meetingTimer == nil {
                meetingTimer = Timer.onMain(every: 15) { [weak self] in self?.syncMeetingActivity() }
            }
        } else {
            meetingTimer?.invalidate()
            meetingTimer = nil
        }
        syncMeetingActivity()
    }

    /// Shows the next meeting in the pill from `meetingLeadMinutes` before it until five
    /// minutes after it starts, which is how late people join.
    ///
    /// Internal rather than private so `--capture-notch --sample-calendar` can drive it with the
    /// sample events, the way `--timer` drives the timer's activity.
    func syncMeetingActivity(now: Date = Date()) {
        let lead = settings.calendar.meetingLeadMinutes * 60
        let meeting = wantsMeetingCountdown && calendarService.hasAccess
            ? calendarService.items.first { item in
                !item.isAllDay && !item.isReminder
                    && item.start > now.addingTimeInterval(-300)
                    && item.start <= now.addingTimeInterval(lead)
            }
            : nil
        let id = meeting.map { "meeting|" + $0.id }

        for activity in liveActivities.activities where activity.kind == .meeting && activity.id != id {
            liveActivities.dismiss(id: activity.id)
        }
        guard let meeting, let id, !liveActivities.putAway.contains(id) else { return }

        let minutes = Int((meeting.start.timeIntervalSince(now) / 60).rounded(.up))
        liveActivities.present(LiveActivity(
            id: id,
            kind: .meeting,
            symbolName: meeting.joinURL == nil ? "calendar" : "video.fill",
            title: meeting.title,
            detail: minutes <= 0 ? "Now" : "\(minutes)m",
            tint: meeting.color,
            expiresAt: meeting.start.addingTimeInterval(300),
            priority: 55
        ))
    }

    /// One activity per download, showing its progress, then a tick for a few seconds.
    private func syncDownloadActivities(_ items: [DownloadItem]) {
        let current = Set(items.map { "download|" + $0.id })
        for activity in liveActivities.activities where activity.kind == .download && !current.contains(activity.id) {
            liveActivities.dismiss(id: activity.id)
        }

        for item in items {
            let id = "download|" + item.id
            if item.isFinished {
                // Present the tick once, and let it expire on its own; re-presenting it on every
                // change would keep pushing its expiry back.
                guard liveActivities.activities.first(where: { $0.id == id })?.progress != 1 else { continue }
                liveActivities.present(LiveActivity(
                    id: id,
                    kind: .download,
                    symbolName: "checkmark.circle.fill",
                    title: item.name,
                    detail: "Done",
                    progress: 1,
                    tint: Color(nsColor: .systemGreen),
                    expiresAt: Date().addingTimeInterval(5),
                    priority: 40
                ))
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) { [weak self] in
                    self?.downloads.forget(item.id)
                }
            } else {
                liveActivities.present(LiveActivity(
                    id: id,
                    kind: .download,
                    symbolName: "arrow.down.circle",
                    title: item.name,
                    detail: item.fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "…",
                    progress: item.fraction,
                    tint: settings.appearance.resolvedAccent,
                    priority: 40
                ))
            }
        }
    }

    /// A few seconds of an accessory's charge when it connects. Earbuds arrive as a left, a
    /// right and a case, and are shown as one device at the lower of the two buds, since that
    /// is the one that runs out.
    private func announceConnected(_ devices: [BluetoothDevice]) {
        let grouped = Dictionary(grouping: devices, by: \.baseName)
        for (name, parts) in grouped {
            let buds = parts.filter { !$0.name.hasSuffix(" (Case)") }
            let level = (buds.isEmpty ? parts : buds).map(\.percentage).min() ?? 0
            let symbol = parts.first?.symbolName ?? "wave.3.right.circle"
            liveActivities.present(LiveActivity(
                id: "device|" + name,
                kind: .bluetoothDevice,
                symbolName: symbol,
                title: name,
                detail: "\(level)%",
                progress: Double(level) / 100,
                tint: level <= 20 ? Color(nsColor: .systemRed) : .white,
                expiresAt: Date().addingTimeInterval(6),
                priority: 50
            ))
        }
    }

    /// Asks for the system audio permission by itself, from the tutorial.
    ///
    /// Starting the tap is what raises the prompt, from the foreground. Once it is running the
    /// tutorial calls `reconcileAudioAnalysis()`, which leaves it running only if a setting
    /// wants it, so allowing the permission early costs nothing until something uses it.
    func requestSystemAudioAccess() {
        audioAnalyzer.retry()
    }

    /// Puts the audio tap back to whatever the settings want.
    func reconcileAudioAnalysis() {
        applyAudioAnalysisSetting()
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

        // The song is not a live activity. It used to be presented as one, which put the
        // artist in the Live Activity slot with no way to choose the title instead, and it was
        // never taken down again, so the pill went on naming an artist after the player had
        // quit. The pill's Song indicator reads the track directly.

        // Only for a track that is actually playing. A paused track loading when a player
        // opens is not news, and peeking for it announces a song nobody is hearing.
        guard FeatureFlag.liveActivities.isEnabled,
              settings.media.sneakPeekOnTrackChange,
              track.isPlaying else { return }
        notchWindows.peekAll(duration: settings.media.sneakPeekDuration)
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
