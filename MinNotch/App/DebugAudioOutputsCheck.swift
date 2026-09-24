#if DEBUG
import Foundation

/// Lists the sound outputs the Now Playing card would offer.
///
/// Run with `MinNotch --check-audio-outputs`.
///
/// Read-only: it never changes the output or the volume. What it checks is the filtering, which
/// is the part that can go wrong unseen: every real output listed with a symbol that draws, the
/// default one marked, and no aggregate device, such as the private one the audio tap builds.
@MainActor
enum DebugAudioOutputsCheck {
    static let flag = "--check-audio-outputs"

    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains(flag) else { return false }

        let service = AudioOutputService()
        service.beginObserving()
        defer { service.endObserving() }

        print("\(service.devices.count) outputs")
        for device in service.devices {
            let mark = device.id == service.defaultID ? "*" : " "
            print(" \(mark) \(device.name)  [\(device.symbolName)]  id \(device.id)")
        }
        let volume = service.volume.map { String(format: "%.2f", $0) } ?? "not settable"
        print("volume \(volume)\(service.isMuted ? ", muted" : "")")
        return true
    }
}
#endif
