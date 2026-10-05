#if DEBUG
import Foundation

/// Reads the Mac's temperature sensors once and prints them.
///
/// Run with `MiniNotch --check-temps`.
///
/// The sensors are private and their names differ by chip, so this is how to see what a given
/// Mac actually offers: every sensor the HID event system reports, then the three figures the
/// System tab shows, which come from the die sensors, the battery's fuel gauge and the SSD.
@MainActor
enum DebugTemperatureCheck {
    static let flag = "--check-temps"

    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains(flag) else { return false }

        let sensors = TemperatureSensors.shared.allSensors()
        print("\(sensors.count) sensors with a plausible reading")
        for sensor in sensors {
            print(String(format: "  %-28@ %6.1f °C", sensor.name as NSString, sensor.celsius))
        }

        let semaphore = DispatchSemaphore(value: 0)
        let started = Date()
        nonisolated(unsafe) var result: TemperatureSensors.Reading?
        TemperatureSensors.shared.read { reading in
            result = reading
            semaphore.signal()
        }
        semaphore.wait()
        let elapsed = Date().timeIntervalSince(started) * 1000

        func show(_ value: Double?) -> String { value.map { String(format: "%.1f °C", $0) } ?? "none" }
        print("System tab: chip \(show(result?.chip)), battery \(show(result?.battery)), SSD \(show(result?.ssd))")
        print(String(format: "one read took %.0f ms, off the main thread", elapsed))
        return true
    }
}
#endif
