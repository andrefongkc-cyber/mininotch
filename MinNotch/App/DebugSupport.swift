#if DEBUG
import Foundation

/// Shared setup for the command line debug tools.
///
/// Every one of them builds an `AppEnvironment`, and several deliberately change settings so
/// they can render a feature that is off by default. Those stores write through to
/// `UserDefaults`, so running a preview used to overwrite the user's real configuration as a
/// side effect of looking at it. A throwaway suite, seeded from the real one, means the tools
/// see the user's actual settings and can change whatever they like without any of it
/// surviving the process.
@MainActor
enum DebugSupport {
    private static let suiteName = "com.minnotch.debug-tools"

    static func makeEnvironment() -> AppEnvironment {
        AppEnvironment(settings: SettingsStore(defaults: scratchDefaults()))
    }

    private static func scratchDefaults() -> UserDefaults {
        guard let suite = UserDefaults(suiteName: suiteName) else { return .standard }

        // Start from empty every run, so one tool cannot leak state into the next.
        suite.removePersistentDomain(forName: suiteName)

        // Seed from the real settings so captures reflect what the user actually sees.
        if let data = UserDefaults.standard.data(forKey: SettingsStore.defaultsKey) {
            suite.set(data, forKey: SettingsStore.defaultsKey)
        }
        return suite
    }
}
#endif
