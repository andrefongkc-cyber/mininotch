#if DEBUG
import AppKit
import EventKit

/// Reports permission state and, with `--request`, attempts a prompt.
///
/// Run with `MinNotch --check-permissions [--request]`. TCC failures are close to silent:
/// a request that is never shown looks identical to one the user dismissed, so this prints
/// the state before and after, plus the identity macOS is judging, which is what decides
/// whether a prompt appears at all.
@MainActor
enum DebugPermissionsCheck {
    static let flag = "--check-permissions"

    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains(flag) else { return false }
        let shouldRequest = CommandLine.arguments.contains("--request")

        // These checks run before main.swift builds the application, so NSApp is still nil.
        let app = NSApplication.shared

        report("bundle path:       \(Bundle.main.bundlePath)")
        report("bundle id:         \(Bundle.main.bundleIdentifier ?? "nil")")
        report("activation policy: \(app.activationPolicy().rawValue) (0 regular, 1 accessory, 2 prohibited)")
        report("is active:         \(app.isActive)")
        report("usage description: \(Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") != nil ? "present" : "MISSING")")
        report("calendar status:   \(describe(EKEventStore.authorizationStatus(for: .event)))")

        guard shouldRequest else { exit(0) }

        app.finishLaunching()

        // Goes through `CalendarService` rather than a private `EKEventStore`, so this
        // exercises the code the buttons actually run, including the activation handling
        // that is what makes the dialog appear for an accessory app at all.
        let environment = DebugSupport.makeEnvironment()
        let service = environment.calendarService
        service.start(settings: environment.settings)

        report("requesting full access through CalendarService…")
        service.requestAccess { granted in
            report("granted: \(granted)")
            report("prompt never appeared: \(service.promptDidNotAppear)")
            report("status after: \(describe(EKEventStore.authorizationStatus(for: .event)))")
            exit(granted ? 0 : 1)
        }

        // A dialog the user has not answered yet is normal, so the wait is generous.
        RunLoop.main.run(until: Date().addingTimeInterval(90))
        report("no answer after 90s; the dialog may still be open")
        exit(1)
    }

    private static func describe(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined (no prompt shown yet)"
        case .restricted: return "restricted (blocked by policy)"
        case .denied: return "denied"
        case .fullAccess: return "fullAccess"
        case .writeOnly: return "writeOnly"
        case .authorized: return "authorized"
        @unknown default: return "unknown"
        }
    }

    /// Also appends to a file when `--out <path>` is given, because a process started by
    /// LaunchServices has nowhere to send stderr, and launching it any other way changes the
    /// identity TCC judges the request against.
    private static func report(_ message: String) {
        let line = message + "\n"
        FileHandle.standardError.write(line.data(using: .utf8)!)

        guard let index = CommandLine.arguments.firstIndex(of: "--out"),
              CommandLine.arguments.indices.contains(index + 1) else { return }
        let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])

        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? line.data(using: .utf8)?.write(to: url)
        }
    }
}
#endif
