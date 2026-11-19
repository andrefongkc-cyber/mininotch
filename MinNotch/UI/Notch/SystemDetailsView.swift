import AppKit
import SwiftUI

/// The expanded System tab's extra readings (2026-11-18): the top three apps by processor,
/// graphics and memory, each with Quit; every core's load; then memory pressure, storage,
/// battery health, heat, fans, power and uptime as tiles.
///
/// Samples only while it is on screen (`SystemDetailsService.beginSampling`), since the per-app
/// figures walk every process.
struct SystemDetailsView: View {
    @Environment(\.notchStyle) private var theme
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings

    private var service: SystemDetailsService { environment.systemDetails }
    private var details: SystemDetails { service.details }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topApps
            cores
            tiles
        }
        .onAppear { service.beginSampling(interval: max(1.5, settings.advanced.statsRefreshInterval)) }
        .onDisappear { service.endSampling() }
    }

    // MARK: Top apps

    private var topApps: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Top Apps")
            HStack(alignment: .top, spacing: 12) {
                appColumn("CPU", details.topCPU) { Self.percent($0) }
                appColumn("GPU", details.topGPU) { Self.percent($0) }
                appColumn("Memory", details.topMemory) { ByteFormat.size(UInt64($0)) }
            }
        }
    }

    private func appColumn(_ title: String, _ loads: [AppLoad], format: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.ink.opacity(0.45))
            if loads.isEmpty {
                Text(details.topMemory.isEmpty ? "Measuring…" : "Nothing busy")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.ink.opacity(0.35))
                    .frame(height: 20)
            }
            ForEach(loads) { load in
                AppLoadRow(load: load, value: format(load.value)) { service.quit(bundlePath: $0) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Cores

    private var cores: some View {
        let all = Array(details.cores.enumerated())
        let performance = all.filter { !details.efficiencyCores.contains($0.offset) }
        let efficiency = all.filter { details.efficiencyCores.contains($0.offset) }
        return VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Cores")
            HStack(alignment: .bottom, spacing: 18) {
                if !performance.isEmpty { coreGroup("Performance", performance.map(\.element)) }
                if !efficiency.isEmpty { coreGroup("Efficiency", efficiency.map(\.element)) }
                Spacer(minLength: 0)
            }
        }
    }

    private func coreGroup(_ title: String, _ loads: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(loads.indices, id: \.self) { index in
                    let load = loads[index]
                    ZStack(alignment: .bottom) {
                        NotchElementView(.groove, shape: .rounded(2), emphasis: 0.14)
                        NotchTrackFill(color: tint(for: load))
                            .frame(height: max(2, 30 * load))
                    }
                    .frame(width: 9, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                    .help("\(Self.percent(load))")
                }
            }
            .animation(Motion.content, value: loads)
            Text("\(title) · \(loads.count)")
                .font(.system(size: 9))
                .foregroundStyle(theme.ink.opacity(0.45))
        }
    }

    // MARK: Tiles

    private var tiles: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 4)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            memoryTile
            storageTile
            batteryTile
            thermalTile
            fansTile
            powerTile
            uptimeTile
        }
    }

    private var memoryTile: some View {
        let pressure = details.pressure
        let tint: Color = switch pressure {
        case .critical: Color(nsColor: .systemRed)
        case .warning: Color(nsColor: .systemOrange)
        default: Color(nsColor: .systemGreen)
        }
        return tile("Memory Pressure", symbol: "memorychip",
                    value: pressure?.title ?? "–", valueTint: pressure == nil ? nil : tint,
                    detail: details.swapTotal > 0 ? "Swap \(ByteFormat.size(details.swapUsed)) of \(ByteFormat.size(details.swapTotal))" : "No swap in use")
    }

    private var storageTile: some View {
        let free = details.diskFree.map { ByteFormat.size(UInt64($0)) + " free" } ?? "–"
        let fraction: Double? = {
            guard let total = details.diskTotal, total > 0, let free = details.diskFree else { return nil }
            return 1 - Double(free) / Double(total)
        }()
        let rates = details.diskRead.map { "R \(ByteFormat.rate($0)) · W \(ByteFormat.rate(details.diskWrite ?? 0))" }
        return tile("Storage", symbol: "internaldrive", value: free,
                    valueTint: (fraction ?? 0) > 0.95 ? Color(nsColor: .systemRed) : nil,
                    detail: rates ?? details.diskTotal.map { "of " + ByteFormat.size(UInt64($0)) } ?? "",
                    fraction: fraction)
    }

    private var batteryTile: some View {
        let health = details.battery
        let capacity = health?.maximumCapacity.map { "\(Int(($0 * 100).rounded()))%" }
        let cycles = health?.cycleCount.map { "\($0) cycles" }
        let needsService = health?.condition == "Service Recommended"
        return tile("Battery Health", symbol: "battery.100percent",
                    value: health == nil ? "No battery" : (capacity.map { "\($0) capacity" } ?? "–"),
                    detail: [cycles, health?.condition].compactMap { $0 }.joined(separator: " · "),
                    detailTint: needsService ? Color(nsColor: .systemOrange) : nil)
    }

    private var thermalTile: some View {
        let state = service.thermalState
        let (title, detail, tint): (String, String, Color?) = switch state {
        case .nominal: ("Cool", "Running at full speed", nil)
        case .fair: ("Warm", "Running at full speed", Color(nsColor: .systemYellow))
        case .serious: ("Hot", "Slowing down to cool off", Color(nsColor: .systemOrange))
        case .critical: ("Very hot", "Slowed down a lot", Color(nsColor: .systemRed))
        @unknown default: ("–", "", nil)
        }
        return tile("Heat", symbol: "thermometer.medium", value: title, valueTint: tint, detail: detail)
    }

    private var fansTile: some View {
        let fans = details.fans
        let value: String = {
            guard let fans else { return "–" }
            if fans.isEmpty { return "No fans" }
            return fans.map { "\(Int($0.rounded())) rpm" }.joined(separator: ", ")
        }()
        return tile("Fans", symbol: "fan", value: value,
                    detail: fans?.isEmpty == true ? "Cooled without a fan" : (fans == nil ? "" : (fans!.allSatisfy { $0 < 1 } ? "Stopped" : "Spinning")))
    }

    private var powerTile: some View {
        let status = environment.battery.status
        if status.isPresent, !status.isPluggedIn {
            return tile("Power", symbol: "bolt", value: details.powerOnBattery.map { PowerFormat.watts($0) + " used" } ?? "–",
                        detail: status.timeRemainingDescription ?? "Calculating time left…")
        }
        return tile("Power", symbol: "powerplug", value: status.isPresent ? "Plugged in" : "Wall power",
                    detail: environment.battery.power?.system.map { "Mac using \(PowerFormat.watts($0))" } ?? "Unplug to see the draw")
    }

    private var uptimeTile: some View {
        TimelineView(.everyMinute) { context in
            tile("Uptime", symbol: "clock.arrow.circlepath",
                 value: details.bootTime.map { Self.duration(context.date.timeIntervalSince($0)) } ?? "–",
                 detail: details.bootTime.map { "Since " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "")
        }
    }

    /// One reading in a small box: a label with its symbol, the value, and a line under it.
    private func tile(_ title: String, symbol: String, value: String, valueTint: Color? = nil,
                      detail: String, detailTint: Color? = nil, fraction: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9))
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(theme.ink.opacity(0.45))
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(valueTint ?? theme.ink.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            if let fraction {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        NotchElementView(.groove, shape: .capsule, emphasis: 0.14)
                        NotchTrackFill(color: tint(for: fraction))
                            .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                    }
                }
                .frame(height: 3)
            }
            Text(detail)
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(detailTint ?? theme.ink.opacity(0.45))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .padding(8)
        .background(NotchElementView(.tile, shape: .rounded(8), emphasis: 0.05))
        .animation(Motion.content, value: value)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.ink.opacity(0.7))
    }

    private func tint(for fraction: Double) -> Color {
        switch fraction {
        case ..<0.6: return theme.accentColor(settings.appearance.resolvedAccent)
        case ..<0.85: return Color(nsColor: .systemOrange)
        default: return Color(nsColor: .systemRed)
        }
    }

    static func percent(_ fraction: Double) -> String {
        let value = fraction * 100
        return value < 10 ? String(format: "%.1f%%", value) : "\(Int(value.rounded()))%"
    }

    /// "3d 4h", "5h 12m", "42m".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        let days = minutes / 1440, hours = minutes / 60 % 24, rest = minutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(rest)m" }
        return "\(rest)m"
    }
}

/// One app in a Top Apps list: its icon, name and figure, and on hover a Quit button.
private struct AppLoadRow: View {
    @Environment(\.notchStyle) private var theme
    let load: AppLoad
    let value: String
    let quit: (String) -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 5) {
            AppIcon(bundlePath: load.bundlePath, kind: load.kind)
                .frame(width: 16, height: 16)
            Text(load.name)
                .font(.system(size: 11))
                .foregroundStyle(theme.ink.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)
            Spacer(minLength: 2)
            if isHovering, SystemDetailsService.canQuit(load), let path = load.bundlePath {
                Button { quit(path) } label: {
                    Text("Quit")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .systemRed))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(nsColor: .systemRed).opacity(0.15)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Quit \(load.name). It can still ask to save your work.")
            } else {
                Text(value)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(theme.ink.opacity(0.75))
                    .contentTransition(.numericText())
            }
        }
        .frame(height: 20)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(Motion.content, value: value)
    }
}

/// An app's own icon, or a symbol for macOS's services and command line tools.
private struct AppIcon: View {
    @Environment(\.notchStyle) private var theme
    let bundlePath: String?
    let kind: AppEnergyUse.Kind

    @MainActor private static var cache: [String: NSImage] = [:]

    var body: some View {
        if let bundlePath, let image = Self.icon(bundlePath) {
            Image(nsImage: image).resizable().interpolation(.high)
        } else {
            Image(systemName: kind == .system ? "gearshape.2" : "terminal")
                .font(.system(size: 10))
                .foregroundStyle(theme.ink.opacity(0.5))
        }
    }

    @MainActor private static func icon(_ path: String) -> NSImage? {
        if let cached = cache[path] { return cached }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache[path] = image
        return image
    }
}
