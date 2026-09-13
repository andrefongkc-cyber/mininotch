import IOKit.ps
import Observation
import SwiftUI

/// Charge state of the internal battery.
struct BatteryStatus: Equatable {
    var isPresent: Bool = false
    /// 0...100.
    var percentage: Int = 0
    var isCharging: Bool = false
    var isPluggedIn: Bool = false
    var isCharged: Bool = false
    /// Minutes until empty or full, or nil while the estimate is still being calculated.
    var minutesRemaining: Int?
    var isLowPowerMode: Bool = false

    /// SF Symbol matching the current state, using Apple's own battery glyph family.
    var symbolName: String {
        guard isPresent else { return "powerplug" }
        if isCharging { return "battery.100percent.bolt" }
        switch percentage {
        case ..<10: return "battery.0percent"
        case ..<35: return "battery.25percent"
        case ..<60: return "battery.50percent"
        case ..<85: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    /// Colour for the glyph. Yellow in Low Power Mode and red when critical, matching the
    /// system menu bar item so the two never disagree.
    ///
    /// The neutral case is white rather than a semantic label colour: this is only ever
    /// drawn on the notch, which is black in both appearances, so a colour that flips with
    /// the system appearance would disappear in light mode.
    var tint: Color {
        if isCharging || isPluggedIn { return Color(nsColor: .systemGreen) }
        if isLowPowerMode { return Color(nsColor: .systemYellow) }
        if percentage <= 10 { return Color(nsColor: .systemRed) }
        return .white
    }

    var timeRemainingDescription: String? {
        guard let minutesRemaining, minutesRemaining > 0 else { return nil }
        let hours = minutesRemaining / 60
        let minutes = minutesRemaining % 60
        let suffix = isCharging ? "until full" : "remaining"
        if hours > 0 { return "\(hours)h \(minutes)m \(suffix)" }
        return "\(minutes)m \(suffix)"
    }
}

/// Reads the internal battery and republishes it as observable state.
///
/// IOKit posts a run-loop notification whenever any power source changes, so there is no
/// polling: the readout updates the moment the charger is plugged in or the percentage
/// ticks over.
@Observable
final class BatteryService {
    private(set) var status = BatteryStatus()

    /// Set by `AppEnvironment` so notification posting stays out of the service.
    @ObservationIgnored var onLowBattery: ((Int) -> Void)?
    @ObservationIgnored var onPowerSourceChange: ((Bool) -> Void)?

    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var lastNotifiedThresholdCrossing: Int?
    @ObservationIgnored private var lastPluggedIn: Bool?
    @ObservationIgnored private var settings: SettingsStore?

    init() {}

    func start(settings: SettingsStore) {
        self.settings = settings
        refresh()

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { service.refresh() }
        }, context)?.takeRetainedValue() else {
            AppLog.battery.error("Could not create the power source run loop source")
            return
        }

        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        runLoopSource = nil
    }

    func refresh() {
        let newStatus = Self.read()
        let previous = status
        status = newStatus

        evaluateLowBattery(previous: previous, current: newStatus)
        evaluatePowerSourceChange(current: newStatus)
    }

    // MARK: Reading IOKit

    private static func read() -> BatteryStatus {
        var status = BatteryStatus()
        status.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return status }

        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            guard info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }

            status.isPresent = true

            let current = info[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = info[kIOPSMaxCapacityKey] as? Int ?? 100
            status.percentage = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : 0

            status.isCharging = info[kIOPSIsChargingKey] as? Bool ?? false
            status.isCharged = info[kIOPSIsChargedKey] as? Bool ?? false
            status.isPluggedIn = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

            // IOKit reports -1 while it is still computing an estimate, which it does for a
            // minute or two after any power state change and after waking from sleep. A nil
            // here means "not known yet", never "no time left".
            let key = status.isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            if let minutes = info[key] as? Int, minutes >= 0 {
                status.minutesRemaining = minutes
            } else {
                status.minutesRemaining = nil
            }
            break
        }

        return status
    }

    // MARK: Notifications

    private func evaluateLowBattery(previous: BatteryStatus, current: BatteryStatus) {
        guard let settings, settings.battery.lowBatteryNotifications else { return }
        guard current.isPresent, !current.isCharging, !current.isPluggedIn else {
            // Charging again re-arms the notification for the next discharge.
            lastNotifiedThresholdCrossing = nil
            return
        }

        let threshold = settings.battery.lowBatteryThreshold
        let crossedDown = previous.percentage > threshold && current.percentage <= threshold
        let startedBelow = previous.percentage == 0 && current.percentage <= threshold

        guard crossedDown || startedBelow else { return }
        guard lastNotifiedThresholdCrossing != threshold else { return }

        lastNotifiedThresholdCrossing = threshold
        onLowBattery?(current.percentage)
    }

    private func evaluatePowerSourceChange(current: BatteryStatus) {
        guard let settings, settings.battery.notifyOnPowerSourceChange else {
            lastPluggedIn = current.isPluggedIn
            return
        }
        defer { lastPluggedIn = current.isPluggedIn }
        guard let lastPluggedIn, lastPluggedIn != current.isPluggedIn else { return }
        onPowerSourceChange?(current.isPluggedIn)
    }
}

#if DEBUG
extension BatteryService {
    /// Injects a fixed reading for offscreen design review, so previews do not depend on
    /// the charge of whatever Mac happens to be rendering them.
    func applySampleStatus() {
        status = BatteryStatus(
            isPresent: true,
            percentage: 68,
            isCharging: false,
            isPluggedIn: false,
            isCharged: false,
            minutesRemaining: 214,
            isLowPowerMode: false
        )
    }
}
#endif
