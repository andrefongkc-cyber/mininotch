import Foundation

extension Timer {
    /// A repeating timer on the main run loop, in common modes, whose action runs on the main
    /// actor.
    ///
    /// Every timer in the app drives main-actor state, and `Timer`'s block is `@Sendable` with
    /// no isolation, so each one used to reach into its owner from a context the compiler
    /// could not prove was the main thread. It always was: the timer is added to the main run
    /// loop right here, which is what makes `assumeIsolated` true rather than hopeful. Common
    /// modes so the timer keeps firing while a menu is open or a slider is being dragged.
    static func onMain(every interval: TimeInterval, _ action: @escaping @MainActor @Sendable () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { action() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
