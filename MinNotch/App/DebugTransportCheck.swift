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
        // One ordinary read first, so the sample is the song the controller already knows, as a
        // playing song always is by the time anyone presses pause.
        controller.simulateRead(isPlaying: true, elapsed: 97)
        report("start")
        controller.send(.playPause)
        report("after pause")
        // The player answering before it has acted: it must not flip the button back.
        controller.simulateRead(isPlaying: true, elapsed: 97.2)
        report("player still says playing (want: false)")
        controller.simulateRead(isPlaying: false, elapsed: 97.2)
        report("player agrees (want: false)")
        controller.send(.playPause)
        report("after play (want: true)")
        controller.simulateRead(isPlaying: false, elapsed: 97.2)
        report("player still says paused (want: true)")
        // A player that ignored the command: after the hold, what it says is shown.
        controller.simulateRead(isPlaying: false, elapsed: 97.2, at: Date().addingTimeInterval(2))
        report("ignored, 2 s on (want: false)")
        controller.send(.nextTrack)
        controller.simulateRead(isPlaying: true, elapsed: 98)
        report("after next, old position read (want: ~0)")
        return true
    }
}
#endif
