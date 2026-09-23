#if DEBUG
import Foundation

/// Plays out downloads in a scratch folder and checks what the monitor reports.
///
/// Run with `MinNotch --check-downloads [--out f]`.
///
/// The real Downloads folder is a privacy permission and a real download is slow and depends on
/// the network, so the check does what a browser does, in a folder of its own: a Chrome-style
/// `.crdownload` that grows and is renamed, a Safari-style `.download` bundle whose `Info.plist`
/// carries the byte counts, and a cancelled one whose temporary file just disappears.
@MainActor
enum DebugDownloadsCheck {
    static let flag = "--check-downloads"

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard arguments.contains(flag) else { return false }

        var lines: [String] = []
        var failures = 0
        func check(_ label: String, _ passed: Bool, _ detail: String) {
            if !passed { failures += 1 }
            lines.append("\(passed ? "ok  " : "FAIL") \(label): \(detail)")
        }

        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("minnotch-downloads-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let monitor = DownloadsMonitor(folder: folder, asksFromForeground: false)
        var latest: [DownloadItem] = []
        monitor.onChange = { latest = $0 }
        monitor.start()

        func wait(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func item(_ name: String) -> DownloadItem? { latest.first { $0.name == name } }

        // Chrome: a growing .crdownload, renamed when done.
        let chrome = folder.appendingPathComponent("report.pdf.crdownload")
        FileManager.default.createFile(atPath: chrome.path, contents: Data(count: 1000))
        wait(1.5)
        check("chrome started", item("report.pdf") != nil, item("report.pdf").map { "seen as \($0.name)" } ?? "not seen")
        try? FileManager.default.moveItem(at: chrome, to: folder.appendingPathComponent("report.pdf"))
        wait(1.5)
        check("chrome finished", item("report.pdf")?.isFinished == true, item("report.pdf").map { "finished \($0.isFinished)" } ?? "gone")

        // Safari: a bundle with byte counts in its Info.plist.
        let safari = folder.appendingPathComponent("movie.mov.download")
        try? FileManager.default.createDirectory(at: safari, withIntermediateDirectories: true)
        let plist: NSDictionary = ["DownloadEntryProgressBytesSoFar": 250, "DownloadEntryProgressTotalToLoad": 1000]
        plist.write(to: safari.appendingPathComponent("Info.plist"), atomically: true)
        wait(1.5)
        let fraction = item("movie.mov")?.fraction
        check("safari progress", fraction.map { abs($0 - 0.25) < 0.01 } ?? false, fraction.map { String(format: "%.2f", $0) } ?? "no fraction")

        // Cancelled: the temporary file goes and nothing replaces it.
        let cancelled = folder.appendingPathComponent("big.iso.part")
        FileManager.default.createFile(atPath: cancelled.path, contents: Data(count: 10))
        wait(1.5)
        let sawCancelled = item("big.iso") != nil
        try? FileManager.default.removeItem(at: cancelled)
        wait(1.5)
        check("cancelled", sawCancelled && item("big.iso") == nil, sawCancelled ? (item("big.iso") == nil ? "seen, then removed" : "still listed") : "never seen")

        check("names", DownloadsMonitor.finalName(for: "a.tar.gz.crdownload") == "a.tar.gz", DownloadsMonitor.finalName(for: "a.tar.gz.crdownload"))

        monitor.stop()
        lines.append(failures == 0 ? "all checks passed" : "\(failures) check(s) failed")
        let output = lines.joined(separator: "\n") + "\n"
        if let index = arguments.firstIndex(of: "--out"), arguments.indices.contains(index + 1) {
            try? output.write(toFile: arguments[index + 1], atomically: true, encoding: .utf8)
        }
        FileHandle.standardError.write(output.data(using: .utf8)!)
        return true
    }
}
#endif
