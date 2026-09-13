import Foundation

/// The entire user configuration in one `Codable` value.
///
/// This is the unit of export and import. Every section decodes leniently, so a file
/// written by an older or newer build loads with defaults filled in for anything it does
/// not recognise rather than failing outright.
struct SettingsSnapshot: Codable, Equatable {
    /// Bumped only for changes a lenient decode cannot absorb, e.g. a key whose meaning
    /// changed. `SettingsMigrator` handles those.
    static let currentSchemaVersion = 1

    var schemaVersion: Int = SettingsSnapshot.currentSchemaVersion
    var general = GeneralSettings()
    var appearance = AppearanceSettings()
    var media = MediaSettings()
    var calendar = CalendarSettings()
    var huds = HUDSettings()
    var battery = BatterySettings()
    var shelf = ShelfSettings()
    var timer = TimerSettings()
    var shortcuts = ShortcutSettings()
    var advanced = AdvancedSettings()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = c.value(.schemaVersion, SettingsSnapshot.currentSchemaVersion)
        general = c.value(.general, GeneralSettings())
        appearance = c.value(.appearance, AppearanceSettings())
        media = c.value(.media, MediaSettings())
        calendar = c.value(.calendar, CalendarSettings())
        huds = c.value(.huds, HUDSettings())
        battery = c.value(.battery, BatterySettings())
        shelf = c.value(.shelf, ShelfSettings())
        timer = c.value(.timer, TimerSettings())
        shortcuts = c.value(.shortcuts, ShortcutSettings())
        advanced = c.value(.advanced, AdvancedSettings())
    }
}

/// Applies any change a lenient decode cannot express.
///
/// Empty today. Kept so the call site in `SettingsStore.load()` already exists when the
/// first real migration is needed.
enum SettingsMigrator {
    static func migrate(_ snapshot: SettingsSnapshot) -> SettingsSnapshot {
        var result = snapshot
        // Example shape for a future migration:
        // if result.schemaVersion < 2 { ...; }
        result.schemaVersion = SettingsSnapshot.currentSchemaVersion
        return result
    }
}
