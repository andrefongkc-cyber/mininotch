#if DEBUG
import AppKit

/// Checks everything about taking the volume and brightness keys that can be checked without
/// pressing one.
///
/// Run with `MinNotch --check-keys [--simulate] [--apply] [--out f]`, through `open -n -a` so Accessibility
/// is judged against the app and not the terminal.
///
/// - Decodes a synthetic event for every key, down and up, with and without Shift and Option,
///   through the same function the tap uses.
/// - Reports whether Accessibility is granted, and whether the tap installs.
/// - Reports whether this Mac's current output and display can be set in software.
/// - With `--simulate`, posts a real volume-up press with the tap taking it, and checks the
///   volume did not move, which is the proof macOS never received the key.
/// - With `--apply`, steps the volume up and back down once and reports both levels. That is
///   audible for a moment if something is playing, which is why it is not the default.
@MainActor
enum DebugKeysCheck {
    static let flag = "--check-keys"

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard arguments.contains(flag) else { return false }

        var lines: [String] = []
        func say(_ line: String) { lines.append(line) }

        var decodeFailures = 0
        for key in SystemKeyInterceptor.Key.allCases {
            for isDown in [true, false] {
                for modifiers in [NSEvent.ModifierFlags(), [.shift, .option]] {
                    guard let event = SystemKeyInterceptor.makeEvent(for: key, isDown: isDown, modifiers: modifiers),
                          let press = SystemKeyInterceptor.press(from: event),
                          press.key == key, press.isDown == isDown,
                          press.isFineStep == modifiers.contains([.shift, .option])
                    else {
                        decodeFailures += 1
                        say("decode FAILED: \(key) down=\(isDown) modifiers=\(modifiers.rawValue)")
                        continue
                    }
                }
            }
        }
        say("decode: \(SystemKeyInterceptor.Key.allCases.count * 4 - decodeFailures)/\(SystemKeyInterceptor.Key.allCases.count * 4) events round-trip")

        let trusted = SystemKeyInterceptor.isTrusted
        say("accessibility trusted: \(trusted)")
        let interceptor = SystemKeyInterceptor()
        let started = interceptor.start()
        say("tap installed: \(started)")
        interceptor.stop()

        let volume = VolumeMonitor()
        let brightness = BrightnessMonitor()
        say("output volume settable: \(volume.canSetVolume)")
        say("display brightness settable: \(brightness.canSetBrightness) (now \(brightness.readBrightness().map { String(format: "%.3f", $0) } ?? "unreadable"))")

        // Posts a real volume-up press into the event stream with the tap installed and taking
        // it, then checks the tap saw it and the volume did not move, which means macOS never
        // got the key. If the tap failed to take it, the volume went up a step and is put back.
        if arguments.contains("--simulate") {
            volume.start()
            let before = volume.read()
            var seen: [SystemKeyInterceptor.Press] = []
            let tap = SystemKeyInterceptor()
            tap.wantsKey = { $0 == .volumeUp }
            tap.perform = { seen.append($0); return true }
            if tap.start() {
                for isDown in [true, false] {
                    SystemKeyInterceptor.makeEvent(for: .volumeUp, isDown: isDown)?.cgEvent?.post(tap: .cghidEventTap)
                    RunLoop.main.run(until: Date().addingTimeInterval(0.25))
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.5))
                tap.stop()
                let after = volume.read()
                let unchanged = before.map { b in after.map { abs($0.0 - b.0) < 0.0001 } ?? false } ?? false
                say("simulate: tap saw \(seen.count) press(es), volume before \(before.map { String(format: "%.4f", $0.0) } ?? "?") after \(after.map { String(format: "%.4f", $0.0) } ?? "?"), swallowed: \(unchanged)")
                if !unchanged, let before, let after, after.0 > before.0 {
                    _ = volume.apply(.volumeDown, fineStep: false)
                    say("simulate: volume moved, stepped it back down")
                }
            } else {
                say("simulate: tap not installed")
            }
            volume.stop()
        }

        // The control for `--simulate`: the same press with no tap, which must move the volume,
        // or an unchanged volume above proves nothing. Shows Apple's overlay once, then puts the
        // level and mute state back.
        if arguments.contains("--control") {
            volume.start()
            let before = volume.read()
            SystemKeyInterceptor.makeEvent(for: .volumeUp, isDown: true)?.cgEvent?.post(tap: .cghidEventTap)
            SystemKeyInterceptor.makeEvent(for: .volumeUp, isDown: false)?.cgEvent?.post(tap: .cghidEventTap)
            RunLoop.main.run(until: Date().addingTimeInterval(0.8))
            let after = volume.read()
            say("control: no tap, volume before \(before.map { String(format: "%.4f muted=%@", $0.0, String($0.1)) } ?? "?") after \(after.map { String(format: "%.4f muted=%@", $0.0, String($0.1)) } ?? "?")")
            if let before, let after, after.0 > before.0 + 0.0001 {
                _ = volume.apply(.volumeDown, fineStep: false)
                if let restored = volume.read(), restored.1 != before.1 { _ = volume.apply(.mute, fineStep: false) }
                say("control: restored to \(volume.read().map { String(format: "%.4f muted=%@", $0.0, String($0.1)) } ?? "?")")
            }
            volume.stop()
        }

        if arguments.contains("--apply") {
            let up = volume.apply(.volumeUp, fineStep: false)
            let down = volume.apply(.volumeDown, fineStep: false)
            say("volume up -> \(up.map { String(format: "%.4f muted=%@", $0.level, String($0.muted)) } ?? "not applied")")
            say("volume down -> \(down.map { String(format: "%.4f muted=%@", $0.level, String($0.muted)) } ?? "not applied")")
        }

        let output = lines.joined(separator: "\n") + "\n"
        if let index = arguments.firstIndex(of: "--out"), arguments.indices.contains(index + 1) {
            try? output.write(toFile: arguments[index + 1], atomically: true, encoding: .utf8)
        }
        FileHandle.standardError.write(output.data(using: .utf8)!)
        return true
    }
}
#endif
