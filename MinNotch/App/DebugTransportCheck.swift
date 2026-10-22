#if DEBUG
import AppKit

/// Presses play, pause and next on the sample song and prints what the card would show.
///
/// Run with `MiniNotch --check-transport`.
///
/// The card changes on the click and the player confirms afterwards (`NowPlayingController.send`).
/// The first version of that crashed on the first click, reading `track` inside an assignment to
/// it, and nothing had pressed a button before it reached the user. The sample song is Apple
/// Music's, and Music is never launched by a command, so this sends nothing anywhere.
@MainActor
enum DebugTransportCheck {
    static let flag = "--check-transport"

    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains(flag) else { return false }
        let environment = DebugSupport.makeEnvironment()
        let controller = environment.nowPlaying
        controller.applySample(settings: environment.settings)

        func report(_ step: String) {
            let track = controller.track
            print("\(step): playing \(track?.isPlaying ?? false), at \(String(format: "%.1f", controller.elapsed())) s")
        }
        report("start")
        controller.send(.playPause)
        report("after pause")
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        report("a second later")
        controller.send(.playPause)
        report("after play")
        controller.send(.nextTrack)
        report("after next")
        return true
    }
}
#endif
