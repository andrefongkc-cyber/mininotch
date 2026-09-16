#if DEBUG
import AppKit

/// Reads what the scriptable players report, including shuffle state and Up Next.
///
/// Run with `MinNotch --check-media [--scripts <dir>] [--out file]`.
///
/// `--scripts` writes the exact AppleScript the sources send into a directory and exits, so
/// `osacompile` can check every term against the player's dictionary without sending it an
/// Apple Event, which means without raising an Automation prompt. Without it, the snapshot and
/// the Up Next read run for real; launch through LaunchServices for that, so the permission
/// being judged is the app's and not the terminal's.
@MainActor
enum DebugMediaCheck {
    static let flag = "--check-media"

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard arguments.contains(flag) else { return false }

        if let index = arguments.firstIndex(of: "--scripts"), arguments.indices.contains(index + 1) {
            let directory = arguments[index + 1]
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            for descriptor in [PlayerDescriptor.appleMusic, .spotify] {
                let source = AppleScriptMediaSource(descriptor: descriptor)
                write(source.debugSnapshotScript, to: directory, name: "\(descriptor.scriptName)-snapshot")
                write(descriptor.shuffleScript, to: directory, name: "\(descriptor.scriptName)-shuffle")
                if let upNext = descriptor.upNextScript {
                    write(upNext.replacingOccurrences(of: "LIMIT", with: "3"), to: directory, name: "\(descriptor.scriptName)-upnext")
                }
            }
            report("scripts written to \(directory)")
            exit(0)
        }

        for descriptor in [PlayerDescriptor.appleMusic, .spotify] {
            let source = AppleScriptMediaSource(descriptor: descriptor)
            guard source.isAvailable else {
                report("\(descriptor.displayName): not running")
                continue
            }
            AppleScriptRunner.shared.queue.sync {
                if let track = source.snapshot() {
                    report("\(descriptor.displayName): \(track.title) by \(track.artist), playing \(track.isPlaying), shuffling \(track.isShuffling.map(String.init) ?? "unknown")")
                } else {
                    report("\(descriptor.displayName): nothing playing")
                }
                report("  up next: \(source.upNext(limit: 3))")
            }
        }
        flush()
        exit(0)
    }

    private static func write(_ script: String, to directory: String, name: String) {
        try? script.write(toFile: (directory as NSString).appendingPathComponent("\(name).applescript"), atomically: true, encoding: .utf8)
    }

    private static var buffer = ""

    private static func report(_ message: String) {
        if outputPath == nil {
            FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
        } else {
            buffer += message + "\n"
        }
    }

    private static func flush() {
        guard let outputPath else { return }
        try? buffer.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    private static var outputPath: String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--out"), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
#endif
