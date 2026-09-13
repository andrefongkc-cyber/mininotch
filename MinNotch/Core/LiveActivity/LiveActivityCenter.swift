import Observation
import SwiftUI

/// Holds the set of currently active Live Activities and decides which one the pill shows.
///
/// Cycling between several with a two-finger swipe is a V2 feature; `selectedIndex` and
/// `cycle(by:)` exist now so that gesture only has to call a method that already works.
@Observable
final class LiveActivityCenter {
    private(set) var activities: [LiveActivity] = []
    private(set) var selectedIndex: Int = 0

    @ObservationIgnored private var expiryTimer: Timer?

    init() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.pruneExpired()
        }
        RunLoop.main.add(timer, forMode: .common)
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

    /// Moves through the stack. Wired to the V2 swipe gesture.
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
