import AppKit
import Observation

/// Whether macOS is in dark mode, for a Notch Style set to Match System.
///
/// The notch panel draws in its style's colours whatever the system appearance is, so nothing
/// else follows the switch by itself. This watches the app's effective appearance, which follows
/// System Settings > Appearance, including Auto as the day changes.
///
/// Also the accessibility display options a style answers to: Reduce Transparency or Increase
/// Contrast (`prefersPlainSurfaces`) put the panel styles that ask for it back to Minimal, and Reduce Motion
/// stops Aurora drifting.
@Observable
@MainActor
final class SystemAppearance {
    private(set) var isDark: Bool
    private(set) var prefersPlainSurfaces: Bool
    private(set) var reducesMotion: Bool

    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private var accessibilityObserver: NSObjectProtocol?

    init() {
        isDark = Self.read()
        prefersPlainSurfaces = Self.readPrefersPlain()
        reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private static func readPrefersPlain() -> Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    func start() {
        if accessibilityObserver == nil {
            accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let plain = Self.readPrefersPlain()
                    if plain != self.prefersPlainSurfaces { self.prefersPlainSurfaces = plain }
                    let motion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                    if motion != self.reducesMotion { self.reducesMotion = motion }
                }
            }
        }
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
