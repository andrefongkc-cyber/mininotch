import AppKit
import Observation

/// Whether macOS is in dark mode, for a Notch Style set to Match System.
///
/// The notch panel draws in its style's colours whatever the system appearance is, so nothing
/// else follows the switch by itself. This watches the app's effective appearance, which follows
/// System Settings > Appearance, including Auto as the day changes.
@Observable
@MainActor
final class SystemAppearance {
    private(set) var isDark: Bool

    @ObservationIgnored private var observation: NSKeyValueObservation?

    init() {
        isDark = Self.read()
    }

    func start() {
        guard observation == nil else { return }
        // Delivered on the main thread, where appearance changes are made.
        observation = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let dark = Self.read()
                if dark != self.isDark { self.isDark = dark }
            }
        }
    }

    private static func read() -> Bool {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
