import Foundation
import IOKit

/// Live power figures from the Mac's System Management Controller: what the charger is
/// delivering, what the Mac itself is using, and the battery's current and voltage.
///
/// macOS has no API for these. The battery's IO registry entry carries a `PowerTelemetryData`
/// dictionary, but it is refreshed about once every 45 seconds, and its load and battery
/// figures disagreed with the battery's own current while charging. The SMC updates every
/// second and its figures add up, so this reads it the way Stats and AlDente do: open the
/// `AppleSMC` user client, which any process may read, and ask for four-character keys.
/// The key names are Apple's and undocumented, so a Mac without one reports that figure as nil
/// rather than failing.
///
/// - `PDTR`: watts arriving from the charger.
/// - `PSTR`: watts the whole Mac is using, not counting what goes into the battery.
/// - `B0AC`, `B0AV`: the battery's current in milliamps, positive while charging, and its
///   voltage in millivolts. Their product is what goes into the battery, or comes out of it.
///
/// One reading is eight round trips to the SMC, about 0.65 ms on an M4: cheap, but it is a
/// coprocessor that can be slow to answer, so it happens on a queue of its own and never on
/// main. Everything below is confined to that queue.
final class PowerSensors: @unchecked Sendable {
    struct Reading: Sendable, Equatable {
        /// Watts, or nil where this Mac's SMC has no such key.
        var input: Double?
        var system: Double?
        /// The battery's current, positive while charging, and its voltage.
        var batteryMilliamps: Double?
        var batteryMillivolts: Double?

        /// Watts into the battery, negative while the battery helps power the Mac.
        var battery: Double? {
            guard let batteryMilliamps, let batteryMillivolts else { return nil }
            return batteryMilliamps * batteryMillivolts / 1_000_000
        }

        var isEmpty: Bool { input == nil && system == nil && battery == nil }
    }

    static let shared = PowerSensors()

    private let queue = DispatchQueue(label: "com.minnotch.power", qos: .utility)

    // Confined to `queue`.
    private var connection: io_connect_t = 0
    private var keyInfo: [UInt32: (size: Int, type: String)] = [:]
    private var missingKeys: Set<UInt32> = []

    /// Reads once, off the main thread, and calls back on that queue with nil when the SMC
    /// cannot be opened or has none of the keys.
    func read(_ completion: @escaping @Sendable (Reading?) -> Void) {
        queue.async { [self] in
            let reading = readNow()
            completion(reading.isEmpty ? nil : reading)
        }
    }

    /// Lets the SMC connection go once nothing is showing the figures.
    func close() {
        queue.async { [self] in
            guard connection != 0 else { return }
            IOServiceClose(connection)
            connection = 0
        }
    }

    private func readNow() -> Reading {
        guard openIfNeeded() else { return Reading() }
        return Reading(
            input: value(Key.input).flatMap { Self.plausibleWatts.contains($0) ? $0 : nil },
            system: value(Key.system).flatMap { Self.plausibleWatts.contains($0) ? $0 : nil },
            batteryMilliamps: value(Key.batteryCurrent),
            batteryMillivolts: value(Key.batteryVoltage)
        )
    }

    private static let plausibleWatts: ClosedRange<Double> = 0...400

    // MARK: The SMC

    private enum Key {
        static let input = fourCharacterCode("PDTR")
        static let system = fourCharacterCode("PSTR")
        static let batteryCurrent = fourCharacterCode("B0AC")
        static let batteryVoltage = fourCharacterCode("B0AV")
    }

    /// `SMCParamStruct`, 80 bytes. It is handled as bytes at the offsets C gives its fields,
    /// because a Swift struct makes no promise to pad the way the kernel's C struct does.
    private enum Layout {
        static let size = 80
        static let key = 0
        static let dataSize = 28
        static let dataType = 32
        static let result = 40
        static let command = 42
        static let bytes = 48
    }

    /// `kSMCHandleYPCEvent`, the one method every request goes through, and its two commands.
    private static let handleEvent: UInt32 = 2
    private static let readBytes: UInt8 = 5
    private static let readKeyInfo: UInt8 = 9

    /// Apple silicon's SMC stores numbers little-endian; an Intel Mac's stores them big-endian.
    private static let isLittleEndian: Bool = {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }()

    private func openIfNeeded() -> Bool {
        if connection != 0 { return true }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        var opened: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &opened) == kIOReturnSuccess else {
            AppLog.battery.error("Could not open the SMC for power readings")
            return false
        }
        connection = opened
        return true
    }

    private func value(_ key: UInt32) -> Double? {
        guard !missingKeys.contains(key) else { return nil }
        guard let info = info(for: key) else {
            missingKeys.insert(key)
            return nil
        }
        var input = [UInt8](repeating: 0, count: Layout.size)
        Self.put(key, into: &input, at: Layout.key)
        Self.put(UInt32(info.size), into: &input, at: Layout.dataSize)
        input[Layout.command] = Self.readBytes
        guard let output = call(input) else { return nil }
        return Self.decode(Array(output[Layout.bytes ..< Layout.bytes + info.size]), type: info.type)
    }

    /// A key's size and type, asked for once: they do not change while the Mac runs.
    private func info(for key: UInt32) -> (size: Int, type: String)? {
        if let known = keyInfo[key] { return known }
        var input = [UInt8](repeating: 0, count: Layout.size)
        Self.put(key, into: &input, at: Layout.key)
        input[Layout.command] = Self.readKeyInfo
        guard let output = call(input) else { return nil }
        let size = Int(Self.uint32(output, at: Layout.dataSize))
        let type = Self.typeName(Self.uint32(output, at: Layout.dataType))
        guard (1...32).contains(size) else { return nil }
        keyInfo[key] = (size, type)
        return (size, type)
    }

    private func call(_ input: [UInt8]) -> [UInt8]? {
        var input = input
        var output = [UInt8](repeating: 0, count: Layout.size)
        var outputSize = Layout.size
        let result = IOConnectCallStructMethod(connection, Self.handleEvent, &input, Layout.size, &output, &outputSize)
        guard result == kIOReturnSuccess, output[Layout.result] == 0 else { return nil }
        return output
    }

    /// The handful of types the four keys come in: a 32-bit float on Apple silicon, 16-bit
    /// integers for the battery, and the signed fixed point (`sp78` and kin, the second hex
    /// digit its fraction bits) an Intel Mac uses for watts.
    private static func decode(_ bytes: [UInt8], type: String) -> Double? {
        func integer(_ count: Int) -> UInt64 {
            let ordered = isLittleEndian ? bytes.prefix(count).reversed() : Array(bytes.prefix(count))
            return ordered.reduce(0) { $0 << 8 | UInt64($1) }
        }
        switch (type, bytes.count) {
        case ("flt ", 4):
            return Double(Float(bitPattern: UInt32(integer(4))))
        case ("si16", 2):
            return Double(Int16(bitPattern: UInt16(integer(2))))
        case ("ui16", 2):
            return Double(UInt16(integer(2)))
        case (let fixed, 2) where fixed.hasPrefix("sp") || fixed.hasPrefix("fp"):
            guard let fractionBits = Int(String(fixed.suffix(1)), radix: 16) else { return nil }
            // These are big-endian on the Intel Macs that use them.
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            let whole = fixed.hasPrefix("sp") ? Double(Int16(bitPattern: raw)) : Double(raw)
            return whole / Double(1 << fractionBits)
        default:
            return nil
        }
    }

    private static func fourCharacterCode(_ name: String) -> UInt32 {
        name.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func typeName(_ code: UInt32) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xff) }, encoding: .ascii) ?? ""
    }

    /// The request's own integers are in the machine's byte order; only values are the SMC's.
    private static func put(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        withUnsafeBytes(of: value) { raw in
            for index in 0..<4 { bytes[offset + index] = raw[index] }
        }
    }

    private static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        bytes[offset ..< offset + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    }
}

/// Watts for display: one decimal under ten, where a tenth is still a real share, whole watts
/// above it, where a tenth is noise.
enum PowerFormat {
    static func watts(_ value: Double, signed: Bool = false) -> String {
        let magnitude = abs(value)
        let number = magnitude < 9.95 ? String(format: "%.1f", magnitude) : String(Int(magnitude.rounded()))
        // A reading that rounds to zero has no direction worth showing.
        if number == "0.0" { return "0 W" }
        guard signed else { return number + " W" }
        return (value > 0 ? "+" : "−") + number + " W"
    }
}
