import AppKit

/// Hook point for the first-launch flow.
///
/// The flow itself is not built yet, but where it goes and what it has to cover are
/// settled: Calendar access, Apple Events access for media control, and notification
/// permission, each explained before the system prompt appears rather than after. The
/// launch-time call site already exists in `AppEnvironment.start()`, so building the flow
/// is a matter of filling in `present()`.
final class OnboardingCoordinator {
    private static let completedKey = "onboarding.completedVersion"
    /// Bumped when onboarding gains a step existing users also need to see.
    private static let currentVersion = 1

    private unowned let environment: AppEnvironment
    private let defaults: UserDefaults

    init(environment: AppEnvironment, defaults: UserDefaults = .standard) {
        self.environment = environment
        self.defaults = defaults
    }

    var shouldPresentOnboarding: Bool {
        defaults.integer(forKey: Self.completedKey) < Self.currentVersion
    }

    /// Permissions the flow will explain, in the order it will ask for them.
    enum Step: CaseIterable {
        case welcome
        case calendarAccess
        case mediaControlAccess
        case notifications
        case shortcuts
        case done
    }

    func present() {
        // Until the flow exists, a first launch quietly asks for nothing and lets the user
        // grant permissions from the relevant settings pane instead. Nothing here should
        // prompt: an unexplained permission dialog on first launch is worse than none.
        AppLog.app.info("First launch detected; onboarding is not built yet")
        markCompleted()
    }

    func markCompleted() {
        defaults.set(Self.currentVersion, forKey: Self.completedKey)
    }

    /// Lets Settings > Advanced offer a "Show onboarding again" action once it exists.
    func reset() {
        defaults.removeObject(forKey: Self.completedKey)
    }
}
