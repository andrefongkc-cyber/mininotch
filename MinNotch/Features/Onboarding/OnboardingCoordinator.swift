import AppKit
import SwiftUI

/// The first-launch tutorial: when it appears, and what finishing or skipping it does.
///
/// It asks for no permission on its own. The permissions page explains each one and offers an
/// "Allow Now" button, which is the one moment a prompt is welcome: the user has just read why,
/// and the tutorial window is frontmost, which an accessory app otherwise never is and a
/// system prompt needs.
///
/// Closing the window counts as skipping. A tutorial that reappears on every launch because
/// someone closed it with the red button instead of pressing Skip is the thing people most
/// dislike about tutorials.
final class OnboardingCoordinator: NSObject, NSWindowDelegate {
    private static let completedKey = "onboarding.completedVersion"
    /// Bumped when the tutorial gains something existing users also need to see.
    private static let currentVersion = 1

    private unowned let environment: AppEnvironment
    private let defaults: UserDefaults
    private var window: NSWindow?
    private var model: OnboardingModel?

    init(environment: AppEnvironment, defaults: UserDefaults = .standard) {
        self.environment = environment
        self.defaults = defaults
    }

    var shouldPresentOnboarding: Bool {
        defaults.integer(forKey: Self.completedKey) < Self.currentVersion
    }

    /// Shows the tutorial.
    ///
    /// A first run starts the checklist from the Recommended preset. A rerun, from Settings,
    /// starts it from whatever is switched on now, because offering to reset someone's
    /// configuration to a preset they never chose is not what "show me the welcome again" means.
    func present(isRerun: Bool = false) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let model: OnboardingModel
        if isRerun {
            let current = Set(OnboardingFeature.available.filter { $0.isOn(in: environment.settings) })
            model = OnboardingModel(
                selection: current,
                preset: OnboardingPreset.allCases.first { $0.features == current }
            )
        } else {
            model = OnboardingModel(selection: OnboardingPreset.recommended.features, preset: .recommended)
        }
        self.model = model

        let window = Self.makeWindow(
            model: model,
            environment: environment,
            onSkip: { [weak self] in self?.close() },
            onFinish: { [weak self] openSettings in
                self?.close()
                if openSettings { self?.environment.openSettings() }
            }
        )
        window.delegate = self
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// Builds the window without showing it. Shared with `--capture-onboarding`, so what gets
    /// captured is the window users see and not a lookalike assembled by the tool.
    static func makeWindow(
        model: OnboardingModel,
        environment: AppEnvironment,
        onSkip: @escaping () -> Void,
        onFinish: @escaping (Bool) -> Void
    ) -> NSWindow {
        let root = OnboardingView(model: model, onSkip: onSkip, onFinish: onFinish)
            .environment(environment)
            .environment(environment.settings)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: OnboardingView.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to MinNotch"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: root)
        window.setContentSize(OnboardingView.size)
        return window
    }

    private func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        markCompleted()
        environment.settings.flush()
        window = nil
        model = nil
    }

    func markCompleted() {
        defaults.set(Self.currentVersion, forKey: Self.completedKey)
    }

    func reset() {
        defaults.removeObject(forKey: Self.completedKey)
    }
}
