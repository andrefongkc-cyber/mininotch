import OSLog

/// Subsystem-scoped loggers. Using distinct categories keeps `log stream` usable when
/// debugging a single subsystem, e.g. window placement across displays.
enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.minnotch.MinNotch"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let notch = Logger(subsystem: subsystem, category: "notch")
    static let media = Logger(subsystem: subsystem, category: "media")
    static let calendar = Logger(subsystem: subsystem, category: "calendar")
    static let battery = Logger(subsystem: subsystem, category: "battery")
    static let hotkeys = Logger(subsystem: subsystem, category: "hotkeys")
    static let settings = Logger(subsystem: subsystem, category: "settings")
}
