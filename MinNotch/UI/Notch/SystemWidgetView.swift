import SwiftUI

/// The System widget. Today it is the battery detail; CPU, memory, and network readouts
/// join it here rather than getting their own tab.
struct SystemWidgetView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings

    private var status: BatteryStatus { environment.battery.status }

    /// Height the widget needs, excluding the panel's padding and top strip.
    static func preferredHeight(bluetoothDeviceCount: Int) -> CGFloat {
        let batteryBlock: CGFloat = 54
        let statsBlock: CGFloat = 58
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
                Divider().overlay(Color.white.opacity(0.12))
                statsRow
            }

            if !environment.bluetooth.devices.isEmpty {
                Divider().overlay(Color.white.opacity(0.12))
                bluetoothRow
            }

            Spacer(minLength: 0)
        }
        // Sampling is tied to this view being on screen, so nothing is measured while the
        // panel is closed or another tab is showing.
        .onAppear {
            if showsStats { environment.systemStats.beginSampling() }
            environment.bluetooth.beginSampling()
        }
        .onDisappear {
            if showsStats { environment.systemStats.endSampling() }
            environment.bluetooth.endSampling()
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
                        .foregroundStyle(.white.opacity(0.55))

                    Text(device.name)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)

                    Text("\(device.percentage)%")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(device.isLow ? Color(nsColor: .systemRed) : .white.opacity(0.9))

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
                Image(systemName: status.symbolName)
                    .font(.system(size: 22))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(status.isCharging ? Color(nsColor: .systemGreen) : .white)

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(status.percentage)%")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(stateDescription)
                        .font(Typography.helper)
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()

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
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule()
                        .fill(status.tint)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 6)
            .animation(Motion.content, value: status.percentage)
        }
    }

    private var stateDescription: String {
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
                .foregroundStyle(.white.opacity(0.5))
            VStack(alignment: .leading, spacing: 1) {
                Text("No Battery")
                    .font(Typography.bodyEmphasised)
                    .foregroundStyle(.white.opacity(0.8))
                Text("This Mac runs on wall power.")
                    .font(Typography.helper)
                    .foregroundStyle(.white.opacity(0.5))
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
    private static func scaledToPeak(_ values: [Double]) -> [Double] {
        let peak = max(values.max() ?? 0, 64 * 1024)
        return values.map { $0 / peak }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell(
                label: "CPU",
                symbol: "cpu",
                value: percentage(stats.cpuUsage),
                fraction: stats.cpuUsage,
                history: history.cpu
            )

            if let gpu = stats.gpuUsage {
                statCell(label: "GPU", symbol: "cpu.fill", value: percentage(gpu), fraction: gpu, history: history.gpu)
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
                history: history.memory
            )

            statCell(
                label: "Network",
                symbol: "network",
                value: "↓ " + ByteFormat.rate(stats.networkIn),
                fraction: nil,
                secondaryText: "↑ " + ByteFormat.rate(stats.networkOut),
                history: Self.scaledToPeak(history.network)
            )
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
        history: [Double] = []
    ) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))

            Text(value)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Group {
                if let fraction {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.14))
                            Capsule()
                                .fill(tint(for: fraction))
                                .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                        }
                    }
                    .frame(height: 3)
                    .padding(.horizontal, 12)
                } else if let secondaryText {
                    Text(secondaryText)
                        .font(.system(size: 9))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Color.clear
                }
            }
            .frame(height: 10)

            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        // The last minute or so behind the numbers, faint enough to read over, so a spike that
        // came and went between glances is still there to see.
        .background {
            if history.count > 1 {
                ZStack {
                    SparklineShape(values: history, closed: true)
                        .fill(Color.white.opacity(0.06))
                    SparklineShape(values: history, closed: false)
                        .stroke(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
                }
                .padding(.horizontal, 6)
                .allowsHitTesting(false)
            }
        }
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

/// A line through `values`, each 0...1, spread evenly across the rect, newest on the right.
///
/// A `Shape` rather than a `Canvas`, because `Canvas` output does not appear in a layer
/// capture and this has to be checkable with `--capture-notch`. `closed` draws it down to the
/// bottom edge and back, for the fill under the line.
struct SparklineShape: Shape {
    var values: [Double]
    var closed: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        // Always spaced for a full history, so the line grows in from the right as samples
        // arrive rather than stretching across the cell from the first two.
        let step = rect.width / CGFloat(SystemStatsHistory.capacity - 1)
        let startX = rect.maxX - step * CGFloat(values.count - 1)

        func point(_ index: Int) -> CGPoint {
            let value = min(max(values[index], 0), 1)
            return CGPoint(x: startX + step * CGFloat(index), y: rect.maxY - rect.height * CGFloat(value))
        }

        if closed { path.move(to: CGPoint(x: startX, y: rect.maxY)); path.addLine(to: point(0)) } else { path.move(to: point(0)) }
        for index in values.indices.dropFirst() { path.addLine(to: point(index)) }
        if closed {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}
