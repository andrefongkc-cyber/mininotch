import AppKit
import SwiftUI

/// Settings > Battery > Apps Using the Battery: the apps that have used the most energy since the
/// Mac was unplugged, or over the last time on battery while it is plugged in (`AppEnergyMonitor`).
struct AppEnergyCard: View {
    var stretch: BatteryStretch?
    var ranking: [AppEnergyUse]
    var isPluggedIn: Bool

    /// The list stops here; the rest are summed into one row.
    private static let shown = 8

    var body: some View {
        SettingsCard(
            header: "Battery Use",
            footer: "Processor and graphics energy, as macOS tallies it for each app and everything the app starts, read by MiniNotch while it runs. Work macOS does for an app counts as the app's; the rest of macOS is System Services. The display is not counted, so these are shares of what apps used, not of the whole battery."
        ) {
            SettingsRow(
                title: "Apps Using the Battery",
                subtitle: summary,
                systemImage: "bolt.batteryblock"
            ) {
                EmptyView()
            }

            if !ranking.isEmpty {
                let total = ranking.reduce(0) { $0 + $1.joules }
                let top = ranking.prefix(Self.shown)
                let rest = ranking.dropFirst(Self.shown)
                ForEach(Array(top)) { use in
                    SettingsDivider()
                    AppEnergyRow(
                        name: use.name, icon: Self.icon(for: use), joules: use.joules,
                        share: use.joules / total, wattHours: stretch?.batteryWattHours
                    )
                }
                if !rest.isEmpty {
                    let joules = rest.reduce(0) { $0 + $1.joules }
                    SettingsDivider()
                    AppEnergyRow(
                        name: "\(rest.count) Others", icon: Image(systemName: "ellipsis.circle"), joules: joules,
                        share: joules / total, wattHours: stretch?.batteryWattHours
                    )
                }
            }
        }
    }

    private var summary: String {
        guard let stretch else {
            return isPluggedIn
                ? "Unplug the Mac and MiniNotch starts counting which apps use the battery."
                : "Counting starts in a moment."
        }
        let time = stretch.startedAt.formatted(date: Self.isToday(stretch.startedAt) ? .omitted : .abbreviated, time: .shortened)
        let charge = stretch.startPercentage == stretch.lastPercentage
            ? "at \(stretch.startPercentage)%"
            : "\(stretch.startPercentage)% to \(stretch.lastPercentage)%"
        if let ended = stretch.endedAt {
            let end = ended.formatted(date: .omitted, time: .shortened)
            return "Your last time on battery, \(time) to \(end), \(charge)."
        }
        let since = stretch.sawUnplug ? "Since you unplugged at \(time)" : "Since \(time), when MiniNotch started on battery"
        if ranking.isEmpty { return "\(since). Nothing to show yet: check back in a minute." }
        return "\(since), \(charge)."
    }

    private static func isToday(_ date: Date) -> Bool { Calendar.current.isDateInToday(date) }

    private static func icon(for use: AppEnergyUse) -> Image {
        switch use.kind {
        case .app:
            if let path = use.bundlePath { return Image(nsImage: NSWorkspace.shared.icon(forFile: path)) }
            return Image(systemName: "app")
        case .system: return Image(systemName: "gearshape.2")
        case .tool: return Image(systemName: "terminal")
        }
    }
}

private struct AppEnergyRow: View {
    var name: String
    var icon: Image
    var joules: Double
    var share: Double
    var wattHours: Double?

    var body: some View {
        HStack(spacing: 10) {
            icon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 20, height: 20)

            Text(name)
                .font(Typography.body)
                .foregroundStyle(Palette.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 12)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.separator.opacity(0.5))
                    Capsule().fill(Palette.controlAccent)
                        .frame(width: max(3, proxy.size.width * min(max(share, 0), 1)))
                }
            }
            .frame(width: 110, height: 6)

            Text(share > 0 && share < 0.005 ? "<1%" : share.formatted(.percent.precision(.fractionLength(0))))
                .font(Typography.body.monospacedDigit())
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 42, alignment: .trailing)
        }
        .padding(.horizontal, Metrics.cardHorizontalPadding)
        .padding(.vertical, 7)
        .help(detail)
    }

    /// The figure behind the share, and what it is of a full battery.
    private var detail: String {
        let wh = joules / 3600
        var text = "\(name) used \(wh.formatted(.number.precision(.fractionLength(wh < 0.1 ? 3 : 2)))) Wh"
        if let wattHours, wattHours > 0 {
            let ofCharge = wh / wattHours
            text += ", about \(ofCharge.formatted(.percent.precision(.fractionLength(ofCharge < 0.01 ? 1 : 0)))) of a full charge"
        }
        return text + "."
    }
}
