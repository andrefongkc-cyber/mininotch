import AppKit
import LocalAuthentication

/// Asks whoever is at the Mac to prove they are its owner: Touch ID, else the login password, or
/// an Apple Watch where one is set up to unlock this Mac. The dialog is the system's own.
///
/// Public API with no permission, entitlement or usage description. The dialog is shown to the
/// active app, and MiniNotch's panel never makes it active, so this brings the app forward first,
/// which an accessory app can do without a Dock icon.
@MainActor
enum OwnerCheck {
    enum Outcome: Equatable {
        case confirmed
        /// Cancelled, or a wrong finger or password too many times. Nothing to say about it.
        case declined
        /// This Mac cannot be asked at all, with the reason macOS gave.
        case unavailable(String)
    }

    /// `reason` finishes the sentence "MiniNotch is trying to …" in the dialog.
    static func confirm(reason: String) async -> Outcome {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            let message = error?.localizedDescription ?? "macOS gave no reason"
            AppLog.app.error("Owner check unavailable: \(message, privacy: .public)")
            return .unavailable(message)
        }

        NSApp.activate(ignoringOtherApps: true)
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) ? .confirmed : .declined
        } catch {
            AppLog.app.info("Owner check declined: \(error.localizedDescription, privacy: .public)")
            return .declined
        }
    }

    /// What this Mac would ask with, without asking. For `--check-permissions`.
    static var method: String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return "unavailable (\(error?.localizedDescription ?? "no reason"))"
        }
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType == .touchID ? "Touch ID, or the login password" : "the login password"
    }
}
