import Observation
import SwiftUI

/// The app's single source of truth for user configuration.
///
/// Sections are value types, so a SwiftUI binding into `store.media.showLyrics` mutates the
/// struct, which fires the section's `didSet` on this object, which both notifies observers
/// and schedules a debounced write. That keeps every section free of persistence code and
/// makes export/import a straight encode of `snapshot`.
@Observable
@MainActor
final class SettingsStore {
    static let defaultsKey = "settings.snapshot"

    var general = GeneralSettings() { didSet { didChange(oldValue != general) } }
    var appearance = AppearanceSettings() { didSet { didChange(oldValue != appearance) } }
    var media = MediaSettings() { didSet { didChange(oldValue != media) } }
    var calendar = CalendarSettings() { didSet { didChange(oldValue != calendar) } }
    var huds = HUDSettings() { didSet { didChange(oldValue != huds) } }
    var battery = BatterySettings() { didSet { didChange(oldValue != battery) } }
    var shelf = ShelfSettings() { didSet { didChange(oldValue != shelf) } }
    var timer = TimerSettings() { didSet { didChange(oldValue != timer) } }
    var shortcuts = ShortcutSettings() { didSet { didChange(oldValue != shortcuts) } }
    var advanced = AdvancedSettings() { didSet { didChange(oldValue != advanced) } }
    var weather = WeatherSettings() { didSet { didChange(oldValue != weather) } }

    /// Fired after a section actually changed value, on the main thread.
    /// `AppEnvironment` uses this to reconcile side effects such as login-item
    /// registration and hotkey re-binding.
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var pendingWrite: DispatchWorkItem?
    @ObservationIgnored private var isLoading = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// The visualizer and ambient glow switches, read and written as one cycling value.
    ///
    /// Lives here rather than on either section because the two switches it combines belong
    /// to different sections. Storing a third value would mean two sources of truth for the
    /// same two facts, so this is a projection, not state.
    var mediaEffectsMode: MediaEffectsMode {
        get {
            switch (media.showVisualizer, appearance.ambientGlow.isEnabled) {
            case (true, true): return .both
            case (true, false): return .visualizer
            case (false, true): return .ambient
            case (false, false): return .off
            }
        }
        set {
            media.showVisualizer = newValue.showsVisualizer
            appearance.ambientGlow.isEnabled = newValue.showsAmbient
        }
    }

    // MARK: Snapshot

    var snapshot: SettingsSnapshot {
        get {
            var snapshot = SettingsSnapshot()
            snapshot.general = general
            snapshot.appearance = appearance
            snapshot.media = media
            snapshot.calendar = calendar
            snapshot.huds = huds
            snapshot.battery = battery
            snapshot.shelf = shelf
            snapshot.timer = timer
            snapshot.shortcuts = shortcuts
            snapshot.advanced = advanced
            snapshot.weather = weather
            return snapshot
        }
        set { apply(newValue) }
    }

    private func apply(_ snapshot: SettingsSnapshot) {
        general = snapshot.general
        appearance = snapshot.appearance
        media = snapshot.media
        calendar = snapshot.calendar
        huds = snapshot.huds
        battery = snapshot.battery
        shelf = snapshot.shelf
        timer = snapshot.timer
        shortcuts = snapshot.shortcuts
        advanced = snapshot.advanced
        weather = snapshot.weather
    }

    // MARK: Persistence

    private func load() {
        isLoading = true
        defer { isLoading = false }

        guard let data = defaults.data(forKey: Self.defaultsKey) else { return }
        do {
            let decoded = try SettingsCoding.decoder.decode(SettingsSnapshot.self, from: data)
            apply(SettingsMigrator.migrate(decoded))
        } catch {
            AppLog.settings.error("Settings failed to load, falling back to defaults: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func didChange(_ changed: Bool) {
        guard changed, !isLoading else { return }
        scheduleWrite()
        onChange?()
    }

    /// Debounced so dragging a slider does not write to disk on every frame.
    private func scheduleWrite() {
        pendingWrite?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.writeNow() }
        pendingWrite = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// Forces an immediate write. Called on quit so nothing is lost to the debounce.
    func flush() {
        pendingWrite?.cancel()
        pendingWrite = nil
        writeNow()
    }

    private func writeNow() {
        do {
            let data = try SettingsCoding.encoder.encode(snapshot)
            defaults.set(data, forKey: Self.defaultsKey)
        } catch {
            AppLog.settings.error("Settings failed to save: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Export / import

    func exportData() throws -> Data {
        try SettingsCoding.encoder.encode(snapshot)
    }

    func importData(_ data: Data) throws {
        let decoded = try SettingsCoding.decoder.decode(SettingsSnapshot.self, from: data)
        snapshot = SettingsMigrator.migrate(decoded)
        flush()
    }

    func resetToDefaults() {
        snapshot = SettingsSnapshot()
        flush()
    }

    /// Suggested filename for an export.
    var exportFilename: String {
        let stamp = ISO8601DateFormatter().string(from: Date()).prefix(10)
        return "MinNotch Settings \(stamp).minnotch"
    }
}
