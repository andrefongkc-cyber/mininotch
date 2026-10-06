import SwiftUI

/// The System widget. Today it is the battery detail; CPU, memory, and network readouts
/// join it here rather than getting their own tab.
struct SystemWidgetView: View {
    @Environment(\.notchStyle) private var theme
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings

    private var status: BatteryStatus { environment.battery.status }

    /// Height the widget needs, excluding the panel's padding and top strip.
    static func preferredHeight(bluetoothDeviceCount: Int, showsChargingPower: Bool) -> CGFloat {
        var batteryBlock: CGFloat = 54
        if showsChargingPower { batteryBlock += 8 + chargingPowerHeight }
        // The readout, then the graph under it.
        let statsBlock: CGFloat = 58 + StatChart.spacing + StatChart.height
        let deviceBlock: CGFloat = 26
        let divider: CGFloat = 1
        let spacing: CGFloat = 12

        var height = batteryBlock
        if FeatureFlag.systemStats.isEnabled {
            height += spacing + divider + spacing + statsBlock
        }
        if bluetoothDeviceCount > 0 {
            height += spacing + divider + spacing + deviceBlock
        }
        return height
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if status.isPresent {
                batteryDetail
            } else {
                noBattery
            }

            if showsStats {
                Divider().overlay(theme.ink.opacity(0.12))
                statsRow
            }

            if !environment.bluetooth.devices.isEmpty {
                Divider().overlay(theme.ink.opacity(0.12))
                bluetoothRow
            }

            Spacer(minLength: 0)
        }
        // Sampling is tied to this view being on screen, so nothing is measured while the
        // panel is closed or another tab is showing.
        .onAppear {
            if showsStats { environment.systemStats.beginSampling() }
            environment.bluetooth.beginSampling()
            environment.battery.beginPowerSampling()
        }
        .onDisappear {
            if showsStats { environment.systemStats.endSampling() }
            environment.bluetooth.endSampling()
            environment.battery.endPowerSampling()
        }
    }

    // MARK: Bluetooth accessories

    /// One chip per connected accessory that reports charge. Earbuds contribute a chip each
    /// for left, right, and case, because an average would hide whichever one is nearly flat.
    private var bluetoothRow: some View {
        HStack(spacing: 14) {
            ForEach(environment.bluetooth.devices.prefix(4)) { device in
                HStack(spacing: 5) {
                    Image(systemName: device.symbolName)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.ink.opacity(0.55))

                    Text(device.name)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.ink.opacity(0.7))
                        .lineLimit(1)

                    Text("\(device.percentage)%")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(device.isLow ? Color(nsColor: .systemRed) : theme.ink.opacity(0.9))

                    if device.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Color(nsColor: .systemGreen))
                    }
                }
                .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .frame(height: 20)
    }

    private var showsStats: Bool {
        FeatureFlag.systemStats.isEnabled && settings.advanced.showSystemStats
    }

    // MARK: Battery

    private var batteryDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TransportSymbol.hierarchical(
                    status.symbolName,
                    pointSize: 22,
                    color: status.isCharging ? Color(nsColor: .systemGreen) : theme.ink
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(status.percentage)%")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(theme.ink)
                    Text(stateDescription)
                        .font(Typography.helper)
                        .foregroundStyle(theme.ink.opacity(0.55))
                }

                Spacer()

                // Named, because a bare thermometer and a number here read as the chip's temperature
                // further down, which is the question this answered when it had no label.
                if let temperature = environment.systemStats.stats.batteryTemperature, showsStats {
                    Label {
                        Text("Battery " + TemperatureFormat.string(celsius: temperature, fahrenheit: usesFahrenheit))
                    } icon: {
                        // Through `TransportSymbol`: as a plain system image it stayed white,
                        // whatever colour it was given, and vanished on a light Notch Style.
                        TransportSymbol.image("thermometer.medium", pointSize: 11, weight: .medium)
                    }
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(theme.ink.opacity(0.6))
                        .help("Battery temperature")
                }

                if status.isLowPowerMode {
                    Text("Low Power")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(nsColor: .systemYellow))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(nsColor: .systemYellow).opacity(0.18)))
                }
            }

            GeometryReader { proxy in
                let fraction = min(max(Double(status.percentage) / 100, 0), 1)
                ZStack(alignment: .leading) {
                    NotchElementView(.groove, shape: .capsule, emphasis: 0.14)
                    NotchTrackFill(color: status.tint(neutral: theme.ink))
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 6)
            .animation(Motion.content, value: status.percentage)

            if environment.battery.showsChargingPower {
                chargingPowerRow
            }
        }
    }

    // MARK: Charging power

    static let chargingPowerHeight: CGFloat = 24

    private var power: ChargingPower? { environment.battery.power }

    /// While plugged in: what the charger delivers, what the Mac uses of it, and what goes into
    /// the battery, over a bar as wide as the charger's rating. How much of the charger's power
    /// is actually charging is the green part of the bar, and the figure on the right.
    private var chargingPowerRow: some View {
        VStack(spacing: 5) {
            HStack(spacing: 12) {
                powerFigure("In", power?.input.map { PowerFormat.watts($0) })
                powerFigure("Mac", power?.system.map { PowerFormat.watts($0) })
                powerFigure(
                    "Battery",
                    power?.battery.map { PowerFormat.watts($0, signed: true) },
                    tint: power?.isDraining == true ? Color(nsColor: .systemOrange)
                        : power?.isCharging == true ? Color(nsColor: .systemGreen) : nil
                )
                Spacer(minLength: 8)
                Text(chargingSummary.text)
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(chargingSummary.tint)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
            .frame(height: 14)

            PowerFlowBar(power: power, adapterWatts: status.adapterWatts)
                .frame(height: 5)
        }
        .frame(height: Self.chargingPowerHeight)
        .animation(Motion.content, value: power)
    }

    private func powerFigure(_ label: String, _ value: String?, tint: Color? = nil) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(theme.ink.opacity(0.45))
            Text(value ?? "–")
                .fontWeight(.medium)
                .foregroundStyle(tint ?? theme.ink.opacity(0.9))
                .contentTransition(.numericText())
        }
        .font(.system(size: 11))
        .monospacedDigit()
        .fixedSize()
    }

    /// The one-line answer to "is this charging well": the battery's share of what comes in,
    /// or what is wrong when the battery is not gaining.
    private var chargingSummary: (text: String, tint: Color) {
        let quiet = theme.ink.opacity(0.5)
        let warning = Color(nsColor: .systemOrange)
        guard let power else { return ("", quiet) }
        if let input = power.input, input < 1 { return ("Charger giving no power", warning) }
        if power.isDraining { return ("Charger can't keep up", warning) }
        if let share = power.batteryShare {
            return ("\(Int((share * 100).rounded()))% into the battery", Color(nsColor: .systemGreen))
        }
        // Full, or held by Optimised Charging or a charge limit: the charger is running the
        // Mac and the battery is being kept where it is.
        return (status.isCharged ? "Battery full" : "Not charging", quiet)
    }

    /// The state, and while plugged in the charger's rating, which is the ceiling everything in
    /// the charging row is measured against.
    private var stateDescription: String {
        guard environment.battery.showsChargingPower, let watts = status.adapterWatts else { return chargeState }
        return chargeState + " · \(watts) W charger"
    }

    private var chargeState: String {
        if status.isCharged && status.isPluggedIn { return "Fully charged" }

        if settings.battery.showTimeRemaining {
            if let description = status.timeRemainingDescription { return description }

            // macOS throws away its estimate whenever the power state changes and reports
            // nothing until the draw settles, which is why the time appears and disappears.
            // Saying "Charging" there reads as the estimate being unsupported rather than
            // pending, so this matches the wording Apple's own menu bar uses.
            if status.isCharging || !status.isPluggedIn { return "Calculating…" }
        }

        if status.isCharging { return "Charging" }
        if status.isPluggedIn { return "Plugged in" }
        return "On battery"
    }

    private var noBattery: some View {
        HStack(spacing: 10) {
            Image(systemName: "powerplug")
                .font(.system(size: 20))
                .foregroundStyle(theme.ink.opacity(0.5))
            VStack(alignment: .leading, spacing: 1) {
                Text("No Battery")
                    .font(Typography.bodyEmphasised)
                    .foregroundStyle(theme.ink.opacity(0.8))
                Text("This Mac runs on wall power.")
                    .font(Typography.helper)
                    .foregroundStyle(theme.ink.opacity(0.5))
            }
            Spacer()
        }
    }

    // MARK: Stats

    // MARK: Stats

    private var stats: SystemStats { environment.systemStats.stats }
    private var history: SystemStatsHistory { environment.systemStats.history }

    /// A rate history as fractions of its own peak, since a network rate has no fixed ceiling.
    /// A floor keeps an idle connection's few bytes from being drawn as a full-height line.
    private static func scaledToPeak(_ points: [ChartPoint]) -> [ChartPoint] {
        let peak = max(points.map(\.value).max() ?? 0, 64 * 1024)
        return points.map { ChartPoint(x: $0.x, value: $0.value / peak) }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell(
                label: "CPU",
                symbol: "cpu",
                value: percentage(stats.cpuUsage),
                fraction: stats.cpuUsage,
                history: history.points { $0.cpu }
            )

            if let gpu = stats.gpuUsage {
                statCell(label: "GPU", symbol: "cpu.fill", value: percentage(gpu), fraction: gpu, history: history.points { $0.gpu })
            } else {
                // Some Macs publish no GPU utilisation counter. Showing a permanent zero
                // would read as an idle GPU rather than as a missing measurement.
                statCell(label: "GPU", symbol: "cpu.fill", value: "n/a", fraction: nil)
            }

            statCell(
                label: "Memory",
                symbol: "memorychip",
                value: ByteFormat.size(stats.memoryUsed),
                fraction: stats.memoryFraction,
                history: history.points { $0.memory }
            )

            statCell(
                label: "Network",
                symbol: "network",
                value: "↓ " + ByteFormat.rate(stats.networkIn),
                fraction: nil,
                secondaryText: "↑ " + ByteFormat.rate(stats.networkOut),
                history: Self.scaledToPeak(history.points { $0.network })
            )

            if settings.advanced.showTemperatures {
                temperatureCell
            }
        }
    }

    /// The chip's hottest point, with the SSD beside it in the label.
    ///
    /// The bar and the graph span 30 to 100 °C, roughly idle to throttling, and take their
    /// colour from the heat rather than from load. A Mac that reports no temperatures shows
    /// "n/a" rather than nothing, as the GPU does, so the gap reads as unmeasured.
    @ViewBuilder
    private var temperatureCell: some View {
        let ssd = stats.ssdTemperature.map { " · SSD " + TemperatureFormat.string(celsius: $0, fahrenheit: usesFahrenheit) } ?? ""
        if let chip = stats.chipTemperature {
            statCell(
                label: "Chip" + ssd,
                symbol: "thermometer.medium",
                value: TemperatureFormat.string(celsius: chip, fahrenheit: usesFahrenheit),
                fraction: Self.heatFraction(chip),
                history: history.points { $0.chipTemperature.map(Self.heatFraction) },
                barTint: Self.heatTint(chip),
                chartTint: Self.heatTint(chip)
            )
        } else {
            statCell(label: "Chip", symbol: "thermometer.medium", value: "n/a", fraction: nil)
        }
    }

    private var usesFahrenheit: Bool { settings.weather.units.usesFahrenheit }

    private static func heatFraction(_ celsius: Double) -> Double {
        min(max((celsius - 30) / 70, 0), 1)
    }

    /// Cool reads as calm, warm as a warning, hot as a problem: green under 70 °C, orange
    /// under 90, red above.
    private static func heatTint(_ celsius: Double) -> Color {
        switch celsius {
        case ..<70: return Color(nsColor: .systemGreen)
        case ..<90: return Color(nsColor: .systemOrange)
        default: return Color(nsColor: .systemRed)
        }
    }

    /// One readout. `fraction` draws a bar, `secondaryText` replaces it, and passing neither
    /// leaves the row blank so every cell stays the same height.
    private func statCell(
        label: String,
        symbol: String,
        value: String,
        fraction: Double?,
        secondaryText: String? = nil,
        history: [ChartPoint] = [],
        barTint: Color? = nil,
        chartTint: Color? = nil
    ) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(theme.ink.opacity(0.45))

            // Every text that changes with the reading rolls its digits rather than cross-fading.
            // A cross-fade drew the old number and the new one on top of each other for a moment,
            // which read as a scrambled "9ɞ°F" rather than as 95 becoming 96.
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(theme.ink.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())

            Group {
                if let fraction {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            NotchElementView(.groove, shape: .capsule, emphasis: 0.14)
                            NotchTrackFill(color: barTint ?? tint(for: fraction))
                                .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                        }
                    }
                    .frame(height: 3)
                    .padding(.horizontal, 12)
                } else if let secondaryText {
                    Text(secondaryText)
                        .font(.system(size: 9))
                        .monospacedDigit()
                        .foregroundStyle(theme.ink.opacity(0.4))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                } else {
                    Color.clear
                }
            }
            .frame(height: 10)

            Text(label)
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(theme.ink.opacity(0.4))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.numericText())

            StatChart(values: history, tint: chartTint ?? settings.appearance.resolvedAccent)
                .padding(.horizontal, 8)
                .padding(.top, StatChart.spacing - 2)
        }
        .frame(maxWidth: .infinity)
        .animation(Motion.content, value: value)
    }

    /// Green through amber to red as load climbs, so a glance is enough.
    private func tint(for fraction: Double) -> Color {
        switch fraction {
        case ..<0.6: return settings.appearance.resolvedAccent
        case ..<0.85: return Color(nsColor: .systemOrange)
        default: return Color(nsColor: .systemRed)
        }
    }

    private func percentage(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}

/// The last five minutes of one reading, under it: a line in the reading's colour over a fill
/// that fades to nothing, on a faint ground with a midline, so it reads as a graph even before
/// there is much in it.
///
/// It used to sit behind the numbers, faint, and its history was thrown away whenever the tab
/// closed, so what anyone saw was a few seconds of it, a sliver against the right edge that read
/// as a glitch. The service now samples in the background too, and the graph is drawn by time:
/// newest at the right edge, five minutes ago at the left.
struct StatChart: View {
    @Environment(\.notchStyle) private var theme
    var values: [ChartPoint]
    var tint: Color

    static let height: CGFloat = 22
    static let spacing: CGFloat = 6

    var body: some View {
        ZStack {
            NotchElementView(.tile, shape: .rounded(4), emphasis: 0.05)
            Rectangle()
                .fill(theme.ink.opacity(0.06))
                .frame(height: 0.5)
            if values.count > 1 {
                SparklineShape(points: values, closed: true)
                    .fill(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                SparklineShape(points: values, closed: false)
                    .stroke(tint.opacity(0.95), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .allowsHitTesting(false)
    }
}

/// A line through `points`, placed by their `x` across the rect.
///
/// A `Shape` rather than a `Canvas`, because `Canvas` output does not appear in a layer
/// capture and this has to be checkable with `--capture-notch`. `closed` draws each stretch down
/// to the bottom edge and back, for the fill under the line. Two samples further apart than
/// `maxGap` are not joined: that is the Mac asleep or saving power, not a reading that slid from
/// one value to the other. The line is inset a point from the top and bottom so a reading pinned
/// at either end is not half cut off by the clip.
struct SparklineShape: Shape {
    var points: [ChartPoint]
    var closed: Bool
    /// Twenty seconds, as a fraction of the five minute window.
    var maxGap: Double = 20 / SystemStatsHistory.window

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset: CGFloat = 1
        let usable = rect.height - inset * 2

        func position(_ point: ChartPoint) -> CGPoint {
            CGPoint(
                x: rect.minX + rect.width * CGFloat(min(max(point.x, 0), 1)),
                y: rect.maxY - inset - usable * CGFloat(min(max(point.value, 0), 1))
            )
        }

        var runs: [[ChartPoint]] = []
        for point in points {
            if let last = runs.last?.last, point.x - last.x <= maxGap {
                runs[runs.count - 1].append(point)
            } else {
                runs.append([point])
            }
        }

        for run in runs where run.count > 1 {
            let first = position(run[0])
            if closed {
                path.move(to: CGPoint(x: first.x, y: rect.maxY))
                path.addLine(to: first)
            } else {
                path.move(to: first)
            }
            for point in run.dropFirst() { path.addLine(to: position(point)) }
            if closed {
                path.addLine(to: CGPoint(x: position(run[run.count - 1]).x, y: rect.maxY))
                path.closeSubpath()
            }
        }
        return path
    }
}

/// Where the charger's power goes, as one bar the width of the charger's rating: the Mac's share
/// in white, the battery's in green, and what the charger could give but is not, empty. While
/// the battery is helping instead, its part is orange, after what the charger covers.
private struct PowerFlowBar: View {
    @Environment(\.notchStyle) private var theme
    var power: ChargingPower?
    var adapterWatts: Int?

    var body: some View {
        GeometryReader { proxy in
            let segments = segments
            let scale = scale
            HStack(spacing: 1) {
                ForEach(segments.indices, id: \.self) { index in
                    Rectangle()
                        .fill(segments[index].tint)
                        .frame(width: max(proxy.size.width * min(segments[index].watts / scale, 1) - 1, 0))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.ink.opacity(0.12))
            .clipShape(Capsule())
        }
        .help(help)
    }

    private var segments: [(watts: Double, tint: Color)] {
        guard let power else { return [] }
        let mac = power.system ?? 0
        let battery = power.battery ?? 0
        let all: [(watts: Double, tint: Color)] = power.isDraining
            ? [
                (power.input ?? max(mac + battery, 0), theme.ink.opacity(0.6)),
                (-battery, Color(nsColor: .systemOrange)),
            ]
            : [
                (mac, theme.ink.opacity(0.6)),
                (power.isCharging ? battery : 0, Color(nsColor: .systemGreen)),
            ]
        // An empty segment would still take a gap's width.
        return all.filter { $0.watts > 0 }
    }

    /// The charger's rating, unless the readings already exceed it, as they briefly can.
    private var scale: Double {
        let used = (power?.system ?? 0) + max(power?.battery ?? 0, 0)
        return max(Double(adapterWatts ?? 0), power?.input ?? 0, used, 1)
    }

    private var help: String {
        guard let power else { return "" }
        var parts: [String] = []
        if let adapterWatts { parts.append("A \(adapterWatts) W charger") }
        if let input = power.input { parts.append("giving \(PowerFormat.watts(input))") }
        if let system = power.system { parts.append("the Mac using \(PowerFormat.watts(system))") }
        if let battery = power.battery {
            parts.append(battery < 0 ? "the battery adding \(PowerFormat.watts(-battery))" : "the battery taking \(PowerFormat.watts(battery))")
        }
        return parts.joined(separator: ", ")
    }
}
