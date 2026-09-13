import Foundation

/// Settings > Battery.
struct BatterySettings: Codable, Equatable {
    // There is no `showInPill`. Whether the battery appears in the closed pill or the
    // panel's top strip is now part of the arrangement for each of those surfaces,
    // `general.pillLeading` / `pillTrailing` and `appearance.topStripTrailing`, so a
    // separate switch here would have been a second answer to the same question. Old
    // settings files still carrying the key are ignored by the lenient decode.

    /// Show the numeric percentage next to the glyph.
    var showPercentage: Bool = true

    /// Post a notification when the charge drops through `lowBatteryThreshold`.
    var lowBatteryNotifications: Bool = true

    /// Percentage that triggers the low-battery notification.
    var lowBatteryThreshold: Int = 20

    /// Also notify when a charger is connected or removed.
    var notifyOnPowerSourceChange: Bool = false

    /// Show estimated time remaining in the expanded battery detail.
    var showTimeRemaining: Bool = true

    // MARK: V2 scaffolding

    /// Live Activity showing AirPods and other Bluetooth device charge.
    var showBluetoothDeviceBattery: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showPercentage = c.value(.showPercentage, true)
        lowBatteryNotifications = c.value(.lowBatteryNotifications, true)
        lowBatteryThreshold = c.value(.lowBatteryThreshold, 20, in: 5...50)
        notifyOnPowerSourceChange = c.value(.notifyOnPowerSourceChange, false)
        showTimeRemaining = c.value(.showTimeRemaining, true)
        showBluetoothDeviceBattery = c.value(.showBluetoothDeviceBattery, false)
    }
}
