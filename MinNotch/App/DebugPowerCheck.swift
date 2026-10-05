#if DEBUG
import Foundation
import IOKit.ps

/// Reads the charging figures the System tab shows, once a second, beside what they are made of.
///
/// Run with `MiniNotch --check-power [seconds]`.
///
/// The SMC keys are undocumented, so this is how to see whether a given Mac has them and whether
/// they add up: what comes in should be about what the Mac uses plus what goes into the battery,
/// and the difference is the conversion loss, a watt or two. The battery's own registry entry is
/// printed beside them as a cross-check; it updates far less often, so it lags.
@MainActor
enum DebugPowerCheck {
    static let flag = "--check-power"

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag) else { return false }
        let seconds = arguments.indices.contains(index + 1) ? Int(arguments[index + 1]) ?? 5 : 5

        if let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
            let watts = adapter[kIOPSPowerAdapterWattsKey] as? Int
            print("charger: \(watts.map { "\($0) W" } ?? "no rating"), \(adapter["Description"] as? String ?? "no description")")
        } else {
            print("charger: none connected")
        }

        func show(_ value: Double?) -> String { value.map { String(format: "%6.2f W", $0) } ?? "   none " }
        for _ in 0..<max(seconds, 1) {
            let semaphore = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var result: PowerSensors.Reading?
            let started = Date()
            PowerSensors.shared.read { reading in
                result = reading
                semaphore.signal()
            }
            semaphore.wait()
            let elapsed = Date().timeIntervalSince(started) * 1000

            guard let reading = result else {
                print("no power keys on this Mac's SMC")
                return true
            }
            var line = "in \(show(reading.input))  Mac \(show(reading.system))  battery \(show(reading.battery))"
            if let milliamps = reading.batteryMilliamps, let millivolts = reading.batteryMillivolts {
                line += String(format: " (%5.0f mA at %5.0f mV)", milliamps, millivolts)
            }
            if let input = reading.input, let system = reading.system, let battery = reading.battery {
                line += String(format: "  loss %5.2f W", input - system - battery)
            }
            line += String(format: "  %.2f ms", elapsed)
            print(line + "  | registry: " + registry())
            RunLoop.main.run(until: Date().addingTimeInterval(1))
        }
        PowerSensors.shared.close()
        return true
    }

    /// The battery's `PowerTelemetryData`, refreshed by the system about every 45 seconds.
    private static func registry() -> String {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return "no battery entry" }
        defer { IOObjectRelease(service) }
        guard let telemetry = IORegistryEntryCreateCFProperty(service, "PowerTelemetryData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any] else { return "no telemetry" }
        func watts(_ key: String) -> String {
            (telemetry[key] as? Int).map { String(format: "%.1f", Double($0) / 1000) } ?? "?"
        }
        return "in \(watts("SystemPowerIn")) load \(watts("SystemLoad")) battery \(watts("BatteryPower"))"
    }
}
#endif
