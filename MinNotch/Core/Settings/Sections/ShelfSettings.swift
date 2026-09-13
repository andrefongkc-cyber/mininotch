import Foundation

/// What happens to a file dragged out of the shelf.
enum ShelfDropBehavior: String, Codable, CaseIterable, Identifiable {
    case copy
    case move
    case ask

    var id: String { rawValue }

    var title: String {
        switch self {
        case .copy: return "Copy"
        case .move: return "Move"
        case .ask: return "Ask Each Time"
        }
    }
}

/// Settings > Shelf.
///
/// V2 feature. The settings are persisted now so the pane renders real controls.
struct ShelfSettings: Codable, Equatable {
    var enabled: Bool = false
    var dropBehavior: ShelfDropBehavior = .copy

    /// Items kept before the oldest is evicted.
    var maxItems: Int = 12

    /// Clear the shelf when the app quits rather than persisting it.
    var clearOnQuit: Bool = false

    /// Expand the notch automatically when a drag enters its area.
    var expandOnDragEnter: Bool = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = c.value(.enabled, false)
        dropBehavior = c.value(.dropBehavior, ShelfDropBehavior.copy)
        maxItems = c.value(.maxItems, 12, in: 4...40)
        clearOnQuit = c.value(.clearOnQuit, false)
        expandOnDragEnter = c.value(.expandOnDragEnter, true)
    }
}
