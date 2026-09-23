import Observation
import SwiftUI

/// Holds the set of currently active Live Activities and decides which one the pill shows.
///
/// Cycling between several with a two-finger swipe is a V2 feature; `selectedIndex` and
/// `cycle(by:)` exist now so that gesture only has to call a method that already works.
@Observable
@MainActor
final class LiveActivityCenter {
    private(set) var activities: [LiveActivity] = []
    private(set) var selectedIndex: Int = 0

    // Unchecked so `deinit`, which is not on the main actor, can invalidate it.
    @ObservationIgnored nonisolated(unsafe) private var expiryTimer: Timer?

    init() {
                let timer = Timer.onMain(every: 1) { [weak self] in
            self?.pruneExpired()
        }
        expiryTimer = timer
    }

    deinit { expiryTimer?.invalidate() }

    /// Adds or replaces an activity, keeping the list sorted by priority.
    func present(_ activity: LiveActivity) {
        if let index = activities.firstIndex(where: { $0.id == activity.id }) {
            activities[index] = activity
        } else {
            activities.append(activity)
        }
        activities.sort { $0.priority > $1.priority }
        clampSelection()
    }

    func dismiss(id: String) {
        activities.removeAll { $0.id == id }
        clampSelection()
    }

    func dismissAll(kind: LiveActivity.Kind) {
        activities.removeAll { $0.kind == kind }
        clampSelection()
    }

    /// The activity the collapsed pill should render, if any.
    var current: LiveActivity? {
        guard activities.indices.contains(selectedIndex) else { return activities.first }
        return activities[selectedIndex]
    }

    /// Takes the current activity out of the pill, if it is one that can be put away: a notice
    /// such as a finished download or a device connecting. A running timer cannot, because the
    /// pill is where it is being watched. Returns whether anything was dismissed.
    @discardableResult
    func dismissCurrentNotice() -> Bool {
        guard let current, current.kind == .download || current.kind == .bluetoothDevice else { return false }
        dismiss(id: current.id)
        return true
    }

    /// Moves through the stack. Wired to the two-finger swipe on the closed pill.
    func cycle(by offset: Int) {
        guard !activities.isEmpty else { return }
        selectedIndex = (selectedIndex + offset + activities.count) % activities.count
    }

    private func pruneExpired() {
        let remaining = activities.filter { !$0.isExpired }
        guard remaining.count != activities.count else { return }
        activities = remaining
        clampSelection()
    }

    private func clampSelection() {
        guard !activities.isEmpty else { selectedIndex = 0; return }
        selectedIndex = min(selectedIndex, activities.count - 1)
    }
}
