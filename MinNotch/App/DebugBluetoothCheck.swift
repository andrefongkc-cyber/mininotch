#if DEBUG
import AppKit

/// What the connection popup can see: headphones' charge from the profiler, the Bluetooth audio
/// devices Core Audio lists, and, with `--watch <seconds>`, every popup a connection would raise.
///
/// Run with `MiniNotch --check-bluetooth [--watch 60] [--out f]`. Launch it through `open` so it
/// runs as the app rather than as the terminal.
@MainActor
enum DebugBluetoothCheck {
    static let flag = "--check-bluetooth"

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard arguments.contains(flag) else { return false }
        var lines: [String] = []
        func say(_ line: String) {
            print(line)
            lines.append(line)
        }

        let started = Date()
        let profiled = BluetoothProfiler.connectedDevices()
        say(String(format: "profiler, %.2f s:", Date().timeIntervalSince(started)))
        for device in profiled { say("  \(device.name): \(device.percentage)%") }
        if profiled.isEmpty { say("  nothing with a charge") }

        say("Core Audio Bluetooth devices:")
        for name in BluetoothBatteryService.bluetoothAudioDevices().values { say("  \(name)") }

        if let index = arguments.firstIndex(of: "--watch"), index + 1 < arguments.count,
           let seconds = TimeInterval(arguments[index + 1]) {
            let service = BluetoothBatteryService()
            service.onDeviceConnected = { devices in
                say("connected: " + devices.map { "\($0.name) \($0.percentage)%" }.joined(separator: ", "))
            }
            service.startWatchingConnections()
            say("watching for \(Int(seconds)) s: connect a device now")
            RunLoop.main.run(until: Date().addingTimeInterval(seconds))
            service.stopWatchingConnections()
        }

        if let index = arguments.firstIndex(of: "--out"), index + 1 < arguments.count {
            try? lines.joined(separator: "\n").write(toFile: arguments[index + 1], atomically: true, encoding: .utf8)
        }
        return true
    }
}
#endif
