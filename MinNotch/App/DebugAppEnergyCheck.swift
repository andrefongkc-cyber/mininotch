#if DEBUG
import AppKit
import SwiftUI

/// Checks Apps Using the Battery: a stretch counts from its start, energy lands on the app
/// whose coalition the process is in, even once it has exited (a child shell counts as whoever
/// started it), a
/// plug-in ends the stretch and keeps it, an unplug starts a new one, and a relaunch carries on
/// with the saved stretch unless the battery charged in between.
///
/// Run with `MiniNotch --check-app-energy [--card out.png]`. It burns about two seconds of
/// processor in a child process, and keeps its stretch in a scratch file, never the real one.
@MainActor
enum DebugAppEnergyCheck {
    static let flag = "--check-app-energy"

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard arguments.contains(flag) else { return false }
        var failures = 0
        func check(_ passed: Bool, _ what: String) {
            print((passed ? "ok   " : "FAIL ") + what)
            if !passed { failures += 1 }
        }
        func wait(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func sample(_ monitor: AppEnergyMonitor) {
            var done = false
            monitor.debugSample { done = true }
            let deadline = Date().addingTimeInterval(5)
            while !done, Date() < deadline { wait(0.05) }
        }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("minnotch-energy-\(getpid())")
        let file = folder.appendingPathComponent("AppEnergy.json")
        defer { try? FileManager.default.removeItem(at: folder) }

        // Who this process, and so its child, is counted as: the app of its coalition.
        guard let mine = AppEnergySampler.coalition(of: getpid()),
              let expected = AppEnergySampler().app(forMembers: AppEnergySampler.allProcesses()
                .filter { AppEnergySampler.coalition(of: $0) == mine }.sorted())
        else { print("FAIL this process has no coalition"); exit(1) }
        print("this process counts as: \(expected.name) (\(expected.key))")

        let monitor = AppEnergyMonitor()
        monitor.start(fileURL: file)
        monitor.debugBegin(percentage: 80)
        wait(0.5)
        check(monitor.stretch?.sawUnplug == true && monitor.stretch?.startPercentage == 80, "an unplug starts a stretch at 80%")
        check(monitor.ranking.isEmpty, "processes already running count from the start, not from their launch (\(monitor.ranking.count) entries)")

        // Two seconds of one busy process, started by this one, and gone before the reading. A
        // loop that forks would make macOS's own services busy too, and measure them instead.
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        child.arguments = ["-e", "my $end = time + 2; while (time < $end) {}"]
        try? child.run()
        child.waitUntilExit()
        sample(monitor)

        let ranking = monitor.ranking
        for use in ranking.prefix(5) {
            print(String(format: "     %8.2f J  %@", use.joules, use.name))
        }
        let counted = ranking.first { $0.id == expected.key }
        check((counted?.joules ?? 0) > 0.5, String(format: "the busy process, already exited, counted for %@ (%.2f J)", expected.name, counted?.joules ?? 0))
        check(ranking.first?.id == expected.key, "and it used the most since the start")
        check(!ranking.contains { $0.id == "system" && $0.joules > (counted?.joules ?? 0) },
              "it was not counted as System Services")

        // Saved, and read back by a fresh monitor as the same stretch.
        let reloaded = AppEnergyMonitor()
        reloaded.start(fileURL: file)
        check(reloaded.stretch == monitor.stretch, "the stretch is saved and read back whole")
        reloaded.update(battery: status(percentage: 80, pluggedIn: false))
        wait(0.5)
        check(reloaded.stretch?.startedAt == monitor.stretch?.startedAt, "a relaunch on battery carries on with the saved stretch")

        let charged = AppEnergyMonitor()
        charged.start(fileURL: file)
        charged.update(battery: status(percentage: 90, pluggedIn: false))
        wait(0.5)
        check(charged.stretch?.startedAt != monitor.stretch?.startedAt && charged.stretch?.sawUnplug == false,
              "a relaunch after the charge went up starts afresh, from the launch")

        // Plugging in ends the stretch and keeps it; unplugging starts a new one.
        monitor.update(battery: status(percentage: 79, pluggedIn: true))
        wait(1)
        check(monitor.stretch?.endedAt != nil, "plugging in ends the stretch")
        check(monitor.ranking.contains { $0.id == expected.key }, "and keeps its list to show")
        monitor.update(battery: status(percentage: 79, pluggedIn: false))
        wait(0.5)
        check(monitor.stretch?.endedAt == nil && monitor.stretch?.sawUnplug == true && monitor.ranking.isEmpty,
              "unplugging again starts a new stretch")

        if let index = arguments.firstIndex(of: "--card"), index + 1 < arguments.count {
            renderCard(stretch: reloaded.stretch, ranking: reloaded.ranking, to: arguments[index + 1])
        }

        print(failures == 0 ? "\nall passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func status(percentage: Int, pluggedIn: Bool) -> BatteryStatus {
        var status = BatteryStatus()
        status.isPresent = true
        status.percentage = percentage
        status.isPluggedIn = pluggedIn
        return status
    }

    private static func renderCard(stretch: BatteryStretch?, ranking: [AppEnergyUse], to path: String) {
        let card = AppEnergyCard(stretch: stretch, ranking: ranking, isPluggedIn: false)
            .padding(20)
            .frame(width: 560)
            .background(Palette.paneBackground)
        let hosting = NSHostingView(rootView: card)
        hosting.frame.size = hosting.fittingSize
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("card drawn to \(path)")
    }
}
#endif
